function imdl = eit_build_model(cfg)
% EIT_BUILD_MODEL Build the tdEIT forward/inverse model for the 10cm
% circular membrane, 16-electrode CEM, 2-terminal custom protocol.
%
% Steps:
%   1. Mesh via mk_common_model(cfg.meshString, cfg.nElec) (unit circle).
%   2. Scale nodes to the real membrane radius (cfg.membraneRadius_m).
%   3. Set every electrode's contact impedance to the placeholder value
%      cfg.zContactInit_ohm (~100 ohm, not yet measured) as a FREE
%      parameter (fwd_model.electrode(:).z_contact).
%   4. Replace the default mk_stim_patterns adjacent-drive patterns with
%      the custom 120-pair 2-terminal stim/meas patterns, since our
%      hardware injects and measures on the same electrode pair.
%   5. EIDORS field fix: background conductivity for difference imaging
%      lives at imdl.jacobian_bkgnd.value, NOT imdl.fwd_model.background
%      (which does not exist as a field mk_common_model sets) -- so it
%      is set/read there throughout this pipeline.
%
% NOTE (flagged, not silently changed): mk_common_model('c2d0c',...)
% hardcodes a fixed electrode angular width of 4 degrees. Our physical
% electrodes are 5mm x 4.5mm rounded squares on a 10cm-diameter membrane,
% i.e. a ~5.7 degree arc along the circumference. This is a known,
% intentional deviation from the exact physical electrode footprint in
% exchange for using the mesh call exactly as specified; it mainly
% affects the electrode boundary condition's angular extent, not overall
% model validity.

imdl = mk_common_model(cfg.meshString, cfg.nElec);

% --- Scale mesh from EIDORS' unit circle to the real membrane radius ---
imdl.fwd_model.nodes = imdl.fwd_model.nodes * cfg.membraneRadius_m;

% --- Reorder electrodes to match the PHYSICAL board layout ---
% mk_common_model starts electrode 0 at top, going clockwise. The real
% board starts electrode 0 at the BOTTOM, going counterclockwise
% (confirmed with the experimenter after off-center-heat localization
% testing showed a systematic mismatch). See
% eit_apply_physical_electrode_order.m for the derivation -- this must
% run before anything downstream assumes fwd_model.electrode(k+1) is
% physical electrode k (which chA/chB in the raw data reference).
imdl.fwd_model = eit_apply_physical_electrode_order(imdl.fwd_model, cfg.nElec);

% --- Contact impedance: free parameter, placeholder initial value ---
nElec = length(imdl.fwd_model.electrode);
for e = 1:nElec
    imdl.fwd_model.electrode(e).z_contact = cfg.zContactInit_ohm;
end

% --- Custom 2-terminal stim/meas patterns for all 120 pairs ---
stim = eit_make_2term_stim_patterns(cfg.nElec);
imdl.fwd_model.stimulation = stim;
imdl.fwd_model.meas_select = true(numel(stim),1);

