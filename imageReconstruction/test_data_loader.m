function test_data_loader()
thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir); addpath(fullfile(thisDir,'lib'));
cfg = eit_config();

trials = eit_load_all_temp_data(cfg);

fprintf('\nLoaded %d trials\n', numel(trials));
for k = 1:numel(trials)
    t = trials(k);
    fprintf('ID %d: IR=%.1fC  baseline mean|Z|=%.1f ohm  heated mean|Z|=%.1f ohm  dSweeps b/h=%d/%d\n', ...
        t.id, t.IRTemp_C, mean(t.baseline.zmag), mean(t.heated.zmag), ...
        t.baseline.nSweeps, t.heated.nSweeps);
end

save(fullfile(cfg.dataOutDir,'trials.mat'), 'trials');
fprintf('DATA LOADER TEST OK\n');
end
