import sys
import numpy as np
import zhinst
import zhinst.toolkit
import json
import cmath
import matplotlib.pyplot as plt
import time
import signal
import threading
from TemperatureBoard import TemperatureBoard
from MFIA import MFIA
import helpers
import plotters
import serial

# ---- Electrode readout serial setup ----
readoutPort = 'COM5'
readoutBaudRate = 115200
readoutSerial = serial.Serial(readoutPort, readoutBaudRate, timeout=0.1)

# ---- File destination ----
subDirectoryData = r"C:\Users\Daraio Lab\Documents\Data\Brian\EIT"
fileIDData = r"20260728_ManualElectrodeReadout"

# ---- Output file setup ----
headerList_IARaw = ["timestamp", "z", "frequency"]
headerList = ["time", "zreal", "zimag", "zmag", "zphase", "frequency", "chA", "chB"]
outputFile = helpers.initializeData(subDirectoryData, fileIDData, headerList)

# ---- MFIA measurement constants ----
deviceID = 'dev3275'
amplitudeExct = 0.1
frequencyExct = 1000
currentRange = 1e-4
demodRate = 100e3
samplingRate = 0.001

# ---- Polling constants ----
POLL_INTERVAL_S = 0.1        # how often to poll in seconds
RECORDING_TIME_S = 0.05      # recording time during poll session
TIMEOUT_MS = 500

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

IAAvgData = {key: [] for key in headerList}


def sendPairAndWaitForConfirmation(chA, chB):
    command = f"{chA},{chB}\n"
    readoutSerial.write(command.encode())

    start = time.time()
    while time.time() - start < 2.0:
        line = readoutSerial.readline()
        if not line:
            continue

        line = line.decode(errors='ignore').strip()

        if line.startswith("PAIR"):
            parts = line.split(",")
            if len(parts) == 3:
                return int(parts[1]), int(parts[2])

        if line.startswith("ERROR"):
            print(f"Teensy reported error: {line}")
            return None

    print("Timed out waiting for Teensy confirmation")
    return None


# ---- Continuous polling for the currently-active pair ----

pollingThread = None
stopPollingEvent = threading.Event()


def continuousPollLoop(chA, chB, stopEvent):
    last_Polled = time.time()

    while not stopEvent.is_set():
        currentTime = time.time()

        if currentTime - last_Polled >= POLL_INTERVAL_S:
            last_Polled += POLL_INTERVAL_S

            daq.flush()
            daq.subscribe(impedanceNode)
            daq.sync()
            IARawData = daq.poll(RECORDING_TIME_S, TIMEOUT_MS, 0, True)[impedanceNode]
            daq.unsubscribe("*")

            for key in headerList_IARaw:
                values = IARawData[key]
                if key == 'timestamp':
                    IAAvgData['time'].append((float(np.mean(values)) / instrClockPeriod) - beginTime_DeviceInternal)
                if key == 'z':
                    IAAvgData['zmag'].append(np.mean(np.abs(values)))
                    IAAvgData['zphase'].append(np.mean(np.angle(values)))
                    IAAvgData['zreal'].append(np.mean(np.real(values)))
                    IAAvgData['zimag'].append(np.mean(np.imag(values)))
                if key == 'frequency':
                    IAAvgData['frequency'].append(np.mean(values))

            IAAvgData['chA'].append(chA)
            IAAvgData['chB'].append(chB)

            helpers.recordData(outputFile, IAAvgData, headerList)

            print(f"[{chA},{chB}] zmag={IAAvgData['zmag'][-1]:.2f}")

        time.sleep(0.005)


def startPollingForPair(chA, chB):
    global pollingThread, stopPollingEvent

    stopActivePolling()

    stopPollingEvent = threading.Event()
    pollingThread = threading.Thread(
        target=continuousPollLoop,
        args=(chA, chB, stopPollingEvent),
        daemon=True
    )
    pollingThread.start()


def stopActivePolling():
    global pollingThread, stopPollingEvent

    if pollingThread is not None and pollingThread.is_alive():
        stopPollingEvent.set()
        pollingThread.join()

    pollingThread = None


def runInteractiveSweep():
    print("Enter electrode pair as chA,chB (or 'q' to quit)")
    print(f"Polling every {POLL_INTERVAL_S}s while a pair is active, until you switch pairs.")

    try:
        while True:
            userInput = input("> ").strip()

            if userInput.lower() == 'q':
                break

            if ',' not in userInput:
                print("Invalid format. Use: chA,chB")
                continue

            try:
                chA_requested, chB_requested = userInput.split(",")
                int(chA_requested)
                int(chB_requested)
            except ValueError:
                print("Invalid format. Use: chA,chB")
                continue

            confirmed = sendPairAndWaitForConfirmation(chA_requested, chB_requested)
            if confirmed is None:
                print("Skipping — no polling started due to error/timeout")
                continue

            chA, chB = confirmed
            print(f"Switched to pair ({chA}, {chB}) — polling started")
            startPollingForPair(chA, chB)

    finally:
        stopActivePolling()
        readoutSerial.write(b"DONE\n")


# ---- Start interactive sweep ----
runInteractiveSweep()