function test_eidors_smoke()
thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir); addpath(fullfile(thisDir,'lib'));
cfg = eit_config();
eit_init_eidors(cfg);

imdl = mk_common_model(cfg.meshString, cfg.nElec);
fprintf('nodes: %d, elems: %d, electrodes: %d\n', ...
    size(imdl.fwd_model.nodes,1), size(imdl.fwd_model.elems,1), ...
    length(imdl.fwd_model.electrode));
fprintf('SMOKE TEST OK\n');
end
