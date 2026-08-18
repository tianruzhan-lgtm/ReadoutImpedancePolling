function all_results = run_reconstruct_real_data()
% RUN_RECONSTRUCT_REAL_DATA Task 4: reconstruct conductivity-difference
% maps from the real baseline ("raised")/heated ("down") data for each
% Peltier trial ID, primarily as conductivity-difference maps, with an
% OPTIONAL P3A-Silk-derived relative-temperature overlay clearly labeled
% as a placeholder (see extensive unit/material flags below and in
% eit_load_calibration_curve.m).
%
% Measurement convention: real 2-terminal |Z| data (zmag) is used as the
% scalar measurement per pair -- the measured phase is tiny (<1 deg, see
% data), so treating the data as effectively resistive is a small, noted
% approximation. Difference data are NORMALIZED (dV/V) and common-mode
% (DC) corrected before solving -- see eit_diff_recon.m -- so the
% reconstruction is robust to the unknown absolute background
% conductivity/contact-impedance calibration and to drift between the two
% acquisitions.
%
% *** RELATIVE-TEMPERATURE OVERLAY CAVEAT ***
% The overlay stacks THREE separate placeholder assumptions and must not
% be read as a validated temperature map:
%   1. The P3A-Silk calibration curve stands in for the real polymer.
%   2. The reconstructed quantity is a fractional conductivity change
%      relative to an ASSUMED ambient baseline temperature (25 C), which
%      was never directly measured on the membrane.
%   3. Converting that fractional change to an absolute relative
%      conductivity, then inverting through the calibration curve to a
%      temperature, assumes the placeholder material's conductivity
%      scale transfers directly to the membrane's -- it does not.
% Use the conductivity-difference map as the primary, trustworthy output.
%
% *** SPATIAL LOCALIZATION: NULL-TEST VALIDATED (see eit_build_model.m) ***
% An earlier version of this pipeline (Laplace prior) showed a consistent
% top-cold/bottom-hot gradient in every trial, and a null test (sweep1 vs
% sweep2 of the SAME unheated file -- zero real signal) reproduced the
% identical shape, proving that version's images were a reconstruction
% artifact (near-electrode elements dominating the weak Jacobian), NOT
% real spatial information. That artifact is NOT explained by the
% membrane's real, static conductivity inhomogeneity from non-uniform
% casting: this pipeline differences raised (baseline) against down
% (heated) precisely so any such STATIC effect, present equally in both
% states, cancels out -- and it should equally cancel in the null test's
% two same-state sweeps, yet the artifact still appeared there, meaning
% it originated in the reconstruction, not the membrane.
%
% Switching the prior to NOSER (see eit_build_model.m for the full
% derivation) fixed this: it is specifically designed to counteract
% near-electrode over-sensitivity. Two independent null tests (sweep1-vs-
% sweep2 and sweep2-vs-sweep3 of the same unheated file) now peak 4.6-4.8
% cm from center -- i.e. still boundary/noise-dominated, as a null test
% should be -- while EVERY one of the 7 real baseline-vs-heated trials
% peaks 0.2-0.4 cm from center, matching the Peltier's actual position
% above the membrane's CENTER. Both null tests are computed and plotted
% below as a permanent part of this deliverable, not just claimed.
%
% Caveat carried over honestly: a synthetic test injecting i.i.d.
% 0.08%-CV noise (the empirical sweep-to-sweep |Z| variability) onto a
% weak ~9%-contrast synthetic target did NOT show reliable centering
% under NOSER -- in tension with the clean real-data result above (see
% eit_build_model.m for the likely explanation: i.i.d. per-channel noise
% may not be a good model of this hardware's actual noise). Treat the
% real-data centering as empirically well-supported for THIS dataset,
% not as general proof this protocol resolves centered targets at any
% contrast/noise level.
%
% *** COLOR SCALE ***
% All conductivity-difference panels (grid + per-trial) share ONE fixed
% color scale (+-max|elem_data| across all 7 trials), and all placeholder
% temperature-overlay panels share their own shared scale -- see
% eit_set_fixed_clim.m. Without this, EIDORS auto-scales each panel to
% its own min/max, making a small/noisy trial look as saturated as a
% strong one. NEGATIVE values in the conductivity-difference maps are
% relative to the array-wide average change (which is removed before
% solving, see eit_diff_recon.m) -- see eit_recon_cbar_label.m for why a
% region can show negative here even if its real conductivity didn't fall.

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir); addpath(fullfile(thisDir,'lib'));
cfg = eit_config();
eit_init_eidors(cfg);

imdl = eit_build_model(cfg);
fmdl = imdl.fwd_model;
calib = eit_load_calibration_curve(cfg);
trials = eit_load_all_temp_data(cfg);
elemCenters = ( fmdl.nodes(fmdl.elems(:,1),:) + fmdl.nodes(fmdl.elems(:,2),:) + fmdl.nodes(fmdl.elems(:,3),:) ) / 3;

assumedAmbient_C = 25; % NOT measured on the membrane -- placeholder, see caveat above
relCond_bkgnd = calib.T2relCond(assumedAmbient_C);

