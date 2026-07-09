import zhinst
import zhinst.utils
import zhinst.ziPython
import numpy as np
import time
import math

class MFIA:

    def __init__(self, deviceID):
        apiLevel = 6
        errMsg = "Impossible to create the API session."
        (self.__daq__, self.__device__, self.__props__) = zhinst.utils.create_api_session(deviceID, apiLevel,
                                                           required_devtype='.*LI|.*IA|.*IS',
                                                           required_err_msg=errMsg)
        print("MFIA successfully connected")

    def set2TerminalMode(self, amplitude, frequency, currentRange, demodRate, samplingRate, timeOut = 500):
        self.__outChannel__ = 0
        self.__outMixerChannel__ = zhinst.utils.default_output_mixer_channel(self.__props__)
        self.__inChannel__ = 0
        self.__demodIndex__ = 0
        self.__oscIndex__ = 0
        impIndex = 0
        self.__currIndex__ = self.__daq__.getInt('/%s/imps/%d/current/inputselect' % (self.__device__, impIndex))
        self.__voltIndex__ = self.__daq__.getInt('/%s/imps/%d/voltage/inputselect' % (self.__device__, impIndex))
        timeConstant = 10/frequency
        expSetting = [['/%s/sigins/%d/ac' % (self.__device__,self.__inChannel__), 0],
                      ['/%s/sigins/%d/range' % (self.__device__, self.__inChannel__), 2 * amplitude],
                      ['/%s/demods/%d/enable' % (self.__device__, self.__demodIndex__), 1],
                      ['/%s/demods/%d/rate' % (self.__device__, self.__demodIndex__), demodRate],
                      ['/%s/demods/%d/adcselect' % (self.__device__, self.__demodIndex__), self.__inChannel__],
                      ['/%s/demods/%d/order' % (self.__device__, self.__demodIndex__), 4],
                      ['/%s/demods/%d/timeconstant' % (self.__device__, self.__demodIndex__), timeConstant],
                      ['/%s/demods/%d/oscselect' % (self.__device__, self.__demodIndex__), self.__oscIndex__],
                      ['/%s/demods/%d/harmonic' % (self.__device__, self.__demodIndex__), 1],
                      ['/%s/oscs/%d/freq' % (self.__device__, self.__oscIndex__), frequency],
                      ['/%s/sigouts/%d/on' % (self.__device__, self.__outChannel__), 1],
                      ['/%s/sigouts/%d/enables/%d' % (self.__device__, self.__outChannel__, self.__outMixerChannel__), 1],
                      ['/%s/sigouts/%d/range' % (self.__device__, self.__outChannel__), 1],
                      ['/%s/sigouts/%d/amplitudes/%d' % (self.__device__, self.__outChannel__, self.__outMixerChannel__), amplitude],
                      ['/%s/currins/%d/range' % (self.__device__, self.__currIndex__), currentRange]]

        self.__daq__.set(expSetting)
        self.__node__ = '/%s/demods/%d/sample' % (self.__device__, self.__demodIndex__)
        self.__samplingRate__ = samplingRate  # [s]
        self.__timeOut__ = timeOut  # [ms]
        self.__pollFlags__ = 0
        self.__pollReturnFlatDict__ = True
        print("2 Terminal Mode set")

    def begin(self):
        self.__daq__.subscribe(self.__node__)

    def end(self):
        self.__daq__.unsubscribe(self.__node__)

    def getData(self):
        start = time.time()
        tempData = self.__daq__.getSample(self.__node__)
        abs = np.abs(tempData['x'] + 1j * tempData['y'])
        phs = np.angle(tempData['x'] + 1j * tempData['y'])
        end = time.time()
        data = {"time": end - start,
                "abs": abs,
                "phs": math.degrees(phs),
                "size": 0,
                "frequency": tempData['frequency']}
        return data

    def pollData(self):
        start = time.time()
        self.__daq__.flush()
        poll = True
        while poll:
            demodData = self.__daq__.poll(self.__samplingRate__, self.__timeOut__, self.__pollFlags__, self.__pollReturnFlatDict__)
            if self.__node__ in demodData:
                poll = False
        end = time.time()
        tempData = demodData[self.__node__]
        abs = np.mean(np.abs(tempData['x'] + 1j * tempData['y']))
        phs = np.mean(np.angle(tempData['x'] + 1j * tempData['y']))
        frequency = np.mean(tempData['frequency'])
        size = len(tempData['x'])
        data = {"time": end - start,
                "abs": abs,
                "phs": phs,
                "size": size,
                "frequency": frequency}
        return data

    ##Accuracy of the sweep:
    ##0: fast speed/low accuracy
    ##1: standard speed/high accuracy
    ##2: slow speed/very high accuracy
    def sweeperSet(self, startFrequency, endFrequency, samples, logScale = 1,accuracy = 1):
        if accuracy == 0:
            omegaSuppression = 60
            maxBandwidth = 1e3
            minimumWaitTime = 0
            inaccuracy = 10e-3
            countTC = 5
            samplesTC = 20
            timeTC = 10e-3
        elif accuracy == 1:
            omegaSuppression = 80
            maxBandwidth = 100
            minimumWaitTime = 0
            inaccuracy = 10e-3
            countTC = 15
            samplesTC = 20
            timeTC = 100e-3
        elif accuracy == 2:
            omegaSuppression = 120
            maxBandwidth = 10
            minimumWaitTime = 0
            inaccuracy = 100e-6
            countTC = 25
            samplesTC = 20
            timeTC = 1

        bandwidthControl = 2
        bandwidthOverlap = 1
        scan = 0

        self.__sweeper__ = self.__daq__.sweep()
        self.__sweeper__.set('sweep/device', self.__device__)
        self.__sweeper__.set('sweep/gridnode', 'oscs/%d/freq' % self.__oscIndex__)
        self.__sweeper__.set('sweep/start', startFrequency)
        self.__sweeper__.set('sweep/stop', endFrequency)
        self.__sweeper__.set('sweep/samplecount', samples)
        ##frequency spacing: 0 - lin spacing/1 - log spacing
        self.__sweeper__.set('sweep/xmapping', logScale)
        ##Bandwidth settings control: 0-Manual/ 1-Fixed / 2-Auto (Reccommended for log sweep)
        self.__sweeper__.set('sweep/bandwidthcontrol', bandwidthControl)
        ## 1-Enable / 0-Disabled
        self.__sweeper__.set('sweep/bandwidthoverlap', bandwidthOverlap)
        self.__sweeper__.set('sweep/omegasuppression', omegaSuppression)
        self.__sweeper__.set('sweep/maxbandwidth', maxBandwidth)
        self.__sweeper__.set('sweep/settling/time', minimumWaitTime)
        self.__sweeper__.set('sweep/settling/inaccuracy', inaccuracy)
        self.__sweeper__.set('sweep/averaging/tc', countTC)
        self.__sweeper__.set('sweep/averaging/sample', samplesTC)
        self.__sweeper__.set('sweep/averaging/time', timeTC)
        self.__sweeper__.set('sweep/scan', scan)


    def sweeperStart (self):
        self.__sweeperPath__ = '/%s/demods/%d/sample' % (self.__device__, self.__demodIndex__)
        self.__sweeper__.subscribe(self.__sweeperPath__)
        self.__sweeper__.execute()

    def sweeperRead (self):
        if self.__sweeper__.progress() > 0:
            temp_data = self.__sweeper__.read(True)
            # assert temp_data, 'read() returned an empty data dictionary'
            # assert self.__sweeperPath__ in temp_data, "No sweep data in data dictionary: it has no key '%s'" % self.__sweeperPath__
            samples = temp_data[self.__sweeperPath__]
            data = {'frequency': samples[0][0]['frequency'],
                    'abs': samples[0][0]['r'],
                    'phs': samples[0][0]['phase'],
                    'x': samples[0][0]['x'],
                    'y': samples[0][0]['y'],
                    'nan': False}
            if (not np.isnan(data['frequency']).any() and not np.isnan(data['abs']).any()
                and not np.isnan(data['phs']).any() and not np.isnan(data['x']).any() and not np.isnan(data['y']).any()):
                data['nan'] = False
            else:
                data['nan'] = True
            return data
        else:
            print('No Data Available')
            data = {}
            return data

    def sweeperStatus (self):
        status = {'progress': None,
                  'done': None}
        status['progress'] = self.__sweeper__.progress()
        status['done'] = self.__sweeper__.finished()
        return status

    def sweeperClose (self):
        self.__sweeper__.unsubscribe(self.__sweeperPath__)
        self.__sweeper__.clear()

    def setLCRMode (self):
        self.__daq__.setInt(['/dev4216/system/impedance/application/1'])

    def setAmplitude (self, amplitude):
        self.__daq__.set([['/%s/sigins/%d/range' % (self.__device__, self.__inChannel__), 2 * amplitude],
                          ['/%s/sigouts/%d/amplitudes/%d' % (self.__device__, self.__outChannel__, self.__outMixerChannel__), amplitude]])


    def setFrequency (self, frequency):
        timeConstant = 10 / frequency
        self.__daq__.set([['/%s/demods/%d/timeconstant' % (self.__device__, self.__demodIndex__), timeConstant],
                          ['/%s/oscs/%d/freq' % (self.__device__, self.__oscIndex__), frequency]])

    def autoRange(self):
        finishedAuto = False
        triggerAuto = [['/%s/currins/%d/autorange' % (self.__device__, self.__currIndex__), 1],
                       ['/%s/sigins/%d/autorange' % (self.__device__, self.__voltIndex__), 1]]
        self.__daq__.set(triggerAuto)
        while not finishedAuto:
            autorange_curr = self.__daq__.getInt('/%s/currins/%d/autorange' % (self.__device__, self.__currIndex__))
            autorange_volt = self.__daq__.getInt('/%s/currins/%d/autorange' % (self.__device__, self.__voltIndex__))
            finishedAuto = (autorange_curr == 0) and (autorange_volt == 0)


    def adjustRange(self, range):
        impIndex = 0
        settings = [['/%s/imps/%d/auto/inputrange' % (self.__device__, impIndex), 0],
                    ['/%s/sigouts/%d/range' % (self.__device__, self.__outChannel__), 1],
                    ['/%s/currins/%d/range' % (self.__device__, self.__currIndex__), range]]
        self.__daq__.set(settings)

    def end(self):
        self.__daq__.unsubscribe(self.__node__)