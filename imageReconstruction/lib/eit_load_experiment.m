function [pairs, sampleinfo] = eit_load_experiment(expt, nElec)
% EIT_LOAD_EXPERIMENT Normalize a packaged experiment variable into
% Control/Heat trial pairs with reduced impedance data.
%
% USAGE:
%   [pairs, sampleinfo] = eit_load_experiment(ExpDate_20260806)   % loaded variable
%   [pairs, sampleinfo] = eit_load_experiment('C:\...\ExpDate_20260806.mat')
%
% EXPECTED INPUT (the current packaged format):
%   expt.sampleinfo  struct of experiment-wide info (SampleNumber, Date,
%                    Description, ...) -- applies to every trial
%   expt.trial       struct array, one entry per acquisition, with fields:
%     .type          'Control' (baseline) or 'Heat' (applied heat source)
%     .temperature   EITHER a char/string 'VALUEUNIT' ('C' = measured
%                    degrees C, 'V' = Peltier drive voltage standing in
%                    for an unmeasured temperature -- flagged via
%                    .temperatureIsProxy), or empty when not yet
%                    recorded; OR a plain numeric double, which (confirmed
%                    with the experimenter for the 20260813 PID dataset)
%                    means a DIRECTLY MEASURED degrees-C reading, not a
%                    proxy. See parse_temperature() below -- do not assume
%                    which shape a new dataset uses without checking
%                    class(), since char()'ing a numeric value silently
%                    mangles it rather than erroring.
%     .positionX/Y   Peltier position relative to the domain center, METERS,
%                    in the MOTOR STAGE's own axis convention (confirmed
%                    with the experimenter): stage +x = up, stage +y =
%                    left. This is NOT the same frame as the reconstructed
%                    image (standard x=right, y=up, matching mesh node
%                    coordinates) -- converted below via
%                    model_x = stage_y, model_y = -stage_x (empirically
%                    resolved against known off-center positions -- see
%                    the NOTE ON SIGN below). Raw stage values are kept
%                    too (positionX_stage_m/positionY_stage_m) for
%                    traceability.
%     .positionZ     Peltier height, CENTIMETERS (30 = raised baseline,
%                    0 = lowered). Not used by the 2D reconstruction;
%                    carried through for labelling/QC only.
%     .data          table with columns time, zreal, zimag, zmag, zphase,
%                    chA, chB (same format as the legacy .txt files)
%     .filename      the raw .txt this trial came from
%
% If the .mat holds a single wrapper variable (e.g. `ExpDate_20260806`),
% that variable's NAME encodes the date and varies per file, so it is
% never hardcoded: the wrapper is located by looking for the struct that
% actually carries `trial`.
%
% PAIRING RULE, PRIMARY (confirmed with the user for the 20260806
% dataset): Control and Heat trials are paired by FILENAME INDEX -- the
% filename with its trailing control/heat token and extension stripped is
% the pairing key, e.g.
%   20260806_AutoTempData_offcenter_1_control.txt  -\
%   20260806_AutoTempData_offcenter_1_heat.txt     -/  key: ..._offcenter_1
% Which member of a pair is baseline vs heated is decided by the `type`
% field, not the filename.
%
% PAIRING RULE, FALLBACK (confirmed with the user for the 20260813 PID
% dataset): some collaborators' filenames carry NO shared control/heat
% token at all (e.g. 20260812_Exp1_PID_01.txt, ..._02.txt, ... -- a
% running index with no per-experiment tag), so the primary rule above
% finds zero valid pairs. When that happens, trials are instead paired by
% CONSECUTIVE POSITION in the trial array, in non-overlapping steps of 2:
% (trial 1, trial 2), (trial 3, trial 4), (trial 5, trial 6), ... Each
% pair must still contain exactly one Control and one Heat (order-
% independent, decided by `type` as always); a pair that doesn't is
% skipped with a warning, not guessed at. This fallback only engages when
% the primary, more specific rule finds NOTHING -- if filenames DO carry
% shared IDs, that rule is used and consecutive-pairing is never tried,
% so this cannot silently override a dataset the primary rule already
% handles correctly.
%
% Returns a struct array `pairs`, one entry per Control/Heat pair:
%   .key, .label            pairing key and a human-readable label
%   .pairingMethod          'filename-key' or 'consecutive' (see above)
%   .temperatureRaw         original string, e.g. '0.5V', '' if absent
%   .temperatureValue       numeric part, e.g. 0.5 (NaN if unavailable)
%   .temperatureUnit        'C' or 'V' ('' if unavailable)
%   .temperatureIsProxy     true when unit is 'V', OR temperature is
%                           absent/unparseable -- i.e. whenever
%                           temperatureValue is not a directly measured
%                           degrees-C reading
%   .positionX_m, .positionY_m   heat-source position, CONVERTED into the
%                           model/image frame (x=right, y=up), meters
%   .positionX_stage_m, .positionY_stage_m   raw, as recorded by the
%                           motor stage (stage +x=up, +y=left), meters
%   .positionZ_cm           heat-source height (cm)
%   .baseline, .heated      reduced impedance structs (eit_reduce_state_table)
%   .baselineFile, .heatedFile