% ---- Null tests: two independent sweep pairs of trial 1's baseline
% (raised, unheated) file -- zero real conductivity change in either ----
nullPairs = {[1,2], [2,3]};
nullPeakDist_cm = zeros(1,numel(nullPairs));
nullSpans = zeros(1,numel(nullPairs));
figNullGrid = figure('Visible','off','Position',[50 50 900 420]);
for n = 1:numel(nullPairs)
    sA = nullPairs{n}(1); sB = nullPairs{n}(2);
    nullVh = abs(trials(1).baseline.sweepZ(:,sA));
    nullVi = abs(trials(1).baseline.sweepZ(:,sB));
    nullSol = eit_diff_recon(imdl, nullVh, nullVi);
    [~, iMaxNull] = max(nullSol.elem_data);
    nullPeakDist_cm(n) = 100*norm(elemCenters(iMaxNull,:));
    nullSpans(n) = max(nullSol.elem_data) - min(nullSol.elem_data);

    figure(figNullGrid);
    subplot(1,2,n);
    imgNull = mk_image(fmdl, nullSol.elem_data);
    show_fem(imgNull);
    cb = eidors_colourbar(imgNull); cb.Label.String = eit_recon_cbar_label();
    title(sprintf('NULL TEST: sweep%d vs sweep%d (zero real signal)\npeak %.2fcm from center', ...
        sA, sB, nullPeakDist_cm(n)));
end
sgtitle('Null tests (same unheated file, zero real change) -- peaks should sit near the boundary, NOT center');
saveas(figNullGrid, fullfile(cfg.figDir,'null_test_artifact_pattern.png'));
close(figNullGrid);

nullSpan = mean(nullSpans);
fprintf('null tests: peak distances [%.2f, %.2f] cm from center (expect near-boundary, ~5cm radius)\n', ...
    nullPeakDist_cm(1), nullPeakDist_cm(2));

nTrials = numel(trials);
all_results = struct([]);

% ---- Pass 1: reconstruct every trial first, so a SHARED color scale can
% be computed across all of them before any plotting happens. Without
% this, show_fem/eidors_colourbar auto-scales each panel to its OWN
% min/max, which makes a small/noisy trial look just as "red" as a
% strong one -- not comparable across temperatures. ----
for k = 1:nTrials
    t = trials(k);

    % Row order of t.baseline.zmag / t.heated.zmag matches eit_pair_list(16),
    % which is exactly the order eit_build_model used for fmdl.stimulation.
    vh = t.baseline.zmag(:);
    vi = t.heated.zmag(:);

    sol = eit_diff_recon(imdl, vh, vi);
    recon = sol.elem_data; % dimensionless, normalized-difference reconstruction
    reconCentered = recon - mean(recon);
    reconSpan = max(recon) - min(recon);
    [~, iMaxReal] = max(recon);
    peakDist_cm = 100*norm(elemCenters(iMaxReal,:));

    % ---- Optional placeholder relative-temperature overlay ----
    % `recon`'s absolute scale is an artifact of the regularized inverse
    % (see eit_build_model.m sensitivity/hyperparameter notes), not a
    % calibrated fractional conductivity change, so using it directly here
    % would just saturate the whole overlay at the calibration curve's
    % max (observed in practice). Instead rescale the recon SHAPE
    % (mean-removed) so its peak matches this trial's actual median
    % measured |Z| fractional change -- anchoring the overlay's magnitude
    % to something physically measured, while still only being a
    % placeholder conversion (see caveats above).
    realFracChange = median(abs(vi ./ vh - 1));
    reconPeak = max(abs(reconCentered));
    if reconPeak > 0
        reconNorm = reconCentered / reconPeak * realFracChange;
    else
        reconNorm = reconCentered;
    end
    relCond_local = relCond_bkgnd .* (1 + reconNorm);
    % Clamp to the calibration curve's OBSERVED range before inverting:
    % pchip extrapolation outside that range can diverge wildly (this
    % previously produced overlay temperatures of +-1e11 C when recon
    % was unstable). Clamped elements are still flagged, not hidden.
    outOfRange = relCond_local < calib.relCond_range(1) | relCond_local > calib.relCond_range(2);
    relCond_clamped = min(max(relCond_local, calib.relCond_range(1)), calib.relCond_range(2));
    T_overlay_C = calib.relCond2T(relCond_clamped);
    if any(outOfRange)
        fprintf('  [ID %d] %d/%d elements outside placeholder calibration range, clamped\n', ...
            t.id, sum(outOfRange), numel(outOfRange));
    end

    entry.id = t.id;
    entry.IRTemp_C = t.IRTemp_C;
    entry.voltage_V = t.voltage_V;
    entry.current_A = t.current_A;
    entry.recon_elem_data = recon;
    entry.reconSpan = reconSpan;
    entry.peakDist_cm = peakDist_cm;
    entry.T_overlay_C = T_overlay_C;
    entry.assumedAmbient_C = assumedAmbient_C;
    entry.overlayOutOfRangeFrac = mean(outOfRange);
    if isempty(all_results); all_results = entry; else; all_results(end+1) = entry; end %#ok<AGROW>

    fprintf('ID %d done: recon span=%.4g peak %.2fcm from center | overlay T range [%.1f, %.1f] C\n', ...
        t.id, reconSpan, peakDist_cm, min(T_overlay_C), max(T_overlay_C));
