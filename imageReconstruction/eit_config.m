function cfg = eit_config()
% EIT_CONFIG Central paths and physical/experimental constants for the
% tdEIT thermal imaging pipeline.
%
% Everything downstream (data loader, model builder, calibration,
% reconstruction scripts) pulls its paths and constants from here so
% there is exactly one place to update if a path or setup parameter
% changes.

thisDir = fileparts(mfilename('fullpath'));

% ---- External library / data locations (read-only, never written to) ----
cfg.eidorsRoot = ['C:\Users\bskah\OneDrive - California Institute of Technology\' ...
    'Daraio Lab\Project_Files\EIT\MatlabCode\EIDOR\eidors-v3.12-ng\eidors-v3.12-ng\eidors'];

cfg.dataDir = ['C:\Users\bskah\OneDrive - California Institute of Technology\' ...
    'Daraio Lab\Project_Files\EIT\Data\7_31_temp_data'];

cfg.dataFilePattern = '20260731_AutoElectrodeReadoutRaw_Peltier_%d_%s.txt';
cfg.peltierIDs = 1:7;
cfg.states = {'raised','down'}; % raised = baseline (30cm), down = heated (3mm)

% ---- Output locations (everything written by this pipeline lives here) ----
cfg.outDir       = thisDir;
cfg.figDir       = fullfile(thisDir,'output','figures');
cfg.dataOutDir   = fullfile(thisDir,'output','data');

% ---- Calibration curve (PLACEHOLDER material, not the actual thermosensitive
%      polymer -- see load_calibration_curve.m for the flagging this triggers) ----
cfg.calibFile = fullfile(thisDir, ...
    'UseMeForCalibration_20260804_250mMolCaCl2_100HzBW_1kHz_ID3_1Day50CCure_LPIBCoating_PostCure_TCyc_Batch4ANewAliquot.txt');
cfg.calibIsPlaceholder = true;
cfg.calibMaterialNote = ['P3A-Silk composite calibration curve is a PLACEHOLDER standing in for the ' ...
    'actual thermosensitive polymer used on the membrane. Any temperature values derived from it ' ...
    'are RELATIVE/PLACEHOLDER estimates, not validated temperatures.'];

% ---- Physical setup ----
cfg.membraneDiameter_m = 0.10;      % 10 cm circular flexible PCB membrane
cfg.membraneRadius_m   = cfg.membraneDiameter_m/2;
cfg.nElec              = 16;        % equally spaced on perimeter
cfg.elecWidth_m         = 5.0e-3;   % electrode footprint, rounded square 5mm x 4.5mm
cfg.elecHeight_m        = 4.5e-3;
cfg.zContactInit_ohm    = 100;      % PLACEHOLDER contact impedance, not yet measured
cfg.meshString          = 'c2d0c';  % mk_common_model mesh spec, per experimental spec

% ---- IR (Peltier-surface) temperatures, transcribed from
%      "Experimental Setup.pdf" in cfg.dataDir. These are IR handheld
%      thermometer readings of the PELTIER PLATE ITSELF, not the membrane,
%      approximate, and are placeholders to be superseded by thermistor
%      data later. Flag this assumption anywhere these values are used. ----
cfg.peltierIRTemp_C = containers.Map(num2cell(1:7), {27.8, 29.5, 30.0, 30.8, 32.8, 38.0, 38.1});
cfg.peltierVoltage_V = containers.Map(num2cell(1:7), {0.5, 0.7, 0.9, 1.1, 1.3, 1.5, 1.7});
cfg.peltierCurrent_A = containers.Map(num2cell(1:7), {0.11, 0.15, 0.17, 0.23, 0.26, 0.28, 0.33});
cfg.peltierTempIsPlaceholder = true;
cfg.peltierTempNote = ['IR temperatures are handheld-thermometer readings of the PELTIER PLATE, ' ...
    'not the membrane surface. Approximate; to be superseded by thermistor data later.'];

if ~exist(cfg.figDir,'dir'); mkdir(cfg.figDir); end
if ~exist(cfg.dataOutDir,'dir'); mkdir(cfg.dataOutDir); end

end
