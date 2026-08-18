function pairs = eit_pair_list(n)
% EIT_PAIR_LIST Canonical ordering of all unique 2-electrode combinations.
%
% pairs = eit_pair_list(n) returns an [n*(n-1)/2 x 2] matrix of 0-based
% electrode index pairs [i,j], i<j, in the order i=0:n-2, j=i+1:n-1.
%
% This is the fixed order the readout firmware sweeps through (confirmed
% against the raw data: chA,chB always progress (0,1),(0,2),...,(0,15),
% (1,2),...,(14,15) within a sweep) and is also the order used to build
% the model's custom stim/meas patterns, so that pattern k in the model
% always corresponds to pair k in the loaded data.

pairs = zeros(n*(n-1)/2, 2);
k = 0;
for i = 0:n-2
    for j = i+1:n-1
        k = k+1;
        pairs(k,:) = [i, j];
    end
end
end
