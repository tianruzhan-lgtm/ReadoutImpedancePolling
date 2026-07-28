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

# ---- Electrode readout serial setup ----
readoutPort = 'COM3'           # set to actual teensy port
readoutBaudRate = 115200       # match Teensy baud rate
readoutSerial = serial.Serial(readoutPort, readoutBaudRate, timeout=0.1)

# ---- File destination ----
subDirectoryData = r"C:\Users\DaraioLab - Pectin\Desktop\BrianAhn\readout_Electrode\WVTR\20260706"
fileIDData = r"20260707_ChromologicTest"

# ---- Output file setup ----
headerList_IARaw = ["timestamp", "z", "frequency"]
headerList = ["time", "zreal", "zimag", "zmag", "zphase", "frequency", "chA", "chB"]
outputFile = helpers.initializeData(subDirectoryData, fileIDData, headerList)

# ---- MFIA measurement constants ----
deviceID = 'dev3275'
amplitudeExct = 0.1      # Amplitude of the excitation sine in V
frequencyExct = 1000      # Driving Signal Frequency
currentRange = 1e-4 # used to be 1e-3
demodRate = 100e3           ###DO NOT CHANGE
samplingRate = 0.001        ###DO NOT CHANGE

# ---- MFIA polling constants ----
RECORDING_TIME_S = 0.1
TIMEOUT_MS = 500

# ---- Connect to LabOne Data Server ----
session = zhinst.toolkit.Session("localhost", 8004)
print(session.debug.level())
print(session.devices.visible())
print(session.devices.connected())

# ---- Debug Server Connection ----
devs_json = session.daq_server.getString("/zi/devices")
print("Raw /zi/devices:", devs_json)
info = json.loads(devs_json)[deviceID.upper()]  # uppercase key
print("INTERFACE:", info["INTERFACE"])
print("INTERFACES:", info["INTERFACES"])
print("STATUS:", info.get("STATUS", "<no STATUS field>"))

# ---- Initialize DAQ ----
daq = session.daq_server
impedanceNode = f"/{deviceID}/imps/0/sample" # Node to subscribe to
device = session.connect_device(deviceID, interface="1GbE") # Connect to device
#Debug code: Confirms that we have connected to device
timestamp = device.status.time()
instrClockPeriod = 60000000 # 60 MHz. Period of the internal clock in the MFIA Imp. Analyzer.
print(timestamp/instrClockPeriod)

# ---- Begin polling impedance data ----
last_Polled = time.time()
time.sleep(1.005) # what is this for
beginTime_DeviceInternal = (device.status.time()/instrClockPeriod) # Time that we began polling, in seconds, according to internal clock

# List where we will store all our data for plotting
IAAvgData = {key: [] for key in headerList}

runElectrodeSweep()


def pollAndAverageImpedance(recordingTimeS, timeoutMs):

    # Subscribes to the MFIA impedance node, polls for recordingTimeS seconds,
    # unsubscribes, and averages recorded data into a single sample.

    # Returns a dict: {'time', 'zreal', 'zimag', 'zmag', 'zphase', 'frequency'}

    daq.flush()
    daq.subscribe(impedanceNode)  # Subscribe to data node
    daq.sync()
    IARawData = daq.poll(recordingTimeS, timeoutMs, 0, True)[impedanceNode]
    daq.unsubscribe("*")  # Unsubscribe, so data doesn't build up in between.

    sample = {}
    for key in headerList_IARaw:
        values = IARawData[key]
        if key == 'timestamp':
            sample['time'] = (float(np.mean(values)) / instrClockPeriod) - beginTime_DeviceInternal
        if key == 'z':  # find the average zmag and zphase first
            sample['zmag'] = np.mean(np.abs(values))
            sample['zphase'] = np.mean(np.angle(values))
            sample['zreal'] = np.mean(np.real(values))
            sample['zimag'] = np.mean(np.imag(values))
        if key == 'frequency':
            sample['frequency'] = np.mean(values)

    return sample


def runElectrodeSweep():

    while True:
        line = readoutSerial.readline()
        if not line:
            continue

        line = line.decode(errors='ignore').strip()
        if not line.startswith("PAIR"):
            continue

        parts = line.split(",")
        if len(parts) != 3:
            continue
        chA, chB = int(parts[1]), int(parts[2])

        sample = pollAndAverageImpedance(RECORDING_TIME_S, TIMEOUT_MS)
        sample['chA'] = chA
        sample['chB'] = chB

        helpers.recordData(outputFile, sample, headerList)
        readoutSerial.write(b"DONE\n")