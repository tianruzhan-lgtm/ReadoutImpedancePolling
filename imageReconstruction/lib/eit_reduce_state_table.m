function S = eit_reduce_state_table(T, nElec, sourceLabel)
% EIT_REDUCE_STATE_TABLE Reduce one raw readout table (one Peltier state:
% control/raised or heat/down) to a single impedance value per electrode
% pair.
%
% This is the shared averaging core. It works on an already-loaded table,
% so it serves BOTH input paths:
%   - eit_load_state_file.m    (legacy: raw .txt file on disk)
%   - eit_load_experiment.m    (current: packaged .mat, trial(k).data)
%
% T must have columns: time, zreal, zimag, zmag, zphase, chA, chB
% (chA/chB 0-based electrode indices). sourceLabel is only used in
% error/warning messages.
%
% Averaging order (unchanged from the original spec):
%   1. Split into the vertically-appended sweeps.
%   2. Within each sweep, average the raw repeated readings per electrode
%      pair -- averaged as complex impedance (zreal + 1i*zimag) rather
%      than averaging zmag/zphase separately, since magnitude/phase
%      averaging is not well behaved across noisy repeats near phase wraps.
%   3. Average the resulting per-sweep complex values per pair.
%
% Sweep boundaries are detected generically via the canonical pair index
% (see eit_pair_list.m): the firmware sweeps chA,chB through all pairs in
% a fixed increasing order, so a sweep boundary is any row where the pair
% index goes backwards relative to the previous row.
%
% Returns a struct S with:
%   S.pairs         [nPairs x 2] canonical (chA,chB) order
%   S.nSweeps       number of sweeps detected (expected 5)
%   S.zreal, S.zimag, S.zmag, S.zphase   [nPairs x 1] final averaged values
%   S.nSamplesPerSweep [nPairs x nSweeps] raw sample counts, for QC
%   S.sweepZ        [nPairs x nSweeps] complex per-sweep means, for QC

if nargin < 2 || isempty(nElec); nElec = 16; end
if nargin < 3 || isempty(sourceLabel); sourceLabel = '<table>'; end

requiredVars = {'time','zreal','zimag','zmag','zphase','chA','chB'};
missing = setdiff(requiredVars, T.Properties.VariableNames);
if ~isempty(missing)
    error('eit_reduce_state_table:badTable', ...
        '%s is missing expected columns: %s', sourceLabel, strjoin(missing,', '));
end

pairs = eit_pair_list(nElec);
nPairs = size(pairs,1);
pairIndex = containers.Map();
for k = 1:nPairs
    pairIndex(sprintf('%d_%d', pairs(k,1), pairs(k,2))) = k;
end

nRows = height(T);
rowPairIdx = zeros(nRows,1);
for r = 1:nRows
    key = sprintf('%d_%d', T.chA(r), T.chB(r));
    if ~isKey(pairIndex, key)
        error('eit_reduce_state_table:badPair', ...
            '%s row %d has electrode pair (%d,%d) not in the expected %d-electrode pair list', ...
            sourceLabel, r, T.chA(r), T.chB(r), nElec);
    end
    rowPairIdx(r) = pairIndex(key);
end

sweepBreaks = find(diff(rowPairIdx) < 0) + 1; % index goes backwards -> new sweep
sweepStart = [1; sweepBreaks];
sweepEnd   = [sweepBreaks - 1; nRows];
nSweeps = numel(sweepStart);

sweepZ = nan(nPairs, nSweeps);
nSamplesPerSweep = zeros(nPairs, nSweeps);

for s = 1:nSweeps
    idxRange = sweepStart(s):sweepEnd(s);
    z = complex(T.zreal(idxRange), T.zimag(idxRange));
    pIdx = rowPairIdx(idxRange);
    for k = 1:nPairs
        mask = (pIdx == k);
        nSamplesPerSweep(k,s) = sum(mask);
        if any(mask)
            sweepZ(k,s) = mean(z(mask));
        end
    end
end

zFinal = mean(sweepZ, 2, 'omitnan');

S.pairs = pairs;
S.nSweeps = nSweeps;
S.zreal = real(zFinal);
S.zimag = imag(zFinal);
S.zmag  = abs(zFinal);
S.zphase = angle(zFinal);
S.nSamplesPerSweep = nSamplesPerSweep;
S.sweepZ = sweepZ;
S.sourceFile = sourceLabel;

if nSweeps ~= 5
    warning('eit_reduce_state_table:sweepCount', ...
        '%s: expected 5 sweeps, found %d', sourceLabel, nSweeps);
end
minSamples = min(nSamplesPerSweep(:));
if minSamples < 5
    warning('eit_reduce_state_table:lowSamples', ...
        '%s: minimum raw samples for a pair in a sweep is %d', sourceLabel, minSamples);
end

end
