function results = reconstruct_new_data(dataSource, outDir)
% RECONSTRUCT_NEW_DATA Reconstruct conductivity-difference maps from a
% packaged experiment variable (current format), a .mat file holding one,
% or a legacy directory of raw .txt files.
%
% USAGE (primary -- packaged experiment variable):
%   load('ExpDate_20260806.mat')            % puts ExpDate_20260806 in the workspace
%   reconstruct_new_data(ExpDate_20260806)
%
% USAGE (equivalent alternatives):
%   reconstruct_new_data('C:\...\ExpDate_20260806.mat')   % path to the .mat
%   reconstruct_new_data                                   % prompts for a path
%   reconstruct_new_data(ExpDate_20260806, 'C:\where\to\save')
%   reconstruct_new_data('C:\...\7_31_temp_data')          % legacy: folder of .txt
%
% PACKAGED FORMAT (see eit_load_experiment.m for the full contract):
%   expt.sampleinfo             experiment-wide info
%   expt.trial(k).type          'Control' (baseline) / 'Heat' (heated)
%   expt.trial(k).temperature   e.g. '35C' (measured) or '1.1V' (Peltier
%                               drive voltage standing in for temperature
%                               until direct measurement is available)
%   expt.trial(k).positionX/Y   heat-source position from domain center, METERS
%   expt.trial(k).positionZ     heat-source height, CENTIMETERS
%   expt.trial(k).data          table: time,zreal,zimag,zmag,zphase,chA,chB
%   expt.trial(k).filename      source .txt name
% Control/Heat trials are paired by filename index; `type` decides which
% is baseline vs heated.
%
% GROUND-TRUTH LOCALIZATION: when positionX/Y are present, each figure
% marks the KNOWN heat-source position and the reconstructed peak, and
% the localization error between them is reported. This is a real
% accuracy check the earlier center-only dataset could not provide.
%
% WHAT THIS DOES NOT DO: no calibration-curve/temperature overlay -- that
% used a placeholder material curve and an assumed ambient temperature
% specific to the original 7/31 experiment (see run_reconstruct_real_data.m).
% This script produces the primary, trustworthy output: conductivity-
% difference maps. Ask if you want the overlay wired in here too.
%
% OUTPUTS: one figure per pair, a combined grid figure, and a .mat of the
% raw reconstructions -- all under `outDir` (default:
% <this folder>/output/new_data/<timestamp>/), never alongside the input.
%
% All panels share ONE fixed color scale (+-max|elem_data| across every
% pair in this run) so pairs are visually comparable -- see
% eit_set_fixed_clim.m. Negative values are relative to the array-wide
% mean change, which is removed before solving -- see
% eit_recon_cbar_label.m and eit_diff_recon.m.

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir); addpath(fullfile(thisDir,'lib'));

if nargin < 1 || isempty(dataSource)
    dataSource = input('Enter path to the experiment .mat file (or a folder of raw .txt files): ', 's');
end

if nargin < 2 || isempty(outDir)
    outDir = fullfile(thisDir, 'output', 'new_data', datestr(now, 'yyyymmdd_HHMMSS'));
end
if ~exist(outDir, 'dir'); mkdir(outDir); end

cfg = eit_config();
eit_init_eidors(cfg);
imdl = eit_build_model(cfg);
fmdl = imdl.fwd_model;
elemCenters = ( fmdl.nodes(fmdl.elems(:,1),:) + fmdl.nodes(fmdl.elems(:,2),:) + fmdl.nodes(fmdl.elems(:,3),:) ) / 3;

jobs = collect_jobs(dataSource, cfg);
fprintf('Found %d Control/Heat pair(s)\n', numel(jobs));

% ---- Pass 1: reconstruct everything first, so one shared color scale
% can be computed before plotting (otherwise EIDORS auto-scales each
% panel to its own range and pairs stop being comparable) ----
results = struct([]);
for k = 1:numel(jobs)
    j = jobs(k);
    fprintf('[%d/%d] %s ...\n', k, numel(jobs), j.label);

    vh = j.baseline.zmag(:);
    vi = j.heated.zmag(:);
    sol = eit_diff_recon(imdl, vh, vi);
    recon = sol.elem_data;

    [~, iMax] = max(recon);
    peakXY = elemCenters(iMax, :);

    entry = j;
    entry.recon_elem_data = recon;
    entry.reconSpan = max(recon) - min(recon);
    entry.peakX_m = peakXY(1);
    entry.peakY_m = peakXY(2);
    entry.peakDistFromCenter_cm = 100*norm(peakXY);
    if ~isnan(j.trueX_m) && ~isnan(j.trueY_m)
        entry.localizationError_cm = 100*norm(peakXY - [j.trueX_m, j.trueY_m]);
    else
        entry.localizationError_cm = NaN;
    end

    if isempty(results); results = entry; else; results(end+1) = entry; end %#ok<AGROW>