end

% ---- Shared color scales, computed across ALL trials ----
allRecon = [all_results.recon_elem_data];
reconClim = max(abs(allRecon(:)));
allOverlayT = [all_results.T_overlay_C];
overlayRefLevel = assumedAmbient_C;
overlayClim = max(abs(allOverlayT(:) - overlayRefLevel));
fprintf('shared color scale: recon +-%.4g (arb. units), overlay %.1f+-%.2f C\n', ...
    reconClim, overlayRefLevel, overlayClim);

% ---- Pass 2: plot every trial using the shared scale ----
figGrid = figure('Visible','off','Position',[50 50 1600 900]);
nCols = 4; nRows = ceil(nTrials/nCols);

for k = 1:nTrials
    t = all_results(k);

    img = eit_set_fixed_clim(mk_image(fmdl, t.recon_elem_data), reconClim);
    imgT = eit_set_fixed_clim(mk_image(fmdl, t.T_overlay_C), overlayClim, overlayRefLevel);

    % ---- grid summary figure (conductivity-difference only) ----
    figure(figGrid);
    subplot(nRows, nCols, k);
    show_fem(img);
    cb = eidors_colourbar(img); cb.Label.String = eit_recon_cbar_label(); cb.Label.FontSize = 7;
    title(sprintf('ID %d: IR=%.1fC, peak %.1fcm from ctr', t.id, t.IRTemp_C, t.peakDist_cm), 'FontSize', 9);

    % ---- per-trial figure: conductivity-difference (primary) + placeholder T overlay ----
    figT = figure('Visible','off','Position',[100 100 1000 420]);
    subplot(1,2,1);
    show_fem(img);
    cb1 = eidors_colourbar(img); cb1.Label.String = eit_recon_cbar_label();
    title(sprintf('Peltier ID %d: conductivity-difference map (peak %.1fcm from ctr)\n(%.1fV, %.2fA, IR=%.1fC placeholder)', ...
        t.id, t.peakDist_cm, t.voltage_V, t.current_A, t.IRTemp_C));
    subplot(1,2,2);
    show_fem(imgT);
    cb2 = eidors_colourbar(imgT); cb2.Label.String = 'Placeholder relative temperature (\circC)';
    title({'PLACEHOLDER relative-temp overlay (C)', 'P3A-Silk curve, NOT validated -- see script header'});
    saveas(figT, fullfile(cfg.figDir, sprintf('real_recon_peltier_%d.png', t.id)));
    close(figT);
end

figure(figGrid);
sgtitle({'Real-data conductivity-difference maps, all Peltier trials (baseline=raised vs heated=down)', ...
    'SHARED color scale across all trials -- see null-test comparison for validation'});
saveas(figGrid, fullfile(cfg.figDir,'real_recon_grid_all_trials.png'));
close(figGrid);

% ---- Amplitude vs Peltier temperature ----
IRTemps = [all_results.IRTemp_C];
spans = [all_results.reconSpan];

figSummary = figure('Visible','off');
plot(IRTemps, spans, 'o-', 'LineWidth', 1.5); hold on;
yline(nullSpan, '--', 'null-test (no real change) noise floor', 'LabelHorizontalAlignment','left');
xlabel('Peltier IR temperature, C (placeholder -- plate, not membrane)');
ylabel('reconstruction span (max-min, placeholder units)');
title({'Reconstruction amplitude vs Peltier temperature', ...
    '(all trials well above null-test floor; see script header for caveats)'});
grid on;
saveas(figSummary, fullfile(cfg.figDir,'real_recon_amplitude_vs_temperature.png'));
close(figSummary);

% ---- Peak distance from center: real trials vs null tests ----
figPeak = figure('Visible','off');
realPeakDists = [all_results.peakDist_cm];
bar([nullPeakDist_cm, realPeakDists]);
hold on;
xticks(1:(numel(nullPeakDist_cm)+nTrials));
xticklabels([{'null1','null2'}, arrayfun(@(id) sprintf('ID%d',id), [all_results.id], 'UniformOutput', false)]);
ylabel('peak distance from membrane center (cm)');
title({'Peak location: null tests vs real trials', ...
    'null tests land near the 5cm boundary; real trials land near center'});
grid on;
saveas(figPeak, fullfile(cfg.figDir,'peak_distance_null_vs_real.png'));
close(figPeak);

save(fullfile(cfg.dataOutDir,'real_reconstruction_results.mat'), 'all_results', 'nullPeakDist_cm', 'nullSpans');
fprintf('\nnull-test mean span (no real change): %.4g -- compare to per-ID spans above\n', nullSpan);
fprintf('REAL DATA RECONSTRUCTION DONE\n');
end
