import sys
sys.path.append('C:\\Users\\DaraioLab - Pectin\\Desktop\\Python Scripts\\SerialCom')
from SerialCom import SerialCom
import os

class TemperatureBoard:

    wave = {
        "sine": 's',
        "triangle": 't',
        "square": 'q',
        "pid": 'p'
    }

    def __init__(self, port: str, baudRate: int):
        self.__ser__ = SerialCom(port, baudRate)

    def begin(self):
        self.__ser__.begin()

    def end(self):
        self.__ser__.end()

    def disableOutput(self):
        self.__ser__.write('e')

    def setWave(self, function: str, frequency: str, amplitude: str, offset: str):
        command = self.__setFunction__(function)
        if function == self.wave["pid"]:
            print("Error: Invalid Format")
            errorCom = True
        else:
            command = self.__setFrequency__(frequency, command);
            command = self.__setAmplitude__(amplitude, command);
            command = self.__setOffset__(offset, command);
            errorCom = self.__ser__.write(''.join(command))
        return errorCom

    def setTemperature(self, function: str, setpoint: str):
        if function != self.wave["pid"]:
            print("Error: Invalid Format")
            errorCom = True
        else:
            command = self.__setFunction__(function)
            command = self.__setTemperature__(setpoint, command);
            errorCom = self.__ser__.write(''.join(command))
        return errorCom

    def setCalibration(self, degree: str, p1, p2, p3, p4: str):
        command = self.__setDegree__(degree)
        self.__setConstants__(p1, p2, p3, p4, command)

    def pollData(self, charNumber):
        #print('startpulldata')
        data = self.__ser__.requestData(charNumber)
        #print('pulleddata')
        return data

    def extractFromFile(self, directory: str, fileID: str):
        file = open(os.path.join(directory, fileID),'r')
        calibrationData = file.readlines()
        calibrationData = [float(i) for i in calibrationData]
        file.close()
        return calibrationData

    def selectFile(self, directory: str, fileID: str):
        print('itsopeningme')
        completePath = os.path.join(directory, fileID + '.txt')
        print(completePath)
        if not os.path.exists(completePath):
            file = open(completePath, 'w')
        else:
            overwrite = input('File already exists! Do you want to overwrite(y/n)? ')              ##TODO: Implement in the graphics
            if overwrite == 'y':
                file = open(completePath, 'w');
            else:
                fileIDNew = input("insert new file name: ")
                completePathNew = os.path.join(directory, fileIDNew + '.txt')
                file = open(completePathNew, 'w')
        return file

    def closeFile(self, file):
        file.close()

    def writeDataToFile(self, file, data, printSize = False):
        listData = []
        header = '\t'
        if os.stat(file.buffer.name).st_size == 0:
            for key in data:
                listData.append(key)
            header = header.join(listData) + '\n'
            file.write(header)
            file.close()
        else:
            if file.closed:
                file = open(file.name, 'a')
            if printSize: print("The Size of the file is {}".format(os.stat(file.buffer.name).st_size))
            for key, value in data.items():
                listData.append(str(value))
            header = header.join(listData) + '\n'
            file.write(header)

    ##Private Methods and Variables##

    ## command in the format:
    ## f: function
    ## frequency: fffmultiplier (allowed multiplier format +3, +0, -3)
    ## amplification: aaa in percentage (maximum allowed 100);
    ## offset:change with respect of no offset in the form of signaa
    __setWaveCmd__ = ['w', 'f', '0', '0', '1', '+', '0', '0', '0', '0', '+', '0', '0']

    ## command in the format:
    ## temperature: aaaa (the second two digits indicate . -> aa.aa real value)
    __setReferenceCmd__ = ['w', 'p', '0', '0', '0', '0']

    def __setFunction__(self, function: str):
        if function == self.wave["pid"]:
            command = self.__setReferenceCmd__
            command[1] = function
        else:
            command = self.__setWaveCmd__
            command [1] = function
        return command

    def __setFrequency__(self, frequency: str, command: list):
        index = 2
        for chr in frequency:
            command[index] = chr
            index += 1
        return command

    def __setAmplitude__(self, amplitude: str, command: list):
        index = 7
        for chr in amplitude:
            command[index] = chr
            index += 1
        return command

    def __setOffset__(self, offset: str, command: list):
        index = 10
        for chr in offset:
            command[index] = chr
            index += 1
        return command

    def __setTemperature__(self, temperature: str, command: list):
        index = 2
        for chr in temperature:
            if chr != '.':
                command[index] = chr
                index +=1
        return command


    __setCalibrationDeg__ = ['w', 'c', '0']                     ##degreee of the fitting polynomial for the pt100 (T = p1 + p2*R + p3*R^2 + p4*R^3)
    __setCalibration1__ =  ['0', '0', '0', '0']            ##1st coefficient of the fit
    __setCalibration2__ =  ['0', '0', '0', '0']            ##2nd coefficient of the fit
    __setCalibration3__ = ['0', '0', '0', '0']             ##3rd coefficient of the fit
    __setCalibration4__ = ['0', '0', '0', '0']             ##4th coefficient of the fit

    def __setDegree__(self, degree: str):
        command = self.__setCalibrationDeg__
        command[2] = degree
        return command

    def __setConstants__(self, p1, p2, p3, p4, command: list):
        None
