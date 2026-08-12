function Exp = importExperiment(folderPath)
% IMPORTEXPERIMENT  Import all trial data files from an experiment folder
%                    into a single struct.
%
%   Exp = importExperiment(folderPath)
%
%   INPUT:
%       folderPath - path to a folder containing all .txt trial files
%                    for one experiment (one file per trial, each
%                    starting with a "% Key: Value" header block as
%                    produced by the AutoTempData script)
%
%   OUTPUT:
%       Exp.sampleinfo          -  struct with fields SampleNumber, Date,
%                                  Description (taken from Trial 1, checked
%                                  for consistency across all trials)
%       Exp.trial(i).type        - 'control' or 'heat'
%       Exp.trial(i).temperature - peltier plate temperature. Numeric
%                                  (double) if the header value parses as
%                                  a number, otherwise kept as the raw
%                                  string (e.g. 'off', 'ambient'). Blank
%                                  header fields come through as NaN.
%       Exp.trial(i).positionX/positionY/positionZ - position (double)
%       Exp.trial(i).data         - table of the raw recorded data
%       Exp.trial(i).filename     - source filename, for traceability
%
%   USAGE:
%       Exp4 = importExperiment('C:\data\Experiment_4');
%       Exp4.trial(5).data
%       Exp4.trial(5).positionX
%       Exp4.sampleinfo
%       xVals = [Exp4.trial.positionX];   % all X positions at once

    files = dir(fullfile(folderPath, '*.txt'));
    files = files(~[files.isdir]);
    if isempty(files)
        error('No .txt files found in %s', folderPath);
    end

    [~, sortIdx] = sort({files.name});
    files = files(sortIdx);

    nTrials = numel(files);
    trial = struct('type', {}, 'temperature', {}, 'positionX', {}, ...
                    'positionY', {}, 'positionZ', {}, 'data', {}, ...
                    'filename', {});
    sampleInfoList = struct('SampleNumber', {}, 'Date', {}, 'Description', {});

    for i = 1:nTrials
        fpath = fullfile(files(i).folder, files(i).name);
        [headerMap, nHeaderLines] = parseHeader(fpath);

        sampleInfoList(i).SampleNumber = getField(headerMap, 'Sample Number');
        sampleInfoList(i).Date         = getField(headerMap, 'Date');
        sampleInfoList(i).Description  = getField(headerMap, 'Description');

        trial(i).type        = getField(headerMap, 'Type');
        trial(i).temperature = parseTemperature(getField(headerMap, 'Temperature'));
        trial(i).positionX   = str2double(getField(headerMap, 'Position_X'));
        trial(i).positionY   = str2double(getField(headerMap, 'Position_Y'));
        trial(i).positionZ   = str2double(getField(headerMap, 'Position_Z'));
        trial(i).filename    = files(i).name;

        trial(i).data = readtable(fpath, 'FileType', 'text', ...
            'Delimiter', '\t', 'NumHeaderLines', nHeaderLines);

        % flag filename/header Type mismatch, don't error
        lowerName = lower(files(i).name);
        if contains(lowerName, 'control') && ~strcmpi(trial(i).type, 'control')
            warning('Trial %d (%s): header Type "%s" does not match filename ("control")', ...
                i, files(i).name, trial(i).type);
        elseif contains(lowerName, 'heat') && ~strcmpi(trial(i).type, 'heat')
            warning('Trial %d (%s): header Type "%s" does not match filename ("heat")', ...
                i, files(i).name, trial(i).type);
        end
    end

    % Sample info: take Trial 1 as canonical, flag any mismatch
    Exp.sampleinfo.SampleNumber = sampleInfoList(1).SampleNumber;
    Exp.sampleinfo.Date         = sampleInfoList(1).Date;
    Exp.sampleinfo.Description  = sampleInfoList(1).Description;

    for i = 2:nTrials
        if ~isequal(sampleInfoList(i).SampleNumber, sampleInfoList(1).SampleNumber) || ...
           ~isequal(sampleInfoList(i).Date, sampleInfoList(1).Date) || ...
           ~isequal(sampleInfoList(i).Description, sampleInfoList(1).Description)
            warning('Trial %d (%s): Sample Info differs from Trial 1 — check headers.', ...
                i, files(i).name);
        end
    end

    Exp.trial = trial;
end


function [headerMap, nHeaderLines] = parseHeader(fpath)
% Reads leading "%"-comment lines and parses "Key: Value" pairs into a
% containers.Map. Stops at the first non-comment line (the real data
% header row, e.g. "time  zreal  zimag ..."). nHeaderLines is the count
% of comment lines skipped, for use with readtable's NumHeaderLines.

    fid = fopen(fpath, 'r');
    if fid == -1
        error('Could not open file: %s', fpath);
    end

    headerMap = containers.Map();
    nHeaderLines = 0;

    while true
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end
        if startsWith(strtrim(line), '%')
            nHeaderLines = nHeaderLines + 1;
            tok = regexp(line, '^\s*%\s*([^:]+):\s*(.*)$', 'tokens', 'once');
            if ~isempty(tok)
                key = strtrim(tok{1});
                val = strtrim(tok{2});
                headerMap(key) = val;
            end
        else
            break;
        end
    end

    fclose(fid);
end


function val = getField(map, key)
    if isKey(map, key)
        val = map(key);
    else
        val = '';
    end
end


function temp = parseTemperature(rawVal)
% Returns a numeric double if rawVal parses as a number, otherwise
% returns the trimmed raw string as-is (e.g. 'off', 'ambient'). An
% empty/blank header field returns NaN.

    rawVal = strtrim(rawVal);
    if isempty(rawVal)
        temp = NaN;
        return;
    end

    numVal = str2double(rawVal);
    if isnan(numVal)
        temp = rawVal;   % non-numeric text, keep as string
    else
        temp = numVal;   % parses cleanly as a number
    end
end