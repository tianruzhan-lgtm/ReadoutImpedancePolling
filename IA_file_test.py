import sys
#sys.path.append(r"C:\Users\DaraioLab - Pectin\Desktop\Python Scripts\TemperatureBoard")
#sys.path.append(r"C:\Users\DaraioLab - Pectin\Desktop\Python Scripts\MFIA")
import numpy as np
import zhinst
import zhinst.toolkit
import json
import cmath
import matplotlib.pyplot as plt
import time
import signal
from TemperatureBoard import TemperatureBoard
from MFIA import MFIA
import helpers
import plotters
import serial

hboardBaudRate = 38400
# Start humidity serial with matching baud rate in HumidityControl_V2.3_Brian
humidityser = serial.Serial('COM8', hboardBaudRate, timeout = 0.9)


##### Current Reading Settings #####
deviceID = 'dev3275'
amplitudeExct = 0.1      # Amplitude of the excitation sine in V
frequencyExct = 1000      # Driving Signal Frequency
currentRange = 1e-4 # used to be 1e-3
demodRate = 100e3           ###DO NOT CHANGE
samplingRate = 0.001        ###DO NOT CHANGE
# TODO: currently, the amplitude, frequency are not doing anything because we are no longer using the MFIA obj. Implement.

RECORDING_TIME_S = 0.1
TIMEOUT_MS = 500

# Define destination of the file
#subDirectoryData = r"C:\Users\DaraioLab - Pectin\Desktop\BrianAhn\readout_Electrode\P3A\20260529_Exp0025\ImpedData"  #Folder where the data are saved
subDirectoryData = r"C:\Users\DaraioLab - Pectin\Desktop\BrianAhn\readout_Electrode\WVTR\20260706"
#fileIDData = r"20251209_P3APixel_65CBake_P3A1CaCl1_2000Hz_100mV_PostCycling" #### change here file name
#fileIDData = r"20260626_300mMolCaCl2_1HzBW_1kHz_ID2_1Day50CCure_LPIBCoating_PostCure_TCyc_Cont10"
fileIDData = r"20260707_ChromologicTest"
#fileIDData = r"20260224_NewFanTest"
# Connect to the LabOne Data Server
session = zhinst.toolkit.Session("localhost", 8004)
# print(list(session.child_nodes(recursive=True, leavesonly=True)))
# print(session.about.copyright())
print(session.debug.level())
print(session.devices.visible())
print(session.devices.connected())

# Debug Server Connection
devs_json = session.daq_server.getString("/zi/devices")
print("Raw /zi/devices:", devs_json)
info = json.loads(devs_json)[deviceID.upper()]  # uppercase key
print("INTERFACE:", info["INTERFACE"])
print("INTERFACES:", info["INTERFACES"])
print("STATUS:", info.get("STATUS", "<no STATUS field>"))


daq = session.daq_server #Initialize DAQ
impedanceNode = f"/{deviceID}/imps/0/sample" # Node to subscribe to
# daq.subscribe(impedanceNode) # Subscribe to data node. Actually, should be done later. for reasons.
device = session.connect_device(deviceID, interface="1GbE") # Connect to device
#Debug code: Confirms that we have connected to device
timestamp = device.status.time()
instrClockPeriod = 60000000 # 60 MHz. Period of the internal clock in the MFIA Imp. Analyzer.
print(timestamp/instrClockPeriod)


# Creates the file - or either overwrites, or prompts user for new file.
headerList_IARaw = ["timestamp", "z", "frequency"]
headerList = ["time", "zreal", "zimag", "zmag", "zphase", "frequency", "temperature", "humidity"]
outputFile = helpers.initializeData(subDirectoryData, fileIDData, headerList)

# Lock in Amplifier Initializing?
#lockIn = MFIA(deviceID)
#lockIn.set2TerminalMode(amplitudeExct, frequencyExct, currentRange, demodRate, samplingRate)
#lockIn.begin()

# Begin polling impedance data
pollingFreq = 1 # How often we poll, in seconds
last_Polled = time.time()
time.sleep(1.005)
beginTime_DeviceInternal = (device.status.time()/instrClockPeriod) # Time that we began polling, in seconds, according to internal clock

# List where we will store all our data for plotting
IAAvgData = {key: [] for key in headerList}
humidityser.write(b"s\n") # This lets the arduino know that we are starting.

while True:
    currentTime = time.time()

    # Run the polling
    if currentTime - last_Polled >= pollingFreq:
        # last_Polled = currentTime
        last_Polled += pollingFreq
        # We need poll from both the temperature board and the Impedance Analyzer
        # IA Polling
        daq.flush()
        daq.subscribe(impedanceNode) # Subscribe to data node
        daq.sync()
        IARawData = daq.poll(RECORDING_TIME_S, TIMEOUT_MS, 0, True)[impedanceNode]
        daq.unsubscribe("*")  # Unsubscribe, so data doesnt build up in between.
        #print(IARawData) # Debug
        # Average out the polled data to make it a single datapoint
        for key in headerList_IARaw:
            values = IARawData[key]
            if key == 'timestamp':
                IAAvgData['time'].append((float(np.mean(values))/instrClockPeriod) - beginTime_DeviceInternal)
            if key == 'z': # find the average zmag and zphase first
                IAAvgData['zmag'].append(np.mean(np.abs(values)))
                IAAvgData['zphase'].append(np.mean(np.angle(values)))
                IAAvgData['zreal'].append(np.mean(np.real(values)))
                IAAvgData['zimag'].append(np.mean(np.imag(values)))
            if key == 'frequency':
                IAAvgData['frequency'].append(np.mean(values))

        helpers.recordData(outputFile, IAAvgData, headerList)


    # Runs more or less continuously
    #plt.pause(0.01)
    time.sleep(0.005) # Don't want to set CPU at 100%