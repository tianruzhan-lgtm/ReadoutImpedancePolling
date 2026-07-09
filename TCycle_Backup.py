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

temperatureControlPort = 'COM4'
humidityControlPort = 'COM8'
tboardbaudRate = 1000000
hboardBaudRate = 38400
# Start humidity serial with matching baud rate in HumidityControl_V2.3_Brian
humidityser = serial.Serial('COM8', hboardBaudRate, timeout = 0.9)

##### Current Reading Settings #####
deviceID = 'dev4216'
amplitudeExct = 0.1      # Amplitude of the excitation sine in V
frequencyExct = 1000      # Driving Signal Frequency
currentRange = 1e-4 # used to be 1e-3
demodRate = 100e3           ###DO NOT CHANGE
samplingRate = 0.001        ###DO NOT CHANGE
# TODO: currently, the amplitude, frequency are not doing anything because we are no longer using the MFIA obj. Implement.

# Define destination of the file
subDirectoryData = r"C:\Users\DaraioLab - Pectin\Desktop\MaxTepermeister"  #Folder where the data are saved
#fileIDData = r"20251209_P3APixel_65CBake_P3A1CaCl1_2000Hz_100mV_PostCycling" #### change here file name
fileIDData = r"20260422_0p1M_KCl_PEG"
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
info = json.loads(devs_json)["DEV4216"]  # uppercase key
print("INTERFACE:", info["INTERFACE"])
print("INTERFACES:", info["INTERFACES"])
print("STATUS:", info.get("STATUS", "<no STATUS field>"))


daq = session.daq_server #Initialize DAQ
impedanceNode = "/dev4216/imps/0/sample" # Node to subscribe to
# daq.subscribe(impedanceNode) # Subscribe to data node. Actually, should be done later. for reasons.
device = session.connect_device("dev4216", interface="1GbE") # Connect to device
#Debug code: Confirms that we have connected to device
timestamp = device.status.time()
instrClockPeriod = 60000000 # 60 MHz. Period of the internal clock in the MFIA Imp. Analyzer.
print(timestamp/instrClockPeriod)

# Actual Settings for Sinusoidal Temperature Cycling
center = 21    # midpoint (°C) was at 30
amplitude = 0 # ±16 around the center => 12 to 48
num_points = 300        # how many discrete steps in one full cycle
# Generates a Sinusoid
temps_array = center + amplitude * np.sin(
    np.linspace(0, 2*np.pi, num_points, endpoint=False)
)
temperatures = [f"{temp:.2f}" for temp in temps_array]
# Needed for the loop. Determines how many times to cycle temp.
nsteps = 99999
holdTime = 1 # How long to hold at each temp. In seconds

# Used by the Temperature Board. Internal Variable for data parsing. do not change or perish.
charNumber = 5

# Connect to Temperature Board
# TemperatureBoard is the board Object
temp = TemperatureBoard(temperatureControlPort, tboardbaudRate)
temp.begin()

# Automatically disable port when pressing ctrl-c
# A method defn, but in the middle of the code in the last implementation. Better way of doing this?
def signal_handler(sig, frame):
    print('You pressed Ctrl+C!')
    temp.disableOutput()
    print("Output Disabled")
    temp.end()
signal.signal(signal.SIGINT, signal_handler) # Idk wtf this does, I am putting this in here because it was in last code

# Creates the file - or either overwrites, or prompts user for new file.
headerList_IARaw = ["timestamp", "z", "frequency"]
headerList = ["time", "zreal", "zimag", "zmag", "zphase", "frequency", "temperature", "humidity"]
outputFile = helpers.initializeData(subDirectoryData, fileIDData, headerList)

# Lock in Amplifier Initializing?
#lockIn = MFIA(deviceID)
#lockIn.set2TerminalMode(amplitudeExct, frequencyExct, currentRange, demodRate, samplingRate)
#lockIn.begin()

# Create the plotting window
mainFigure = plotters.TCyclePlot()

# Begin polling impedance data
pollingFreq = 1 # How often we poll, in seconds
last_Polled = time.time()
last_TCtrld = time.time()
time.sleep(1.005)
temperatureInd = 0
beginTime_DeviceInternal = (device.status.time()/instrClockPeriod) # Time that we began polling, in seconds, according to internal clock

# List where we will store all our data for plotting
IAAvgData = {key: [] for key in headerList}
humidityser.write(b"s\n") # This lets the arduino know that we are starting.
while True:
    currentTime = time.time()

    # Run the polling
    if currentTime - last_Polled >= pollingFreq:
        last_Polled = currentTime
        # We need poll from both the temperature board and the Impedance Analyzer
        # IA Polling
        daq.flush()
        daq.subscribe(impedanceNode) # Subscribe to data node
        daq.sync()
        IARawData = daq.poll(0.1, 500, 0, True)[impedanceNode]
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

        #TemperatureBoard Polling
        temperatureData = temp.pollData(charNumber)
        IAAvgData['temperature'].append(float(temperatureData))

        # TODO: Humidity Polling. Just default to 50 for now.
        # 2026/02/09 We are implementing the humidity polling
        humidityser.flush()
        while humidityser.in_waiting > 0:
            humidityser.read(humidityser.in_waiting) # Flush any data in buffer from ard before I request it.
        readRequestByte = b"r\n"
        humidityser.write(readRequestByte)
        humidityData = humidityser.readline()
        if humidityData.startswith(b"h"):
            humidityData = float(humidityData[1:].decode())
        else:
            humidityData = 99.99 # PlaceHolder humidity data.
        IAAvgData['humidity'].append(humidityData)
        # Debug
        for key in IAAvgData:
            print(key, IAAvgData[key][-1])

        # Update the Plotting Data
        #mainFigure.update_axA(IAAvgData['time'], IAAvgData['temperature'],(IAAvgData['zmag']/1000))
        mainFigure.update_axA(IAAvgData['time'], IAAvgData['temperature'], [float(x) / 1000 for x in IAAvgData['zmag']])
        #mainFigure.update_axA(IAAvgData['time'], IAAvgData['temperature'], [float(x) for x in IAAvgData['zmag']])
        mainFigure.update_axB(IAAvgData['time'], IAAvgData['humidity'])
        mainFigure.update_axC(IAAvgData['temperature'], IAAvgData['zmag'], IAAvgData['zphase'])

        # Record data to file
        helpers.recordData(outputFile, IAAvgData, headerList)

    # Run the PID for the temperature board
    if currentTime - last_TCtrld >= holdTime:
        currentTemp = temperatures[temperatureInd]
        print(currentTemp)
        temp.setTemperature(temp.wave["pid"], str(currentTemp))
        temperatureInd = (temperatureInd + 1) % len(temperatures)  # Reset the temperatureInd index if it wraps around
        last_TCtrld = currentTime

    # Runs more or less continuously
    plt.pause(0.01)
    time.sleep(0.005) # Don't want to set CPU at 100%
impdata = device.imps[0].output.amplitude
print(impdata)
print("hi")
