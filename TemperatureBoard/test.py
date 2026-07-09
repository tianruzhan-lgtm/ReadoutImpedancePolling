from TemperatureBoard import TemperatureBoard
import time

port = 'COM3'
baudRate = 1000000
subDirectoryCalibration = 'C:\\Users\\vcostanz\\Desktop\\Calibration SetUp\\Calibration Pt100\\'
fileIDCalibration = 'test.txt'

subDirectoryData = 'C:\\Users\\DaraioLab - Pectin\\Desktop'
fileIDData = 'test'

frequency = '010-3'
amplitude = '100'           ##percentage of the amplitude
temperature = '30.00'
charNumber = 5

temp = TemperatureBoard(port, baudRate)
temp.begin()

data = {"time": None, "temperature": None}

file = temp.selectFile(subDirectoryData, fileIDData)
input("press enter to continue...")
temp.writeDataToFile(file, data, True)
input("press enter to continue...")
temp.setTemperature(temp.wave["pid"], temperature)
for i in range(10):
    start = time.time()
    data["temperature"] = temp.pollData(charNumber)
    end = time.time()
    data["time"] = end-start
    temp.writeDataToFile(file, data)
temp.closeFile(file)

# temp.setTemperature(temp.wave["pid"], temperature)
#temp.setWave(temp.wave["sine"], frequency, amplitude)

# temperature = []
# timeElapsed = []

# for i in range(0,10000):
#     start = time.time()
#     temperature.append(temp.pollData(charNumber))
#     end = time.time()
#     timeElapsed.append(end-start)
#
temp.disableOutput()
temp.end()
#
# timeAbsolute = []
# sum = 0
# for object in timeElapsed:
#     sum += object
#     timeAbsolute.append(sum)
#
# temperature = [float(i) for i in temperature]
#
# plt.plot(timeAbsolute, temperature)
# plt.autoscale()
# plt.show()
# print(np.mean(timeElapsed))