% --- Solver / reconstruction settings (difference imaging) ---
imdl.reconst_type = 'difference';
imdl.solve = 'inv_solve_diff_GN_one_step';
%
% PRIOR CHOICE -- this took three iterations to get right, documented here
% because the failure modes are non-obvious and easy to reintroduce:
%
% 1. prior_laplace (gradient/smoothness-only): this sparse 2-terminal
%    "self-measurement" protocol (120 measurements, each injecting AND
%    sensing on the same electrode pair) has a Jacobian whose largest
%    entries are near-electrode elements by orders of magnitude, so any
%    unmodeled residual in the data -- real signal, noise, or drift --
%    gets attributed almost entirely to boundary elements. On real data,
%    reconstructed peaks sat at ~4.8-4.9 cm from center on a 5 cm-radius
%    membrane, i.e. essentially ON the electrode ring, regardless of
%    hyperparameter -- never centered, even though the Peltier was always
%    positioned above the membrane CENTER. A null test (differencing two
%    sweeps of the SAME unheated file, i.e. zero real signal) reproduced
%    the exact same boundary-hugging shape, confirming it was a
%    reconstruction artifact, not real membrane inhomogeneity leaking
%    through the raised-vs-heated differencing (which does correctly
%    cancel static effects common to both states -- casting non-uniformity
%    included -- since it's a genuine difference image).
% 2. prior_laplace also leaves the constant/DC mode of elem_data
%    completely unpenalized (a spatially-uniform field has zero gradient).
%    Real data contains a large common-mode normalized-impedance shift
%    across nearly all 120 pairs (consistent with drift between the
%    raised/down acquisitions, not a localized target); with nothing
%    penalizing it, one-step GN blew up to elem_data ~ thousands and a
%    downstream temperature overlay diverging to +-1e11 C. Fixed
%    separately by removing that common-mode component before solving
%    (see eit_diff_recon.m) -- necessary but not sufficient.
% 3. prior_noser (Reg = diag(diag(J'*J)^0.5), i.e. regularization
%    weighted by each element's own sensitivity) is the standard EIT fix
%    for exactly the boundary-bias problem in (1): it penalizes
%    high-sensitivity (near-electrode) elements MORE, freeing
%    low-sensitivity interior elements to explain genuine smooth signal.
%    Switching to it fixed the boundary bias directly: on the same
%    noiseless synthetic test, corr rose from ~0.82 (Laplace) to ~0.91-0.93
%    with the peak landing 0.2 cm from true center (vs Laplace's ~0.2 cm
%    too, to be fair -- the difference is entirely in the REAL-data
%    behavior). On real data, EVERY one of the 7 trials now peaks 0.2-0.4
%    cm from center, while two independent null tests (sweep1-vs-sweep2
%    and sweep2-vs-sweep3 of the same unheated file) peak 4.6-4.8 cm from
%    center -- i.e. NOSER does not simply bias every reconstruction toward
%    the center; it discriminates cleanly between real signal and no
%    signal on this hardware. See run_reconstruct_real_data.m for the
%    full null-test comparison kept as a permanent diagnostic.
%
% CAVEAT: a synthetic test injecting i.i.d. 0.08%-CV noise (matching the
% empirical sweep-to-sweep |Z| variability) onto a weak ~9%-contrast
% target did NOT show reliable centering under NOSER either (correlation
% stayed near zero). This is in tension with the clean real-data result
% above. The likely explanation is that i.i.d. per-channel noise is a
% poor model of the real hardware's actual noise (which may be more
% correlated across channels, and/or smaller in the final 5-sweep-averaged
% data than the single-sweep CV used to calibrate that test) -- but this
% was not independently confirmed, so treat the real-data centering as
% empirically well-supported for THIS dataset, not as proof this protocol
% generally resolves centered targets at arbitrary contrast/noise levels.
imdl.RtR_prior = 'prior_noser';
% hp=0.1: chosen from a joint sweep against (a) the noiseless synthetic
% target (good corr/centering from ~0.03 to ~1) and (b) real data across
% all 7 trials + both null tests (hp=0.1 gave the most consistent
% real-vs-null separation: real trials 10-22x the null-test span, peaks
% 0.2-0.4cm vs 4.6-4.7cm from center). See run_synthetic_sanity_check.m
% for the local hp override used there for its own higher-SNR validation.
imdl.hyperparameter.value = 0.1;

% EIDORS field fix: background conductivity for the Jacobian linearization
% point lives here, NOT under fwd_model.
imdl.jacobian_bkgnd.value = 1; % arbitrary placeholder; see unit-flag notes
                                % in eit_synthetic_sanity_check / calibration

imdl.fwd_model.solve = 'fwd_solve_1st_order';
imdl.fwd_model.system_mat = 'system_mat_1st_order';
imdl.fwd_model.jacobian = 'jacobian_adjoint';

% Normalized (relative) differencing: dv = data2./data1 - 1, dimensionless.
% This matters because we reconstruct real hardware Ohms-scale data
% against a model whose absolute background conductivity (jacobian_bkgnd)
% and z_contact are both placeholder guesses, not calibrated to the real
% cell constant. Normalized sensitivity (dV/V) is invariant to a uniform
% rescaling of the background conductivity, so this choice makes the
% reconstruction robust to that unknown absolute calibration -- whereas
% un-normalized absolute differencing would conflate the real data's
% Ohms scale with the model's arbitrary Volt scale. See eit_config.m /
% calibration notes for the broader S/m-units flag this connects to.
imdl.fwd_model.normalize_measurements = 1;

imdl.name = sprintf('tdEIT %s %dmm membrane %d elec CEM', ...
    cfg.meshString, round(cfg.membraneDiameter_m*1000), cfg.nElec);
imdl.fwd_model.name = imdl.name;

imdl = eidors_obj('inv_model', imdl);

end
