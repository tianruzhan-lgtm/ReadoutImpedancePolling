function calib = eit_load_calibration_curve(cfg)
% EIT_LOAD_CALIBRATION_CURVE Load the P3A-Silk composite conductivity-vs-
% temperature PLACEHOLDER curve and reduce it to a monotonic lookup.
%
% *** PLACEHOLDER MATERIAL WARNING ***
% This calibration data is from a P3A-Silk composite (250mM CaCl2,
% thermal-cycling test), NOT the actual thermosensitive polymer used on
% the membrane. Anything derived from it is a RELATIVE/PLACEHOLDER
% estimate, not a validated temperature value. See cfg.calibMaterialNote.
%
% *** UNITS WARNING ***
% The calibration file records raw 2-terminal impedance (zreal, zimag,
% zmag, zphase) of the calibration cell, not conductivity. Converting
% |Z| to a true conductivity in S/m requires the calibration cell's
% geometric/cell constant (electrode area / gap), which is NOT recorded
% here. We therefore only compute a RELATIVE conductivity,
%   relCond = 1 / zmag   (arbitrary units, 1/ohm)
% This is proportional to true conductivity only up to that unknown cell
% constant. calib.needsUnitConversion is set true to flag this
% explicitly -- do not treat calib.relCond as S/m anywhere downstream.
%
% The source file is a long (~15.7 hour) thermal-cycling run (14.3 to
% 45.9 C, with hysteresis expected between heating/cooling branches). For
% a placeholder calibration curve we reduce this to a monotonic
% temperature -> relative-conductivity lookup by binning temperature and
% averaging over all cycles (this averages over, and therefore hides,
% any heating/cooling hysteresis -- acceptable for a placeholder, flagged
% here so it isn't forgotten).
%
% Returns calib with fields:
%   .T_C, .relCond, .relCondStd   binned lookup table
%   .T2relCond(T)                 monotonic interpolant, T [C] -> relCond
%   .relCond2T(rc)                monotonic interpolant, relCond -> T [C]
%   .isPlaceholderMaterial, .needsUnitConversion, .note

Traw = readtable(cfg.calibFile, 'FileType','text', 'Delimiter','\t');
req = {'time','zreal','zimag','zmag','zphase','frequency','temperature','humidity'};
missing = setdiff(req, Traw.Properties.VariableNames);
if ~isempty(missing)
    error('eit_load_calibration_curve:badFile', ...
        'Calibration file missing expected columns: %s', strjoin(missing,', '));
end

relCondRaw = 1 ./ Traw.zmag; % arbitrary units, see units warning above
Traw_T = Traw.temperature;

binWidth = 0.5; % degrees C
edges = floor(min(Traw_T)):binWidth:ceil(max(Traw_T));
[~,~,bin] = histcounts(Traw_T, edges);

nBins = numel(edges)-1;
T_C = nan(nBins,1);
relCond = nan(nBins,1);
relCondStd = nan(nBins,1);
nSamp = zeros(nBins,1);
for b = 1:nBins
    mask = (bin == b);
    nSamp(b) = sum(mask);
    if nSamp(b) > 0
        T_C(b) = mean(Traw_T(mask));
        relCond(b) = mean(relCondRaw(mask));
        relCondStd(b) = std(relCondRaw(mask));
    end
end
keep = nSamp > 0;
T_C = T_C(keep); relCond = relCond(keep); relCondStd = relCondStd(keep); nSamp = nSamp(keep);

% Sort by temperature (bins already increasing, but be explicit) and
% enforce strict monotonicity in T for interpolation.
[T_C, order] = sort(T_C);
relCond = relCond(order);
relCondStd = relCondStd(order);
nSamp = nSamp(order);

calib.T_C = T_C;
calib.relCond = relCond;
calib.relCondStd = relCondStd;
calib.nSamplesPerBin = nSamp;
calib.T_C_range = [min(T_C), max(T_C)];
calib.relCond_range = [min(relCond), max(relCond)];
calib.T2relCond = @(T) interp1(T_C, relCond, T, 'pchip', 'extrap');
% relCond2T is only reliable INSIDE calib.relCond_range: pchip
% extrapolation outside the observed calibration data can diverge
% wildly (seen in practice: unclamped inputs produced results of
% +-1e11 C). Callers converting outside this pipeline should clamp their
% input to calib.relCond_range first; relCond2T itself still extrapolates
% (no clamping applied here) so that out-of-range behavior stays visible
% to callers that don't clamp, rather than being silently hidden.
calib.relCond2T = @(rc) interp1(relCond, T_C, rc, 'pchip', 'extrap');
calib.isPlaceholderMaterial = cfg.calibIsPlaceholder;
calib.needsUnitConversion = true;
calib.note = [cfg.calibMaterialNote, ' relCond units are 1/ohm (proportional to conductivity ' ...
    'via an unknown cell constant), NOT S/m -- see eit_load_calibration_curve.m header.'];
calib.sourceFile = cfg.calibFile;

end
