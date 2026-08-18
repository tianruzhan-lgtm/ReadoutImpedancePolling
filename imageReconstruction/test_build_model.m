function test_build_model()
thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir); addpath(fullfile(thisDir,'lib'));
cfg = eit_config();
eit_init_eidors(cfg);

imdl = eit_build_model(cfg);
fmdl = imdl.fwd_model;

fprintf('nodes: %d, elems: %d, electrodes: %d, stim patterns: %d\n', ...
    size(fmdl.nodes,1), size(fmdl.elems,1), length(fmdl.electrode), length(fmdl.stimulation));
fprintf('node radius range: %.4f to %.4f m (expect ~0 to %.4f)\n', ...
    min(sqrt(sum(fmdl.nodes.^2,2))), max(sqrt(sum(fmdl.nodes.^2,2))), cfg.membraneRadius_m);
fprintf('z_contact(1) = %.2f ohm\n', fmdl.electrode(1).z_contact);
fprintf('jacobian_bkgnd.value = %.3f\n', imdl.jacobian_bkgnd.value);

% Homogeneous forward solve sanity check
img = mk_image(fmdl, 1);
vh = fwd_solve(img);
fprintf('homogeneous fwd solve: %d measurements, mean |V|=%.4g, any nan=%d\n', ...
    length(vh.meas), mean(abs(vh.meas)), any(isnan(vh.meas)));

% Perturbed forward solve + one-step difference inverse solve, sanity check only
img2 = img;
ctr = [0.01, 0.01]; % small off-center perturbation, 1cm from center
r = sqrt(sum((fmdl.nodes(fmdl.elems(:,1),:) + fmdl.nodes(fmdl.elems(:,2),:) + fmdl.nodes(fmdl.elems(:,3),:)) / 3 - ctr, 2).^2);
elemCenters = (fmdl.nodes(fmdl.elems(:,1),:) + fmdl.nodes(fmdl.elems(:,2),:) + fmdl.nodes(fmdl.elems(:,3),:))/3;
d = sqrt(sum((elemCenters - ctr).^2,2));
pert = ones(size(fmdl.elems,1),1);
pert(d < 0.015) = 1.5; % 50% conductivity bump in a 1.5cm radius blob
img2.elem_data = pert;
vi = fwd_solve(img2);
fprintf('perturbed fwd solve: mean |V|=%.4g, max abs diff from homog=%.4g\n', ...
    mean(abs(vi.meas)), max(abs(vi.meas - vh.meas)));

sol = inv_solve(imdl, vh, vi);
fprintf('inverse solve: elem_data range [%.4g, %.4g], any nan=%d\n', ...
    min(sol.elem_data), max(sol.elem_data), any(isnan(sol.elem_data)));

fig = figure('Visible','off');
show_fem(sol);
title('test\_build\_model: recovered blob (sanity, not calibrated)');
saveas(fig, fullfile(cfg.figDir,'test_build_model_recon.png'));
close(fig);

fprintf('BUILD MODEL TEST OK\n');
end
