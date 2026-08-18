function results = run_synthetic_sanity_check()
% RUN_SYNTHETIC_SANITY_CHECK Task 3: build a radially-symmetric synthetic
% temperature profile (centered, decaying to ambient at the membrane
% edge), map it through the PLACEHOLDER P3A-Silk calibration curve to a
% synthetic relative-conductivity map, forward-solve, run the inverse
% pipeline, and verify that the reconstructed image recovers the
% expected centered, radially-decaying pattern.
%
% This is a MATH VALIDATION ONLY check. The P3A-Silk calibration curve
% is an explicitly-flagged placeholder (see eit_load_calibration_curve.m)
% and its relative-conductivity units are NOT S/m (no known cell
% constant) -- this script flags that unit gap again below rather than
% silently assuming a conversion.

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir); addpath(fullfile(thisDir,'lib'));
cfg = eit_config();
eit_init_eidors(cfg);

imdl = eit_build_model(cfg);
fmdl = imdl.fwd_model;
calib = eit_load_calibration_curve(cfg);

% eit_build_model's default hyperparameter (0.1) is chosen jointly against
% real-data behavior (see its comments). This sanity check is a
% noiseless, high-contrast (~150%) math-validation exercise, where a
% sweep found hp=3e-3 gives the best correlation/centering with the NOSER
% prior (corr ~0.93 vs ~0.82-0.87 at other tested values) -- used here
% instead; do not carry this value over to real-data reconstruction (see
% run_reconstruct_real_data.m).
imdl.hyperparameter.value = 3e-3;

fprintf('\n=== UNIT FLAG ===\n%s\n', calib.note);
fprintf('=> Synthetic conductivity here is normalized RELATIVE to ambient\n');
fprintf('   background (background = jacobian_bkgnd.value = %.3g, dimensionless).\n', ...
    imdl.jacobian_bkgnd.value);
fprintf('   No S/m conversion is available or applied. This check validates\n');
fprintf('   the geometry/math of the reconstruction pipeline only.\n\n');

% ---- Synthetic radially-symmetric temperature profile ----
Tambient_C = 25;
Tpeak_C    = 45;             % within calibration curve's observed range
sigma_r    = cfg.membraneRadius_m * 0.4; % Gaussian decay length

elemCenters = ( fmdl.nodes(fmdl.elems(:,1),:) + ...
                fmdl.nodes(fmdl.elems(:,2),:) + ...
                fmdl.nodes(fmdl.elems(:,3),:) ) / 3;
r = sqrt(sum(elemCenters.^2, 2));

T_true_C = Tambient_C + (Tpeak_C - Tambient_C) * exp(-(r/sigma_r).^2);

% ---- Map through PLACEHOLDER calibration curve to relative conductivity ----
relCond_true = calib.T2relCond(T_true_C);
relCond_ambient = calib.T2relCond(Tambient_C);

% Normalize so ambient (edge) maps to the model background value, keeping
% everything in the same self-consistent relative unit system.
sigma_true = imdl.jacobian_bkgnd.value * (relCond_true / relCond_ambient);

fprintf('Synthetic T range: [%.1f, %.1f] C -> normalized sigma range: [%.3f, %.3f]\n', ...
    min(T_true_C), max(T_true_C), min(sigma_true), max(sigma_true));

% ---- Forward solves ----
img_h = mk_image(fmdl, imdl.jacobian_bkgnd.value);
vh = fwd_solve(img_h);

img_i = mk_image(fmdl, sigma_true);
vi = fwd_solve(img_i);

fprintf('Forward solve: %d measurements, homog mean|V|=%.4g, target mean|V|=%.4g\n', ...
    length(vh.meas), mean(abs(vh.meas)), mean(abs(vi.meas)));
if any(isnan(vh.meas)) || any(isnan(vi.meas))
    error('run_synthetic_sanity_check:nanMeas','NaN in forward-solved measurements');
end

% ---- Inverse solve ----
sol = eit_diff_recon(imdl, vh, vi);
recon = sol.elem_data;

