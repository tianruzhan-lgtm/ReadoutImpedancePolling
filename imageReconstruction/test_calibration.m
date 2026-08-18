function test_calibration()
thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir); addpath(fullfile(thisDir,'lib'));
cfg = eit_config();

calib = eit_load_calibration_curve(cfg);
fprintf('bins: %d, T range [%.1f, %.1f] C\n', numel(calib.T_C), min(calib.T_C), max(calib.T_C));
fprintf('relCond range [%.4g, %.4g]\n', min(calib.relCond), max(calib.relCond));
d = diff(calib.relCond);
fprintf('monotonic increasing fraction: %.2f%%\n', 100*sum(d>0)/numel(d));

fig = figure('Visible','off');
errorbar(calib.T_C, calib.relCond, calib.relCondStd, '.-');
xlabel('Temperature (C)'); ylabel('Relative conductivity (1/ohm, arbitrary units)');
title({'P3A-Silk PLACEHOLDER calibration curve', '(not the actual thermosensitive polymer)'});
grid on;
saveas(fig, fullfile(cfg.figDir,'test_calibration_curve.png'));
close(fig);

fprintf('CALIBRATION TEST OK\n');
end
