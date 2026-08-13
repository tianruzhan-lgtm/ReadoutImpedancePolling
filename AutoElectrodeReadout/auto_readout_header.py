import sys
import numpy as np
import zhinst
import zhinst.toolkit
import json
import cmath
import matplotlib.pyplot as plt
import time
from MFIA import MFIA
import utils.helpers as helpers
import serial

# ---- Electrode readout settings ----
readoutPort = 'COM5'
readoutBaudRate = 115200
readoutSerial = serial.Serial(readoutPort, readoutBaudRate, timeout=0.1)

PAIR_INCOMING_MESSAGE = "P,"
IMPEDANCE_DONE_MESSAGE = b"D\n"

# ---- MFIA polling constants ----
RECORDING_TIME_S = 0.01
MIN_SAMPLES = 80
TIMEOUT_MS = 500
NUM_SWEEPS_DESIRED = 5

# ---- File destination ----
subDirectoryData = r"C:\Users\Daraio Lab\Documents\Data\Brian\EIT"
fileIDData = r"20260812_Exp1_PID_10"

# ---- MATLAB header metadata (fill these in per trial) ----
SAMPLE_NUMBER = "1"
DATE = "0812"
DESCRIPTION = "varied locations, increasing heat"        # e.g. "off-center electrode sweep, heat ramp"
TEMPERATURE = "20"
POSITION_X = "0.005"
POSITION_Y = "-0.03"
POSITION_Z = "0"
TYPE = "heat"               # "control" or "heat"

# ---- Output file setup ----
headerList_IARaw = ["timestamp", "z"]
headerList = ["time", "zreal", "zimag", "zmag", "zphase", "chA", "chB"]
outputFile = helpers.initializeData(subDirectoryData, fileIDData, headerList)


def prependHeaderBlock(filePath, sampleNumber, date, description,
                        temperature, positionX, positionY, positionZ, type_):
    """
    Reads the file at filePath (at this point it should contain only the
    column header row written by initializeData) and rewrites it with a
    "% Key: Value" metadata block inserted above that row. Must be called
    before any data rows are appended via recordData, since it reads and
    fully rewrites the file's current contents.
    """
    with open(filePath, 'r') as f:
        existingContent = f.read()

    headerBlockLines = [
        "% ===================== TRIAL HEADER =====================",
        f"% Sample Number: {sampleNumber}",
        f"% Date: {date}",
        f"% Description: {description}",
        f"% Temperature: {temperature}",
        f"% Position_X: {positionX}",
        f"% Position_Y: {positionY}",
        f"% Position_Z: {positionZ}",
        f"% Type: {type_}",
        "% ===========================================================",
    ]
    headerBlock = "\n".join(headerBlockLines) + "\n"

    with open(filePath, 'w') as f:
        f.write(headerBlock)
        f.write(existingContent)


prependHeaderBlock(outputFile, SAMPLE_NUMBER, DATE, DESCRIPTION,
                    TEMPERATURE, POSITION_X, POSITION_Y, POSITION_Z, TYPE)

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

def pollWriteRawImpedance(recordingTimeS, timeoutMs, chA, chB):
    #daq.subscribe(impedanceNode)
    daq.sync()

    dataSamplesLength = 0
    while dataSamplesLength < MIN_SAMPLES:
        IARawData = daq.pollEvent(timeoutMs)[impedanceNode]
        dataSamplesLength = len(IARawData['timestamp'])

    #daq.unsubscribe("*")

    timestamps = IARawData['timestamp']
    zValues = IARawData['z']

    lines = []
    for i in range(len(timestamps)):
        t = (float(timestamps[i]) / instrClockPeriod) - beginTime_DeviceInternal
        zreal = np.real(zValues[i])
        zimag = np.imag(zValues[i])
        zmag = np.abs(zValues[i])
        zphase = np.angle(zValues[i])
        lines.append(f"{t:.10g}\t{zreal:.6g}\t{zimag:.6g}\t{zmag:.6g}\t{zphase:.6g}\t{chA}\t{chB}")

    with open(outputFile, "a") as f:
        f.writelines(f"{line}\n" for line in lines)


def runElectrodeSweep():
    global sweepCounter

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

        pollWriteRawImpedance(RECORDING_TIME_S, TIMEOUT_MS, chA, chB)
        readoutSerial.write(IMPEDANCE_DONE_MESSAGE)

        if (chA == 14) and (chB == 15):
            sweepCounter+= 1
            if sweepCounter == NUM_SWEEPS_DESIRED:
                print(f"{sweepCounter} sweeps reached, ending now.")
                break




# ---- sweep ----
input("Press Enter to start the electrode sweep...")
readoutSerial.write(b"START\n")

daq.subscribe(impedanceNode)    # subscribe once, turn off at end
# daq.sync()
sweepCounter = 0

try:
    runElectrodeSweep()
finally:
    # ---- always unsubscribe on exit, even if interrupted ----
    daq.unsubscribe("*")
    print("Unsubscribed from impedance node, exiting.")