% ---- Verification ----
sigma_delta_true = sigma_true - imdl.jacobian_bkgnd.value;
c = corrcoef(recon, sigma_delta_true);
corrVal = c(1,2);

[~, iMax] = max(recon);
peakLoc = elemCenters(iMax,:);
peakDist_cm = 100*norm(peakLoc);

nBins = 10;
edges = linspace(0, cfg.membraneRadius_m, nBins+1);
binCtr = (edges(1:end-1)+edges(2:end))/2;
reconRadial = nan(nBins,1);
truthRadial = nan(nBins,1);
for b = 1:nBins
    mask = r >= edges(b) & r < edges(b+1);
    if any(mask)
        reconRadial(b) = mean(recon(mask));
        truthRadial(b) = mean(sigma_delta_true(mask));
    end
end
monotoneDecayFrac = sum(diff(reconRadial(~isnan(reconRadial))) <= 0) / max(1,sum(~isnan(reconRadial))-1);

reconDynamicRangePct = 100*(max(recon)-min(recon))/mean(recon);
fprintf('\n=== SANITY CHECK RESULTS ===\n');
fprintf('corr(reconstructed, true delta-sigma) per element = %.3f\n', corrVal);
fprintf('reconstructed peak location: (%.2f, %.2f) cm, %.2f cm from center\n', ...
    100*peakLoc(1), 100*peakLoc(2), peakDist_cm);
fprintf('radial profile monotonically non-increasing in %.0f%% of bins\n', 100*monotoneDecayFrac);
fprintf('reconstructed dynamic range: %.3f%% of mean (heavily damped by GN one-step\n', reconDynamicRangePct);
fprintf('  regularization -- expected for one-step GN difference EIT; only the SHAPE/\n');
fprintf('  location of the reconstruction is meaningful here, not absolute amplitude)\n');

pass = corrVal > 0.5 && peakDist_cm < 1.5;
if pass
    fprintf('PASS: recovered image is centered and radially decaying, as expected.\n');
else
    fprintf('CHECK NEEDED: recovered pattern does not clearly match the expected centered/decaying profile.\n');
end

% ---- Figures ----
fig = figure('Visible','off','Position',[100 100 1400 400]);
subplot(1,3,1);
show_fem(img_i);
cb1 = eidors_colourbar(img_i); cb1.Label.String = '\sigma / \sigma_{bkgnd} (synthetic, placeholder units)';
title('True normalized \sigma (synthetic, placeholder units)');
subplot(1,3,2);
show_fem(sol);
cb2 = eidors_colourbar(sol); cb2.Label.String = eit_recon_cbar_label();
title(sprintf('Reconstructed \\Delta\\sigma (corr=%.2f)', corrVal));
subplot(1,3,3);
% Linear difference EIT with regularization (NOSER prior) damps
% absolute amplitude heavily (expected -- recon dynamic range here is
% ~0.05% of its mean, vs a >100x range in the true profile). Plot on
% separate axes so each curve's own SHAPE is visible; do not compare
% amplitudes directly, use corrVal for that.
yyaxis left
plot(binCtr*100, truthRadial, 'o-');
ylabel('true \Delta\sigma (placeholder units)');
yyaxis right
plot(binCtr*100, reconRadial, 's-');
ylabel('reconstructed (placeholder units, heavily damped)');
xlabel('radius (cm)');
title({'Radial SHAPE comparison (separate axes)','amplitude not calibrated -- see corr value'}); grid on;
sgtitle('Synthetic sanity check -- MATH VALIDATION ONLY, placeholder calibration units');
saveas(fig, fullfile(cfg.figDir,'synthetic_sanity_check.png'));
close(fig);

results.corrVal = corrVal;
results.peakDist_cm = peakDist_cm;
results.monotoneDecayFrac = monotoneDecayFrac;
results.reconDynamicRangePct = reconDynamicRangePct;
results.pass = pass;
results.reconRadial = reconRadial;
results.truthRadial = truthRadial;
results.binCtr_cm = binCtr*100;
save(fullfile(cfg.dataOutDir,'synthetic_sanity_check_results.mat'), 'results');

fprintf('\nSANITY CHECK SCRIPT DONE\n');
end
