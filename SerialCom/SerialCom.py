import serial
import time

class SerialCom:
    def __init__(self, port: str, baudRate: int, timeOut = 1.0):
        self.__serialObj__ = serial.Serial()
        self.__serialObj__.port = port
        self.__serialObj__.baudrate = baudRate
        self.__serialObj__.timeout = timeOut
        #self.__serialObj__.dtr = False
        print("class initialized")

    def begin(self):
        if self.__serialObj__.is_open:
            print("Port already open")
            return True
        else:
            self.__serialObj__.open()
            return self.__waitForResponse__()


    def end(self):
        self.__serialObj__.close()
        print("Port closed")

    def write(self, data: str):
        if not self.__beginTransaction__():
            for singleData in data:
                errorCom = self.__writeByte__(singleData)
                if errorCom:
                    break
            # if not errorCom:
            #     self.__endTransaction__()
            return errorCom
        else:
            return False

    def requestData(self, bytesRequested : int):
        #print('requestingdata')
        if not self.__beginTransaction__():
            self.__send__(self.__readByte__)
            data = self.__receive__(bytesRequested)
            #print('gotdata')
            return data
        else:
            return False

    ##Private Methods and Variables##
    __startByte__ = 's'
    __stopByte__ = 'e'
    __ackByte__ = 'a'
    __readByte__ = 'r'

    def __writeByte__(self, singleByte, referenceByte =  __ackByte__):
        self.__send__(singleByte)
        returnByte = self.__receive__()
        errorCom = not self.__ackCheck__(returnByte, referenceByte)
        #print(returnByte)
        return errorCom


    ### For Debug Only ####
    def __writeMirror__(self, dataOut: str):
        self.__beginTransaction__()
        start = time.time()
        for singleData in dataOut:
            errorCom = self.__writeByte__(singleData, singleData)
            ## print(errorCom)
            if errorCom:
                break
        end = time.time()
        print(end-start)
        return errorCom
    #########################

    def __send__(self, dataOut: str):
        self.__serialObj__.write(dataOut.encode())
        #print(dataOut)

    # def __receive__(self, bytesToRead = 0):
    #     while self.__serialObj__.in_waiting == 0:
    #         None
    #     while self.__serialObj__.in_waiting > 0:
    #         print(self.__serialObj__.in_waiting)
    #         if self.__serialObj__.in_waiting >= bytesToRead:
    #             print("true")
    #             dataIn = self.__serialObj__.read(self.__serialObj__.in_waiting)
    #     return dataIn.decode()

    def __receive__(self, bytesToRead = 1):
        while self.__serialObj__.in_waiting < bytesToRead:
            None
        while self.__serialObj__.in_waiting >= bytesToRead:
            dataIn = self.__serialObj__.read(self.__serialObj__.in_waiting)
            return dataIn.decode()


    def __ackCheck__(self, byteToCheck: str, ackByte = __ackByte__):
        return byteToCheck == ackByte

    def __beginTransaction__(self):
        self.__send__(self.__startByte__)
        returnByte = self.__receive__()
        return not self.__ackCheck__(returnByte)

    def __endTransaction__(self):
        self.__send__(self.__stopByte__)
        returnByte = self.__receive__()
        return not self.__ackCheck__(returnByte)

    def __waitForResponse__(self):
        returnByte = self.__receive__()
        errorCom = not self.__ackCheck__(returnByte, self.__startByte__)
        print(f"[DEBUG] received: {returnByte!r}, expected sync: {self.__startByte__!r}")
        if not errorCom:
            self.__send__(self.__ackByte__)
            print("Port ready")
        else:
            print("Wrong sync character")
        return errorCom