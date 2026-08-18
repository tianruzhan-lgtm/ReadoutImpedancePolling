function sol = eit_diff_recon(imdl, vh, vi)
% EIT_DIFF_RECON Difference-EIT solve with common-mode (DC) removal.
%
% sol = eit_diff_recon(imdl, vh, vi)
%   vh, vi: baseline/target measurements, either eidors 'data' structs or
%           plain numeric vectors, ordered to match imdl.fwd_model.stimulation.
%
% *** WHY THIS EXISTS (found while debugging real-data reconstructions) ***
% The Laplace prior (used here for its correct interior-favoring shape --
% see eit_build_model.m) only penalizes GRADIENTS: a spatially-constant
% elem_data field is exactly in its null space. Real hardware data shows
% a substantial, roughly uniform normalized impedance shift across nearly
% ALL 120 electrode pairs between the "raised" and "down" acquisitions
% (median ~1.5%, but with a real common-mode component on top -- see
% run_reconstruct_real_data.m). That common-mode component cannot
% represent a physically localized interior conductivity change under
% this model (a real internal target would affect different pairs very
% differently depending on their geometry relative to it), and is far
% more consistent with a global drift (electronics warm-up, contact
% impedance drift over the ~30s between the two acquisitions) than signal.
% Left in, it exploited the Laplace prior's unconstrained constant mode
% and blew the one-step GN solve up to elem_data ~ thousands.
%
% Fix: remove the mean of the normalized difference data BEFORE solving,
% by adjusting vi so that calc_difference_data's own normalized dv
% (=vi./vh-1) is re-centered to zero mean. This targets the actual cause
% (a common-mode component in the DATA) rather than patching the prior,
% and is a no-op on self-consistent synthetic data (mean(dv) ~ 0 there
% already), so it is used uniformly for both synthetic and real
% reconstructions in this pipeline.

if isstruct(vh); vh_meas = vh.meas(:); else; vh_meas = vh(:); end
if isstruct(vi); vi_meas = vi.meas(:); else; vi_meas = vi(:); end

mean_dv = mean(vi_meas ./ vh_meas - 1);

vi_adj = vi;
if isstruct(vi_adj)
    vi_adj.meas = vi_meas - vh_meas * mean_dv;
else
    vi_adj = vi_meas - vh_meas * mean_dv;
end

sol = inv_solve(imdl, vh, vi_adj);
sol.eit_common_mode_removed = mean_dv;

end
