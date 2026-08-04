dataDir = 'C:\Users\tianr\Documents\SURF 2026 things\from_daraio_lan\EIT_raw_data\0804_tempdata\';
test = readtable([dataDir, '20260804_AutoTempData_1_raised.txt']);

fs = 13390;
fpass = 500;

% separates data into different sweeps
newSweepIdx = find((diff(test.chB) < 0) & (diff(test.chA) < 0)) + 1; % finds the index after channels reset to 0,1
allStartRows = [1; newSweepIdx];
allEndRows = [(newSweepIdx - 1); height(test)];
sweeps = cell(length(allStartRows),1);

for i = 1:length(allStartRows)
    sweeps{i} = test(allStartRows(i):allEndRows(i), :);
end

figure();
plot(sweeps{1,1}.time, sweeps{1,1}.zreal, '.-');

% finds number of samples taken in each channel
for i = 1:5
    uniquePairs = unique([sweeps{i,1}.chA, sweeps{i,1}.chB], 'rows');
    numPairs = size(uniquePairs, 1);
    
    sweeps{i,2} = zeros(120,1);
    
    for k = 1:numPairs
        chA = uniquePairs(k, 1);
        chB = uniquePairs(k, 2);
    
        mask = (sweeps{i,1}.chA == chA) & (sweeps{i,1}.chB == chB);
        sweeps{i,2}(k) = sum(mask);
    end
    % figure();
    % plot(sweeps{i,3}, '.-');
end


% averaging + low pass filter
for n = 1:5
    k = 0;
    chA = zeros(120,1);
    chB = zeros(120,1);
    Zmean = zeros(120,1);
    Zlpass = zeros(120,1);
    raw_lpass = cell(120,1);

    for i = 0:14
        for j = i+1:15
            k = k + 1;
            mask = ((sweeps{n,1}.chA == i) & (sweeps{n,1}.chB == j));
            channel_data = sweeps{n,1}.zreal(mask);
            lpass = lowpass(channel_data, fpass, fs);

            Zmean(k) = mean(channel_data);
            Zlpass(k) = mean(lpass);
            raw_lpass{k} = lpass;
            chA(k) = i;
            chB(k) = j;
        end
    end
    sweeps{n,3} = table(chA, chB, Zmean);
    sweeps{n,4} = table(chA, chB, Zlpass);
    sweeps{n,5} = table(chA, chB, raw_lpass);
end

