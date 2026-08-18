function lbl = eit_recon_cbar_label()
% EIT_RECON_CBAR_LABEL Shared colorbar label for reconstructed elem_data.
%
% elem_data from eit_diff_recon is dimensionally a fractional conductivity
% change (Delta-sigma / sigma_background) from the linearized one-step GN
% difference solve, with sigma_background fixed at an arbitrary placeholder
% (imdl.jacobian_bkgnd.value = 1). Its absolute SCALE is dominated by the
% regularization/hyperparameter choice (see eit_build_model.m), not a
% calibrated physical quantity -- so it is labeled "arbitrary units" rather
% than claiming S/m or a validated relative-conductivity percentage.
%
% It is also, separately, RELATIVE TO THE ARRAY-WIDE AVERAGE CHANGE:
% eit_diff_recon.m removes the common-mode (mean) component of the
% normalized difference data before solving (needed to keep the solve
% numerically bounded -- see eit_build_model.m). So a NEGATIVE value here
% does not necessarily mean that region's real conductivity fell -- it
% means that region changed LESS than the array-wide average change
% (which was already subtracted out and is not visible in this map). On
% real data where the average change itself is positive (heating raises
% overall conductivity, confirmed separately: mean(vi./vh-1) ~ -1 to -2%
% i.e. impedance fell on average), a region that barely changed at all
% will still show up negative here, simply for changing less than that
% removed average.

lbl = '\Delta\sigma/\sigma_{bkgnd}, vs array-wide mean (arb. units, not calibrated)';

end