end

% ---- Shared color scale across every pair in this run ----
allRecon = [results.recon_elem_data];
reconClim = max(abs(allRecon(:)));
fprintf('shared color scale: +-%.4g (arb. units, not calibrated)\n', reconClim);

% ---- Pass 2: plot with the shared scale ----
nResults = numel(results);
nCols = min(4, nResults);
nRows = ceil(nResults / nCols);
figGrid = figure('Visible','off','Position',[50 50 420*nCols 440*nRows]);

for k = 1:nResults
    r = results(k);
    img = eit_set_fixed_clim(mk_image(fmdl, r.recon_elem_data), reconClim);

    figure(figGrid);
    subplot(nRows, nCols, k);
    show_fem(img);
    cb = eidors_colourbar(img); cb.Label.String = eit_recon_cbar_label(); cb.Label.FontSize = 7;
    mark_positions(r);
    title(grid_title(r), 'FontSize', 8, 'Interpreter','tex');

    figSingle = figure('Visible','off','Position',[100 100 620 560]);
    show_fem(img);
    cbs = eidors_colourbar(img); cbs.Label.String = eit_recon_cbar_label();
    mark_positions(r);
    title(single_title(r), 'Interpreter','tex');
    safeLabel = regexprep(r.key, '[^A-Za-z0-9_-]', '_');
    saveas(figSingle, fullfile(outDir, sprintf('%s_recon.png', safeLabel)));
    close(figSingle);
end

figure(figGrid);
sgtitle({'Conductivity-difference maps, all Control/Heat pairs', ...
    sprintf('SHARED color scale (+-%.4g, arb. units, not calibrated); x = known heat-source position, o = reconstructed peak', reconClim)}, ...
    'Interpreter','tex');
saveas(figGrid, fullfile(outDir, 'grid_all_pairs.png'));
close(figGrid);

% ---- Localization summary (only meaningful when true positions known) ----
if any(~isnan([results.localizationError_cm]))
    figLoc = figure('Visible','off','Position',[100 100 640 600]);
    th = linspace(0, 2*pi, 200);
    plot(100*cfg.membraneRadius_m*cos(th), 100*cfg.membraneRadius_m*sin(th), 'k-'); hold on;
    for k = 1:nResults
        r = results(k);
        if isnan(r.trueX_m); continue; end
        plot(100*r.trueX_m, 100*r.trueY_m, 'kx', 'MarkerSize', 11, 'LineWidth', 2);
        plot(100*r.peakX_m, 100*r.peakY_m, 'ro', 'MarkerSize', 8, 'LineWidth', 1.5);
        plot(100*[r.trueX_m, r.peakX_m], 100*[r.trueY_m, r.peakY_m], 'r-');
    end
    axis equal; grid on;
    xlabel('x (cm)'); ylabel('y (cm)');
    title({'Localization: known heat-source position (x) vs reconstructed peak (o)', ...
        sprintf('median error %.2f cm over %d pair(s)', ...
        median([results.localizationError_cm], 'omitnan'), sum(~isnan([results.localizationError_cm])))});
    saveas(figLoc, fullfile(outDir, 'localization_true_vs_reconstructed.png'));
    close(figLoc);

    fprintf('\n%-28s %-8s %10s %10s %12s\n', 'pair', 'temp', 'true(x,y)cm', 'peak(x,y)cm', 'error(cm)');
    for k = 1:nResults
        r = results(k);
        fprintf('%-28s %-8s (%+5.1f,%+5.1f) (%+5.1f,%+5.1f) %10.2f\n', ...
            truncate(r.key,28), r.temperatureRaw, 100*r.trueX_m, 100*r.trueY_m, ...
            100*r.peakX_m, 100*r.peakY_m, r.localizationError_cm);
    end
    fprintf('median localization error: %.2f cm (membrane radius %.1f cm)\n', ...
        median([results.localizationError_cm], 'omitnan'), 100*cfg.membraneRadius_m);
end

save(fullfile(outDir, 'reconstruction_results.mat'), 'results', 'reconClim');
fprintf('\nDone. %d pair(s) reconstructed. Figures + results.mat saved to:\n  %s\n', nResults, outDir);

end

% ==================================================================
function jobs = collect_jobs(dataSource, cfg)
% Normalize any accepted input into a common job list with fields:
%   key, label, temperatureRaw, trueX_m, trueY_m, positionZ_cm,
%   baseline, heated

