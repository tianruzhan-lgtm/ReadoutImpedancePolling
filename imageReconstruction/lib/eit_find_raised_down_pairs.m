function pairs = eit_find_raised_down_pairs(dataDir)
% EIT_FIND_RAISED_DOWN_PAIRS Discover raised/down file pairs in a
% directory by filename, generalizing beyond the fixed Peltier_1..7
% naming used for the original dataset.
%
% Matching rule: any *.txt file whose name contains 'raised' is paired
% with the file of the same name but 'raised' replaced by 'down'. This
% matches the existing naming convention (e.g.
% 20260731_AutoElectrodeReadoutRaw_Peltier_3_raised.txt /
% ..._down.txt) and should generalize to future experiments AS LONG AS
% they keep the same raised/down naming convention. Files that don't
% have a matching counterpart are skipped with a warning, not silently
% dropped.
%
% Returns a struct array with fields:
%   .label       trial label for titles/filenames (raised filename with
%                the raised/down token and extension stripped)
%   .raisedFile, .downFile   full paths

d = dir(fullfile(dataDir, '*raised*.txt'));
pairs = struct('label', {}, 'raisedFile', {}, 'downFile', {});

for i = 1:numel(d)
    raisedName = d(i).name;
    downName = strrep(raisedName, 'raised', 'down');
    downPath = fullfile(dataDir, downName);
    raisedPath = fullfile(dataDir, raisedName);

    if ~exist(downPath, 'file')
        warning('eit_find_raised_down_pairs:noMatch', ...
            'No matching "down" file for %s (looked for %s) -- skipped', raisedName, downName);
        continue
    end

    label = raisedName;
    label = regexprep(label, '\.txt$', '');
    label = regexprep(label, '[_-]?raised', '');
    if isempty(label); label = sprintf('pair%d', i); end

    pairs(end+1) = struct('label', label, 'raisedFile', raisedPath, 'downFile', downPath); %#ok<AGROW>
end

if isempty(pairs)
    warning('eit_find_raised_down_pairs:none', ...
        'No raised/down file pairs found in %s (expected filenames containing "raised" and "down")', dataDir);
end

end
