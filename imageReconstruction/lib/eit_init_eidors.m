function eit_init_eidors(cfg)
% EIT_INIT_EIDORS Add EIDORS to the path and run its startup routine.
% Safe to call multiple times (checks whether eidors_objects already
% exists in memory before re-running startup).
%
% eidors_startup.m uses pwd() internally to locate its subfolders, so we
% must cd into the EIDORS root while it runs, then restore the caller's
% working directory.

if exist('eidors_objects','var') || ~isempty(which('eidors_msg'))
    return
end

origDir = pwd();
cleanupObj = onCleanup(@() cd(origDir));

if ~exist(cfg.eidorsRoot,'dir')
    error('eit_init_eidors:missingRoot', ...
        'EIDORS root not found: %s', cfg.eidorsRoot);
end

cd(cfg.eidorsRoot);
run(fullfile(cfg.eidorsRoot,'startup.m'));

% Redirect EIDORS's mesh/model cache away from the read-only OneDrive
% library into our own output directory -- eidors_startup() defaults
% this to a folder inside cfg.eidorsRoot, which we must not write to.
cacheDir = fullfile(cfg.dataOutDir,'eidors_cache');
if ~exist(cacheDir,'dir'); mkdir(cacheDir); end
eidors_cache('cache_path', cacheDir);
mk_library_model('LIBRARY_PATH', cacheDir);

end
