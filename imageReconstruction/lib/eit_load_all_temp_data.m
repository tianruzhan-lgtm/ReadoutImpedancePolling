function trials = eit_load_all_temp_data(cfg)
% EIT_LOAD_ALL_TEMP_DATA Load and average every raised/down file pair
% across all Peltier IDs, cross-referenced with the IR temperatures
% transcribed from Experimental Setup.pdf (see eit_config.m).
%
% Returns a 1xN struct array `trials`, one entry per Peltier ID, with
% fields:
%   .id                 Peltier trial ID
%   .IRTemp_C            Peltier-plate IR temperature (PLACEHOLDER, see note)
%   .voltage_V, .current_A
%   .baseline            output of eit_load_state_file for the 'raised' file
%   .heated              output of eit_load_state_file for the 'down' file
%   .note                flags on the IR temperature assumption

trials = struct([]);

for k = 1:numel(cfg.peltierIDs)
    id = cfg.peltierIDs(k);

    raisedFile = fullfile(cfg.dataDir, sprintf(cfg.dataFilePattern, id, 'raised'));
    downFile   = fullfile(cfg.dataDir, sprintf(cfg.dataFilePattern, id, 'down'));

    if ~exist(raisedFile,'file')
        error('eit_load_all_temp_data:missingFile','Missing file: %s', raisedFile);
    end
    if ~exist(downFile,'file')
        error('eit_load_all_temp_data:missingFile','Missing file: %s', downFile);
    end

    fprintf('Loading Peltier ID %d (raised + down)...\n', id);

    baseline = eit_load_state_file(raisedFile, cfg.nElec);
    heated   = eit_load_state_file(downFile, cfg.nElec);

    entry.id = id;
    entry.IRTemp_C = cfg.peltierIRTemp_C(id);
    entry.voltage_V = cfg.peltierVoltage_V(id);
    entry.current_A = cfg.peltierCurrent_A(id);
    entry.baseline = baseline;
    entry.heated = heated;
    entry.IRTempNote = cfg.peltierTempNote;

    if isempty(trials)
        trials = entry;
    else
        trials(end+1) = entry; %#ok<AGROW>
    end
end

end
