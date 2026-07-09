import sys
sys.path.append('C:\\Users\\DaraioLab - Pectin\\Desktop\\Python Scripts\\SerialCom')
from SerialCom import SerialCom
import time


baudRate = 1000000
port = 'COM3'

print("Start")
arduino = SerialCom(port, baudRate)
arduino.begin()

print('requested Data')
start = time.time()
data = arduino.requestData(6)
end = time.time()

print(data)
print(end-start)

# arduino.__writeMirror__('a')
arduino.end()
# print(data)
# a = []
# start = time.time()
# for i in range(0,5):
#     a = a.append[25.30]
# a = np.array(a)
# end = time.time()
# print(end-start)