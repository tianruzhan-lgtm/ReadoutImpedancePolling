function run_all()
% RUN_ALL Full pipeline entry point: data loading -> model build ->
% calibration curve -> synthetic sanity check -> real-data reconstruction.
% Run with: matlab -batch run_all
%
% Individual stages can also be run/inspected separately:
%   test_eidors_smoke, test_data_loader, test_build_model, test_calibration
%   run_synthetic_sanity_check   (Task 3)
%   run_reconstruct_real_data    (Task 4)

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir); addpath(fullfile(thisDir,'lib'));

fprintf('\n========== STAGE 1/2: SYNTHETIC SANITY CHECK ==========\n');
sanity = run_synthetic_sanity_check();
if ~sanity.pass
    warning('run_all:sanityCheckFailed', ...
        'Synthetic sanity check did not pass -- inspect output/figures/synthetic_sanity_check.png before trusting real-data results.');
end

fprintf('\n========== STAGE 2/2: REAL DATA RECONSTRUCTION ==========\n');
run_reconstruct_real_data();

fprintf('\n========== RUN_ALL COMPLETE ==========\n');
fprintf('Figures: %s\n', fullfile(thisDir,'output','figures'));
fprintf('Data:    %s\n', fullfile(thisDir,'output','data'));
end
