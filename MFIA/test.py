from MFIA import MFIA
import numpy as np
import time


deviceID = 'dev4216'
amplitude = 0.3
frequency = 10e3
currentRange = 1e-6
demodRate = 100e3
samplingRate = 0.001

lockIn = MFIA(deviceID)

lockIn.set2TerminalMode(amplitude, frequency, currentRange, demodRate, samplingRate)
lockIn.begin()

time.sleep(2)

lockIn.setFrequency(200)
lockIn.setAmplitude(0.1)
#lockIn.autoRange()
#print('autorange')
#lockIn.adjustRange(100e-6)
data = []
#executiontime = np.array(0)
#data = lockIn.getData()
#start = time.time()
#for i in range(0,5000):
#     data = lockIn.getData()
#     executiontime = np.append(executiontime, [data["time"]])
#end = time.time()
#print(np.mean(executiontime))
#print(end - start)
lockIn.end()
