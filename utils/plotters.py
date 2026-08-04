import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from matplotlib.pyplot import axvspan

class TCyclePlot:
    def __init__(self):
        plt.ion() # Turns on interactive mode so they can be updated
        self.mainFig = plt.figure(figsize=(15,8)) # Width and height in inches

        # Fig A will be plotting x: time, y: temperature and impedance
        # Fig B will be plotting x: time, y: humidity
        # Fig C will be plotting x: temperature, y: magnitude and phase
        # Fig D will be plotting the complex impedance as a phasor, maybe later.

        self.mainFigGrid = GridSpec(
            nrows = 2,
            ncols = 2,
            figure = self.mainFig,
            height_ratios=[1.5, 0.5],
            width_ratios=[2.0, 1.0]
        )

        self.axA = self.mainFig.add_subplot(self.mainFigGrid[0,0])
        self.axB = self.mainFig.add_subplot(self.mainFigGrid[1,0])
        self.axC = self.mainFig.add_subplot(self.mainFigGrid[0,1])
        self.axA_right = self.axA.twinx()
        self.axA_right.set_yscale("log")
        self.axC_right = self.axC.twinx()
        self.axC.set_yscale("log")


        # Define Title
        self.axA.set_title("Temperature/Impedance Magnitude vs Time", fontdict={"fontsize": 16})
        self.axB.set_title("Humidity vs Time", fontdict={"fontsize": 16})
        self.axC.set_title("Impedance Magnitude/Phase vs Temperature", fontdict={"fontsize": 16})

        # Define Axis Labels
        self.axA.set_xlabel("Time (s)", fontsize=14)
        self.axA.set_ylabel("Temperature (°C)", fontsize=14)
        self.axA_right.set_ylabel("Impedance (kΩ)", fontsize=14)
        self.axB.set_xlabel("Time (s)", fontsize=14)
        self.axB.set_ylabel("Humidity (%RH)", fontsize=14)
        self.axC.set_xlabel("Temperature (°C)", fontsize=14)
        self.axC.set_ylabel("Impedance (kΩ)", fontsize=14)
        self.axC_right.set_ylabel("Phase (deg)", fontsize=14)
        #

        #Empty Filler Lines that we can update later
        self.line_TempvsTime, = self.axA.plot([], [], color="tab:red", label="Temperature")
        self.line_ImpedancevsTime, = self.axA_right.plot([], [], color="tab:blue", label="Impedance")
        self.line_HumidityvsTime, = self.axB.plot([], [], label="Humidity")
        self.line_MagnitudevsTemperature, = self.axC.plot([], [], color="tab:blue", label="Impedance Magnitude")
        self.line_PhasevsTemperature, = self.axC_right.plot([], [], color="tab:orange", label="Impedance Phase")

        # Color matching with lines and axes
        self.axA.yaxis.label.set_color("tab:red")
        self.axA.tick_params(axis="y", colors="tab:red")
        self.axA_right.yaxis.label.set_color("tab:blue")
        self.axA_right.tick_params(axis="y", colors="tab:blue")

        self.axC.yaxis.label.set_color("tab:blue")
        self.axC.tick_params(axis="y", colors="tab:blue")
        self.axC_right.yaxis.label.set_color("tab:orange")
        self.axC_right.tick_params(axis="y", colors="tab:orange")

        # Define legends
        linesA = [self.line_TempvsTime, self.line_ImpedancevsTime]
        labelsA = [line.get_label() for line in linesA]
        self.axA.legend(linesA, labelsA, loc="best")
        self.axB.legend(loc="best")
        linesC = [self.line_MagnitudevsTemperature, self.line_PhasevsTemperature]
        labelsC = [line.get_label() for line in linesC]
        self.axC.legend(linesC, labelsC, loc="best")

        # Tight layout so things don’t overlap
        self.mainFig.tight_layout()

    def update_axA(self, timeData, temperatureData, impedanceData):
        self.line_TempvsTime.set_data(timeData, temperatureData)
        self.line_ImpedancevsTime.set_data(timeData, impedanceData)
        self.axA.relim()
        self.axA.autoscale_view()
        self.axA_right.relim()
        self.axA_right.autoscale_view()
        #self.mainFig.canvas.draw_idle()

    def update_axB(self, timeData, humidityData):
        self.line_HumidityvsTime.set_data(timeData, humidityData)
        self.axB.relim()
        self.axB.autoscale_view()
        #self.mainFig.canvas.draw_idle()

    def update_axC(self, temperatureData, impedanceData, phaseData):
        self.line_MagnitudevsTemperature.set_data(temperatureData, impedanceData)
        self.line_PhasevsTemperature.set_data(temperatureData, phaseData)
        self.axC.relim()
        self.axC.autoscale_view()
        self.axC_right.relim()
        self.axC_right.autoscale_view()
        #self.mainFig.canvas.draw_idle()

    def refresh(self):
        self.mainFig.canvas.draw_idle()
        self.mainFig.canvas.flush_events()

if __name__ == "__main__":
    exampleFigure = TCyclePlot()
    exampleTime = []
    exampleTemperature = []
    exampleImpedance = []
    plt.show(block=True)