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

#hboardBaudRate = 38400
# Start humidity serial with matching baud rate in HumidityControl_V2.3_Brian
#humidityser = serial.Serial('COM8', hboardBaudRate, timeout = 0.9)

##### Current Reading Settings #####
deviceID = 'dev3275'
amplitudeExct = 0.1      # Amplitude of the excitation sine in V
frequencyExct = 1000      # Driving Signal Frequency
currentRange = 1e-4 # used to be 1e-3
demodRate = 100e3           ###DO NOT CHANGE
samplingRate = 0.001        ###DO NOT CHANGE
# TODO: currently, the amplitude, frequency are not doing anything because we are no longer using the MFIA obj. Implement.

POLL_TIME_S = 0.1   # how long each poll() call blocks collecting samples
TIMEOUT_MS = 500

# Define destination of the file
#subDirectoryData = r"C:\Users\DaraioLab - Pectin\Desktop\BrianAhn\readout_Electrode\P3A\20260529_Exp0025\ImpedData"  #Folder where the data are saved
subDirectoryData = r"C:\Users\Daraio Lab\Documents\Data\Brian\EIT"
#fileIDData = r"20251209_P3APixel_65CBake_P3A1CaCl1_2000Hz_100mV_PostCycling" #### change here file name
#fileIDData = r"20260626_300mMolCaCl2_1HzBW_1kHz_ID2_1Day50CCure_LPIBCoating_PostCure_TCyc_Cont10"
fileIDData = r"20260728_Test"
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
device = session.connect_device(deviceID, interface="1GbE") # Connect to device
#Debug code: Confirms that we have connected to device
timestamp = device.status.time()
instrClockPeriod = 60000000 # 60 MHz. Period of the internal clock in the MFIA Imp. Analyzer.
print(timestamp/instrClockPeriod)


# Creates the file - or either overwrites, or prompts user for new file.
headerList_IARaw = ["timestamp", "z", "frequency"]
headerList = ["time", "zreal", "zimag", "zmag", "zphase", "frequency"]
outputFile = helpers.initializeData(subDirectoryData, fileIDData, headerList)

# Lock in Amplifier Initializing?
#lockIn = MFIA(deviceID)
#lockIn.set2TerminalMode(amplitudeExct, frequencyExct, currentRange, demodRate, samplingRate)
#lockIn.begin()

beginTime_DeviceInternal = (device.status.time()/instrClockPeriod) # Time that we began polling, in seconds, according to internal clock

# List where we will store all our data
IARawSamples = {key: [] for key in headerList}
recordedIdx = 0  # tracks how many rows have already been written to file
#humidityser.write(b"s\n") # This lets the arduino know that we are starting.

# Subscribe once, then keep polling continuously without unsubscribing in between
daq.flush()
daq.subscribe(impedanceNode)
daq.sync()

def recordAllRawData(outputFile, IAAvgData, headerList, startIdx=0):
    """
    Appends every new row (from startIdx to the end of each list) to outputFile.
    Returns the new startIdx to pass in next call, so already-written rows
    aren't duplicated.
    """
    precision = {
        "time": 10,
        "temperature": 4,
        "humidity": 4
    }

    numRows = len(IAAvgData[headerList[0]])
    lines = []
    for i in range(startIdx, numRows):
        rowBuffer = []
        for key in headerList:
            values = IAAvgData[key]
            if i >= len(values):
                val = ""  # Handles keys with fewer entries (e.g. temperature/humidity)
            else:
                val = values[i]

            if isinstance(val, (int, float)):
                sigfigs = precision.get(key, 6)
                val_str = f"{val:.{sigfigs}g}"
            else:
                val_str = str(val)

            rowBuffer.append(val_str)
        lines.append("\t".join(rowBuffer))

    if lines:
        with open(outputFile, "a") as f:
            f.write("\n".join(lines) + "\n")

    return numRows

try:
    while True:
        IARawData = daq.poll(POLL_TIME_S, TIMEOUT_MS, 0, True)[impedanceNode]
        #print(IARawData) # Debug

        # Record every raw sample from this poll window, no averaging
        timestamps = IARawData['timestamp']
        zValues = IARawData['z']
        freqValues = IARawData['frequency']
        for i in range(len(timestamps)):
            IARawSamples['time'].append((float(timestamps[i]) / instrClockPeriod) - beginTime_DeviceInternal)
            IARawSamples['zreal'].append(np.real(zValues[i]))
            IARawSamples['zimag'].append(np.imag(zValues[i]))
            IARawSamples['zmag'].append(np.abs(zValues[i]))
            IARawSamples['zphase'].append(np.angle(zValues[i]))
            IARawSamples['frequency'].append(freqValues[i])

        recordedIdx = recordAllRawData(outputFile, IARawSamples, headerList, recordedIdx)
finally:
    daq.unsubscribe("*")