import sys
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

# ---- Electrode readout settings ----
readoutPort = 'COM5'
readoutBaudRate = 115200
readoutSerial = serial.Serial(readoutPort, readoutBaudRate, timeout=0.1)

PAIR_INCOMING_MESSAGE = "P,"
IMPEDANCE_DONE_MESSAGE = b"D\n"

# ---- MFIA polling constants ----
RECORDING_TIME_S = 0.01
TIMEOUT_MS = 500

# ---- File destination ----
subDirectoryData = r"C:\Users\Daraio Lab\Documents\Data\Brian\EIT"
fileIDData = r"20260729_AutoElectrodeReadout_Test1.5"

# ---- Output file setup ----
headerList_IARaw = ["timestamp", "z"]
headerList = ["time", "zreal", "zimag", "zmag", "zphase", "chA", "chB"]
outputFilePath = helpers.initializeData(subDirectoryData, fileIDData, headerList)
outputFileHandle = open(outputFilePath, "a")

# ---- MFIA measurement constants ----
deviceID = 'dev3275'
amplitudeExct = 0.1
frequencyExct = 1000
currentRange = 1e-4
demodRate = 100e3
samplingRate = 0.001

# ---- Connect to LabOne Data Server ----
session = zhinst.toolkit.Session("localhost", 8004)
print(session.debug.level())
print(session.devices.visible())
print(session.devices.connected())

# ---- Debug Server Connection ----
devs_json = session.daq_server.getString("/zi/devices")
print("Raw /zi/devices:", devs_json)
info = json.loads(devs_json)[deviceID.upper()]
print("INTERFACE:", info["INTERFACE"])
print("INTERFACES:", info["INTERFACES"])
print("STATUS:", info.get("STATUS", "<no STATUS field>"))

# ---- Initialize DAQ ----
daq = session.daq_server
impedanceNode = f"/{deviceID}/imps/0/sample"
device = session.connect_device(deviceID, interface="1GbE")
timestamp = device.status.time()
instrClockPeriod = 60000000
print(timestamp / instrClockPeriod)

# ---- Begin polling impedance data ----
time.sleep(1.005)
beginTime_DeviceInternal = (device.status.time() / instrClockPeriod)


def pollAndAverageImpedance(recordingTimeS, timeoutMs):
    daq.flush()
    IARawData = daq.poll(recordingTimeS, timeoutMs, 0, True)[impedanceNode]

    sample = {}
    for key in headerList_IARaw:
        values = IARawData[key]
        if key == 'timestamp':
            sample['time'] = (float(np.mean(values)) / instrClockPeriod) - beginTime_DeviceInternal
        if key == 'z':
            sample['zmag'] = np.mean(np.abs(values))
            sample['zphase'] = np.mean(np.angle(values))
            sample['zreal'] = np.mean(np.real(values))
            sample['zimag'] = np.mean(np.imag(values))
        # if key == 'frequency':
            # sample['frequency'] = np.mean(values)

    return sample

def writeRow(fileHandle, sample, chA, chB):
    # Writes impedance sample as a tab-separated row to the already-open file handle
    fileHandle.write(
        f"{sample['time']:.10g}\t{sample['zreal']:.6g}\t{sample['zimag']:.6g}\t"
        f"{sample['zmag']:.6g}\t{sample['zphase']:.6g}\t{chA}\t{chB}\n"
    )

def runElectrodeSweep():
    while True:
        line = readoutSerial.readline()
        if not line:
            continue

        line = line.decode(errors='ignore').strip()
        if not line.startswith(PAIR_INCOMING_MESSAGE):
            continue

        messageParts = line.split(",")
        if len(messageParts) != 3:
            continue
        chA, chB = int(messageParts[1]), int(messageParts[2])

        sample = pollAndAverageImpedance(RECORDING_TIME_S, TIMEOUT_MS)
        sample['chA'] = chA
        sample['chB'] = chB

        print(f"chA={chA}, chB={chB},  zreal={sample['zreal']:.2e}")

        writeRow(outputFileHandle, sample, chA, chB)

        readoutSerial.write(IMPEDANCE_DONE_MESSAGE)


# ---- sweep ----
input("Press Enter to start the electrode sweep...")
readoutSerial.write(b"START\n")

daq.subscribe(impedanceNode)    # subscribe once, turn off at end
daq.sync()

try:
    runElectrodeSweep()
finally:
    # ---- always unsubscribe on exit, even if interrupted ----
    daq.unsubscribe(impedanceNode)
    outputFileHandle.close()
    print("Unsubscribed from impedance node, exiting.")