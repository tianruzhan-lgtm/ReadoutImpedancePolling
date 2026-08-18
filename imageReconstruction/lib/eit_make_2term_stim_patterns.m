function stim = eit_make_2term_stim_patterns(nElec, amplitude)
% EIT_MAKE_2TERM_STIM_PATTERNS Build custom stimulation/measurement
% patterns for the readout hardware's 2-terminal protocol.
%
% mk_stim_patterns is built for 4-terminal EIT (inject on one electrode
% pair, measure voltage on other, non-injecting, pairs). Our hardware
% injects current AND measures voltage on the SAME electrode pair, for
% all n*(n-1)/2 unique pairs -- so we build the stimulation struct array
% directly.
%
% stim(k) corresponds to pair k in eit_pair_list(nElec), i.e. pattern k
% here lines up 1:1 with pair k in the loaded data (eit_load_state_file).
%
% Each pattern injects +amplitude/-amplitude at the pair's two
% electrodes and takes exactly one measurement: V_i - V_j on that same
% pair (2-terminal impedance).

if nargin < 2; amplitude = 1e-3; end % 1 mA, arbitrary for a linear FEM solve

pairs = eit_pair_list(nElec);
nPairs = size(pairs,1);

stim = struct('stimulation', cell(nPairs,1), ...
              'stim_pattern', cell(nPairs,1), ...
              'meas_pattern', cell(nPairs,1));

for k = 1:nPairs
    i = pairs(k,1) + 1; % 1-based
    j = pairs(k,2) + 1;

    sp = sparse(nElec,1);
    sp(i) =  amplitude;
    sp(j) = -amplitude;

    mp = sparse(1,nElec);
    mp(i) =  1;
    mp(j) = -1;

    stim(k).stimulation = 'mA';
    stim(k).stim_pattern = sp;
    stim(k).meas_pattern = mp;
end

end