jobs = struct([]);

if isstruct(dataSource) || ...
        ((ischar(dataSource) || isstring(dataSource)) && endsWith(lower(char(dataSource)), '.mat'))
    % ---- Packaged experiment (current format) ----
    [pairs, sampleinfo] = eit_load_experiment(dataSource, cfg.nElec);
    if isfield(sampleinfo, 'Description')
        fprintf('Experiment: %s', sampleinfo.Description);
        if isfield(sampleinfo,'Date'); fprintf('  (Date %s)', sampleinfo.Date); end
        fprintf('\n');
    end
    for k = 1:numel(pairs)
        p = pairs(k);
        j.key = p.key;
        j.label = p.label;
        j.temperatureRaw = p.temperatureRaw;
        j.temperatureIsProxy = p.temperatureIsProxy;
        j.trueX_m = p.positionX_m;
        j.trueY_m = p.positionY_m;
        j.positionZ_cm = p.positionZ_cm;
        j.baseline = p.baseline;
        j.heated = p.heated;
        if isempty(jobs); jobs = j; else; jobs(end+1) = j; end %#ok<AGROW>
    end
    return
end

% ---- Legacy: a directory of raw .txt files ----
dataDir = char(dataSource);
if ~exist(dataDir, 'dir')
    error('reconstruct_new_data:badSource', ...
        ['Input is neither a packaged experiment struct, a .mat path, nor an existing folder: %s'], dataDir);
end
fprintf('Legacy mode: scanning folder for raised/down .txt pairs\n');
filePairs = eit_find_raised_down_pairs(dataDir);
if isempty(filePairs)
    error('reconstruct_new_data:noPairs', ...
        'No raised/down file pairs found in %s', dataDir);
end
for k = 1:numel(filePairs)
    p = filePairs(k);
    try
        baseline = eit_load_state_file(p.raisedFile, cfg.nElec);
        heated = eit_load_state_file(p.downFile, cfg.nElec);
    catch ME
        warning('reconstruct_new_data:loadFailed', 'Skipping %s: %s', p.label, ME.message);
        continue
    end
    j.key = p.label;
    j.label = p.label;
    j.temperatureRaw = '';        % legacy .txt files carry no metadata
    j.temperatureIsProxy = true;
    j.trueX_m = NaN;              % no ground-truth position available
    j.trueY_m = NaN;
    j.positionZ_cm = NaN;
    j.baseline = baseline;
    j.heated = heated;
    if isempty(jobs); jobs = j; else; jobs(end+1) = j; end %#ok<AGROW>
end
if isempty(jobs)
    error('reconstruct_new_data:allFailed', 'Every pair failed to load -- see warnings above.');
end
end

% ==================================================================
function mark_positions(r)
hold on;
if ~isnan(r.trueX_m) && ~isnan(r.trueY_m)
    plot(r.trueX_m, r.trueY_m, 'kx', 'MarkerSize', 12, 'LineWidth', 2);
end
plot(r.peakX_m, r.peakY_m, 'ko', 'MarkerSize', 8, 'LineWidth', 1.5);
hold off;
end

function s = grid_title(r)
base = strrep(r.key, '_', '\_');
if isempty(r.temperatureRaw)
    s = base;
else
    s = sprintf('%s  [%s]', base, r.temperatureRaw);
end
if ~isnan(r.localizationError_cm)
    s = {s, sprintf('true (%+.1f,%+.1f)cm  err %.2fcm', ...
        100*r.trueX_m, 100*r.trueY_m, r.localizationError_cm)};
end
end

function s = single_title(r)
base = strrep(r.key, '_', '\_');
line1 = base;
if ~isempty(r.temperatureRaw)
    if r.temperatureIsProxy
        line1 = sprintf('%s  [%s -- Peltier drive voltage, temperature not yet measured]', base, r.temperatureRaw);
    else
        line1 = sprintf('%s  [%s]', base, r.temperatureRaw);
    end
end
if ~isnan(r.localizationError_cm)
    s = {line1, sprintf('known source (x) = (%+.1f, %+.1f) cm; reconstructed peak (o) = (%+.1f, %+.1f) cm; error %.2f cm', ...
        100*r.trueX_m, 100*r.trueY_m, 100*r.peakX_m, 100*r.peakY_m, r.localizationError_cm)};
else
    s = {line1, sprintf('reconstructed peak (o) = (%+.1f, %+.1f) cm', 100*r.peakX_m, 100*r.peakY_m)};
end
end

function s = truncate(s, n)
s = char(s);
if numel(s) > n; s = s(max(1,end-n+1):end); end
end