if nargin < 2 || isempty(nElec); nElec = 16; end

% ---- Accept a loaded struct, or a path to a .mat ----
if ischar(expt) || isstring(expt)
    matPath = char(expt);
    if ~exist(matPath, 'file')
        error('eit_load_experiment:noFile', 'File not found: %s', matPath);
    end
    expt = load(matPath);
end
if ~isstruct(expt)
    error('eit_load_experiment:badInput', ...
        'Expected a packaged experiment struct or a path to a .mat file, got %s', class(expt));
end

expt = unwrap_to_experiment(expt);

if ~isfield(expt, 'trial')
    error('eit_load_experiment:noTrial', ...
        'Experiment struct has no `trial` field (fields present: %s)', ...
        strjoin(fieldnames(expt)', ', '));
end
if isfield(expt, 'sampleinfo')
    sampleinfo = expt.sampleinfo;
else
    warning('eit_load_experiment:noSampleinfo', 'Experiment struct has no `sampleinfo` field');
    sampleinfo = struct();
end

trials = expt.trial;
requiredTrialFields = {'type','temperature','positionX','positionY','data','filename'};
missing = setdiff(requiredTrialFields, fieldnames(trials));
if ~isempty(missing)
    error('eit_load_experiment:badTrial', ...
        '`trial` is missing expected field(s): %s', strjoin(missing', ', '));
end
nTrials = numel(trials);

% ---- Group trials into Control/Heat pairs: try the primary (filename
% key) rule first, fall back to consecutive-array-order pairing only if
% that finds NOTHING ----
groups = group_by_filename_key(trials);
method = 'filename-key';
if isempty(groups)
    warning('eit_load_experiment:fallbackConsecutive', ...
        ['No trials shared a filename pairing key (expected e.g. "..._control.txt" / ' ...
         '"..._heat.txt" with a common prefix) -- falling back to CONSECUTIVE pairing: ' ...
         'trial 1+2, 3+4, 5+6, ... in array order. Confirmed with the experimenter for ' ...
         'datasets where collaborators omitted shared per-experiment file IDs.']);
    groups = group_consecutive(trials);
    method = 'consecutive';
end

pairs = struct([]);
for g = 1:numel(groups)
    grp = groups(g);
    tC = trials(grp.iControl);
    tH = trials(grp.iHeat);

    [tempVal, tempUnit, isProxy, tempRawStr] = parse_temperature(tH.temperature, grp.key);

    entry.key = grp.key;
    entry.pairingMethod = method;
    entry.temperatureRaw = tempRawStr;
    entry.temperatureValue = tempVal;
    entry.temperatureUnit = tempUnit;
    entry.temperatureIsProxy = isProxy;
    % Motor-stage frame (stage +x=up, +y=left) -> model/image frame
    % (x=right, y=up): model_x = stage_y, model_y = -stage_x.
    %
    % NOTE ON SIGN: a first-pass verbal derivation from "stage +x=up,
    % +y=left" gave the opposite signs (model_x=-stage_y, model_y=stage_x)
    % -- that reasoning has an unstated handedness/viewing-direction
    % assumption (which way is "up" as seen from the stage vs. the
    % reconstruction's plotted frame) that words alone don't pin down.
    % Resolved empirically instead, once the electrode-order fix
    % (eit_apply_physical_electrode_order.m) was in place: tested all 8
    % dihedral sign/swap combinations against the 8 known off-center
    % heat-source positions in the 20260806 dataset. (stage_y, -stage_x)
    % gave 0.82cm median localization error vs 1.6-2.9cm for every other
    % candidate -- a clear winner, not a marginal best-of-many-similar fit.
    entry.positionX_stage_m = tH.positionX;
    entry.positionY_stage_m = tH.positionY;
    entry.positionX_m =  tH.positionY;
    entry.positionY_m = -tH.positionX;
    if isfield(tH, 'positionZ'); entry.positionZ_cm = tH.positionZ; else; entry.positionZ_cm = NaN; end
    entry.baselineFile = char(tC.filename);
    entry.heatedFile = char(tH.filename);
    entry.label = sprintf('%s (%s, x=%+.3gm y=%+.3gm)', grp.key, entry.temperatureRaw, ...
        entry.positionX_m, entry.positionY_m);

    entry.baseline = eit_reduce_state_table(tC.data, nElec, entry.baselineFile);
    entry.heated   = eit_reduce_state_table(tH.data, nElec, entry.heatedFile);

    if isempty(pairs); pairs = entry; else; pairs(end+1) = entry; end %#ok<AGROW>
end

if isempty(pairs)
    error('eit_load_experiment:noPairs', ...
        'No usable Control/Heat pairs found across %d trial(s) (tried filename-key, then consecutive pairing)', nTrials);
end

end

% ------------------------------------------------------------------
function groups = group_by_filename_key(trials)
% PRIMARY pairing rule: group trials whose filename, with its trailing
% control/heat token and extension stripped, matches. A key with a group
% size < 2 (no match at all, e.g. this dataset's filenames carry no
% control/heat token to strip) produces no group for that trial, so a
% dataset where NO filename carries such a token yields zero groups here
% -- the caller then falls back to consecutive pairing.
nTrials = numel(trials);
keys = cell(nTrials,1);
for k = 1:nTrials
    keys{k} = pairing_key(trials(k).filename);
end
uniqueKeys = unique(keys, 'stable');

groups = struct('key', {}, 'iControl', {}, 'iHeat', {});
for u = 1:numel(uniqueKeys)
    key = uniqueKeys{u};
    idx = find(strcmp(keys, key));
    if numel(idx) < 2; continue; end % nothing to pair for this key

    types = arrayfun(@(t) lower(strtrim(char(t.type))), trials(idx), 'UniformOutput', false);
    iControl = idx(strcmp(types, 'control'));
    iHeat    = idx(strcmp(types, 'heat'));

    if numel(iControl) ~= 1 || numel(iHeat) ~= 1
        warning('eit_load_experiment:badGroup', ...
            ['Pairing key "%s" resolved to %d Control and %d Heat trial(s), expected 1 and 1 ' ...
             '-- skipped (not guessing which to use)'], key, numel(iControl), numel(iHeat));
        continue
    end
    groups(end+1) = struct('key', key, 'iControl', iControl, 'iHeat', iHeat); %#ok<AGROW>
end
end

% ------------------------------------------------------------------
function groups = group_consecutive(trials)
% FALLBACK pairing rule: non-overlapping consecutive trials in array
% order, (1,2), (3,4), (5,6), .... Each pair must contain exactly one
% Control and one Heat trial (either order); anything else is skipped
% with a warning. Also warns (without skipping) if the two filenames'
% trailing numeric IDs aren't consecutive integers, since that's the
% shape the confirmed use case (20260813 PID dataset) has and a gap
% there could mean a dropped/misaligned file upstream.
nTrials = numel(trials);
groups = struct('key', {}, 'iControl', {}, 'iHeat', {});

for i = 1:2:nTrials-1
    i1 = i; i2 = i+1;
    t1 = lower(strtrim(char(trials(i1).type)));
    t2 = lower(strtrim(char(trials(i2).type)));

    if strcmp(t1,'control') && strcmp(t2,'heat')
        iControl = i1; iHeat = i2;
    elseif strcmp(t1,'heat') && strcmp(t2,'control')
        iControl = i2; iHeat = i1;
    else
        warning('eit_load_experiment:badConsecutivePair', ...
            'Trials %d ("%s") and %d ("%s") are not one Control + one Heat -- skipped', ...
            i1, trials(i1).type, i2, trials(i2).type);
        continue
    end

    n1 = trailing_number(trials(i1).filename);
    n2 = trailing_number(trials(i2).filename);
    if ~isnan(n1) && ~isnan(n2) && abs(n2-n1) ~= 1
        warning('eit_load_experiment:nonConsecutiveIDs', ...
            'Trials %d and %d were paired by array order but their filename IDs (%g, %g) are not consecutive -- check for a dropped/misaligned file', ...
            i1, i2, n1, n2);
    end

    key = regexprep(char(trials(iControl).filename), '\.[^.]*$', '');
    groups(end+1) = struct('key', key, 'iControl', iControl, 'iHeat', iHeat); %#ok<AGROW>
end

if mod(nTrials,2) == 1
    warning('eit_load_experiment:oddTrialCount', ...
        'Odd number of trials (%d) -- trial %d has no consecutive partner and was skipped', nTrials, nTrials);
end
end

function n = trailing_number(filename)
tok = regexp(char(filename), '(\d+)(?=\.[^.]*$)', 'match', 'once');
if isempty(tok); n = NaN; else; n = str2double(tok); end
end

% ------------------------------------------------------------------
function expt = unwrap_to_experiment(s)
% Find the struct carrying `trial`. Handles being handed the experiment
% struct directly, or a load() result wrapping it under a date-named
% variable whose name we must not hardcode.
if isfield(s, 'trial'); expt = s; return; end

fn = fieldnames(s);
candidates = {};
for i = 1:numel(fn)
    v = s.(fn{i});
    if isstruct(v) && isscalar(v) && isfield(v, 'trial')
        candidates{end+1} = fn{i}; %#ok<AGROW>
    end
end

if numel(candidates) == 1
    expt = s.(candidates{1});
elseif isempty(candidates)
    error('eit_load_experiment:noWrapper', ...
        'Could not find a struct with a `trial` field (top-level fields: %s)', ...
        strjoin(fn', ', '));
else
    error('eit_load_experiment:ambiguousWrapper', ...
        'Multiple candidate experiment structs found (%s) -- pass one explicitly', ...
        strjoin(candidates, ', '));
end
end

% ------------------------------------------------------------------
function key = pairing_key(filename)
% Strip extension and a trailing control/heat token; the remainder is
% the shared index that pairs a Control with its Heat. If the filename
% carries no such token, this simply returns the filename (minus
% extension) unchanged, and group_by_filename_key will naturally find no
% match for it (group size 1).
key = char(filename);
key = regexprep(key, '\.[^.]*$', '');            % drop extension
key = regexprep(key, '[_-]?(control|heat)$', '', 'ignorecase');
end

% ------------------------------------------------------------------
function [val, unit, isProxy, rawStr] = parse_temperature(raw, key)
% Parse a trial's temperature field, which has been seen in TWO shapes
% across datasets so far -- do not assume which one a new file uses
% without checking `class(raw)` first, since blindly calling char() on a
% numeric value silently mangles it into an invisible/wrong control
% character (e.g. char(35)=='#'), not an error -- this bug was caught by
% eye on the 20260813 dataset, not by any crash.
%
%  (a) char/string, e.g. '35C' or '1.1V': numeric value + unit, 'C' =
%      measured degrees C, 'V' = Peltier drive voltage standing in for an
%      unmeasured temperature (temperatureIsProxy=true). An EMPTY string
%      means temperature simply hasn't been recorded yet -- expected, not
%      warned about. Any other unparseable string IS warned about, since
%      that looks like an upstream data issue rather than "not measured".
%  (b) plain numeric double, e.g. 20: confirmed with the experimenter
%      (20260813 PID dataset) that this is a DIRECTLY MEASURED degrees-C
%      reading, not a proxy -- temperatureIsProxy=false.

if isnumeric(raw)
    if isempty(raw) || isnan(raw)
        val = NaN; unit = ''; isProxy = true; rawStr = '';
    else
        val = double(raw); unit = 'C'; isProxy = false;
        rawStr = sprintf('%gC', val);
    end
    return
end

raw = strtrim(char(raw));
if isempty(raw)
    val = NaN; unit = ''; isProxy = true; rawStr = '';
    return
end
tok = regexp(raw, '^\s*([-+]?[\d.]+)\s*([CV])\s*$', 'tokens', 'once', 'ignorecase');
if isempty(tok)
    warning('eit_load_experiment:badTemperature', ...
        'Could not parse temperature "%s" for pair "%s" (expected e.g. "35C" or "1.1V")', raw, key);
    val = NaN; unit = ''; isProxy = true; rawStr = raw;
    return
end
val = str2double(tok{1});
unit = upper(tok{2});
isProxy = strcmp(unit, 'V');
rawStr = raw;
end
