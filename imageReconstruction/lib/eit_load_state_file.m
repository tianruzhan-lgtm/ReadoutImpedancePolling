function S = eit_load_state_file(filepath, nElec)
% EIT_LOAD_STATE_FILE Load one raw readout .txt file (one Peltier state:
% raised/control or down/heat) and reduce it to one impedance value per
% electrode pair.
%
% This is the LEGACY input path, for loose .txt files on disk (the
% original 7/31 dataset). Newer experiments arrive pre-packaged in a
% .mat file -- see eit_load_experiment.m -- but both paths share the
% same averaging core, eit_reduce_state_table.m, so results are
% identical regardless of how the data got here.
%
% See eit_reduce_state_table.m for the averaging order and the returned
% struct's fields.

if nargin < 2; nElec = 16; end

T = readtable(filepath, 'FileType','text', 'Delimiter','\t');
S = eit_reduce_state_table(T, nElec, filepath);

end
