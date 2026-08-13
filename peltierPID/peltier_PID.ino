#include <Adafruit_MAX31865.h>

// ---------------- MAX31865 / PT100 setup ----------------
Adafruit_MAX31865 thermo = Adafruit_MAX31865(10, 11, 12, 13); // CS, DI, DO, CLK (software SPI)
#define RREF      2200.0  // confirmed reference resistor value for this board
#define RNOMINAL  1000.0   // 0°C nominal resistance — 100.0 for PT100, 1000.0 for PT1000 — verify against sensor in use

// ---------------- DRV8874 pin assignments ----------------
const int PIN_EN     = 2;   // PWM speed/duty input (must be a PWM-capable pin)
const int PIN_PH     = 3;   // direction / polarity
const int PIN_NFAULT = 5;   // driver fault flag, active low
const int PIN_FAN_RELAY = 4; // fan relay control — ON/OFF only, relay cannot produce partial voltage

// ---------------- Tunable constants ----------------
const float VM_VOLTAGE          = 12.0;    // supply voltage feeding DRV8874 VM (V) — update if bench supply changes
const int   PWM_FREQ_HZ         = 80000;  // target switching frequency
const int   PWM_RESOLUTION      = 8;      // bits of PWM resolution
const float SAFETY_MAX_VOLTAGE  = 12;    // theoretical output voltage ceiling — shuts down above this

const unsigned long CONTROL_PERIOD_MS = 100;  // PID compute + status print interval
const unsigned long SAMPLE_INTERVAL_MS = 10;  // raw temperature sampling interval, feeds the moving average

// ---------------- PID gains — Kp/Ki/Kd all live-adjustable via K:/I:/D: commands ----------------
float Kp = 10.0;
float Ki = 0.0;
float Kd = 0.0;

// ---------------- Moving average filter ----------------
const int MOVING_AVERAGE_WINDOW_SIZE = 20; // number of fast samples averaged together
float temperatureSampleBuffer[MOVING_AVERAGE_WINDOW_SIZE];
int   temperatureSampleBufferIndex = 0;
bool  temperatureSampleBufferIsFull = false;
float temperatureSampleBufferSum = 0.0;
float filteredTemperatureC = 0.0;

// ---------------- State ----------------
float setpointC = 0.0;
bool  started = false;
bool  shutdownTriggered = false;

float integral = 0.0;
float lastError = 0.0;

int   currentDutyCounts = 0;
bool  currentSide = false; // false = side A, true = side B

String serialLineBuffer = "";
unsigned long lastControlTime = 0;
unsigned long lastSampleTime = 0;

// ---------------- Fault tolerance ----------------
const int FAULT_TOLERANCE_COUNT = 3;        // faults allowed within the window before full shutdown
const unsigned long FAULT_WINDOW_MS = 500;  // window in which repeated faults are counted

int faultCountInWindow = 0;
unsigned long faultWindowStartTime = 0;

void setup() {
  Serial.begin(115200);

  pinMode(PIN_PH, OUTPUT);
  pinMode(PIN_EN, OUTPUT);
  pinMode(PIN_NFAULT, INPUT_PULLUP);
  pinMode(PIN_FAN_RELAY, OUTPUT);
  digitalWrite(PIN_FAN_RELAY, LOW); // fan off until a setpoint is set

  digitalWrite(PIN_PH, LOW);
  digitalWrite(PIN_EN, LOW);

  analogWriteFrequency(PIN_EN, PWM_FREQ_HZ);
  analogWriteResolution(PWM_RESOLUTION);

  thermo.begin(MAX31865_2WIRE); // set to 2WIRE/3WIRE/4WIRE as matches your wiring

  for (int i = 0; i < MOVING_AVERAGE_WINDOW_SIZE; i = i + 1) {
    temperatureSampleBuffer[i] = 0.0;
  }

  for (int i = 0; i < MOVING_AVERAGE_WINDOW_SIZE; i = i + 1) {
    float primingSample = thermo.temperature(RNOMINAL, RREF);
    filteredTemperatureC = updateMovingAverage(primingSample);
    delay(SAMPLE_INTERVAL_MS);
  }

  Serial.println("Ready. Commands: 'T: <temp>' setpoint, 'K: <value>' Kp, 'I: <value>' Ki, 'D: <value>' Kd, 'START' to begin.");
  Serial.print("nFAULT at boot: ");
  Serial.println(digitalRead(PIN_NFAULT));
}

void loop() {
  handleSerialInput();

  if (shutdownTriggered == true) {
    return;
  }

  checkFaultWithTolerance();

  updateTemperatureSamplingIfDue();

  if (started == false) {
    return;
  }

  if (millis() - lastControlTime >= CONTROL_PERIOD_MS) {
    lastControlTime = millis();
    runControlCycle();
  }
}

// ---------------- Fault handling ----------------
void checkFaultWithTolerance() {
  if (digitalRead(PIN_NFAULT) != LOW) {
    return;
  }

  unsigned long now = millis();

  if (now - faultWindowStartTime > FAULT_WINDOW_MS) {
    faultWindowStartTime = now;
    faultCountInWindow = 0;
  }

  faultCountInWindow = faultCountInWindow + 1;
  Serial.print("nFAULT event #");
  Serial.print(faultCountInWindow);
  Serial.print(" within window (tolerance ");
  Serial.print(FAULT_TOLERANCE_COUNT);
  Serial.println(")");

  if (faultCountInWindow > FAULT_TOLERANCE_COUNT) {
    triggerShutdown("REPEATED DRIVER FAULT (nFAULT asserted too often)", 0.0);
  }

  delay(3);
}

void updateTemperatureSamplingIfDue() {
  if (millis() - lastSampleTime < SAMPLE_INTERVAL_MS) {
    return;
  }
  lastSampleTime = millis();

  float rawSample = thermo.temperature(RNOMINAL, RREF);
  filteredTemperatureC = updateMovingAverage(rawSample);
}

float updateMovingAverage(float newSample) {
  temperatureSampleBufferSum = temperatureSampleBufferSum - temperatureSampleBuffer[temperatureSampleBufferIndex];
  temperatureSampleBuffer[temperatureSampleBufferIndex] = newSample;
  temperatureSampleBufferSum = temperatureSampleBufferSum + newSample;

  temperatureSampleBufferIndex = temperatureSampleBufferIndex + 1;
  if (temperatureSampleBufferIndex >= MOVING_AVERAGE_WINDOW_SIZE) {
    temperatureSampleBufferIndex = 0;
    temperatureSampleBufferIsFull = true;
  }

  int sampleCount;
  if (temperatureSampleBufferIsFull == true) {
    sampleCount = MOVING_AVERAGE_WINDOW_SIZE;
  } else {
    sampleCount = temperatureSampleBufferIndex;
  }

  if (sampleCount == 0) {
    return newSample;
  }

  return temperatureSampleBufferSum / sampleCount;
}

void handleSerialInput() {
  while (Serial.available()) {
    char incomingChar = Serial.read();
    if (incomingChar == '\n') {
      processCommandLine(serialLineBuffer);
      serialLineBuffer = "";
    } else if (incomingChar != '\r') {
      serialLineBuffer = serialLineBuffer + incomingChar;
    }
  }
}

void processCommandLine(String line) {
  line.trim();
  if (line.length() == 0) {
    return;
  }

  if (line.startsWith("T:") || line.startsWith("t:")) {
    setpointC = line.substring(2).toFloat();
    Serial.print("Setpoint set to ");
    Serial.print(setpointC);
    Serial.println(" C");
  } else if (line.startsWith("K:") || line.startsWith("k:")) {
    Kp = line.substring(2).toFloat();
    Serial.print("Kp set to ");
    Serial.println(Kp);
  } else if (line.startsWith("I:") || line.startsWith("i:")) {
    Ki = line.substring(2).toFloat();
    Serial.print("Ki set to ");
    Serial.println(Ki);
  } else if (line.startsWith("D:") || line.startsWith("d:")) {
    Kd = line.substring(2).toFloat();
    Serial.print("Kd set to ");
    Serial.println(Kd);
  } else if (line.equalsIgnoreCase("START")) {
    started = true;
    lastControlTime = millis();
    digitalWrite(PIN_FAN_RELAY, HIGH);
    Serial.println("Started.");
  } else {
    Serial.print("Unrecognized command: ");
    Serial.println(line);
  }
}

void runControlCycle() {
  float currentTemp = filteredTemperatureC;
  float dt = CONTROL_PERIOD_MS / 1000.0;

  float error = setpointC - currentTemp;

  float proposedIntegral = integral + (error * dt);
  float derivative = (error - lastError) / dt;

  float proportionalTerm = Kp * error;
  float integralTerm = Ki * proposedIntegral;
  float derivativeTerm = Kd * derivative;

  float output = proportionalTerm + integralTerm + derivativeTerm;

  int maxDutyCounts = (1 << PWM_RESOLUTION) - 1;
  int rawDutyCounts = (int)(fabs(output));
  bool saturated = false;

  if (rawDutyCounts > maxDutyCounts) {
    rawDutyCounts = maxDutyCounts;
    saturated = true;
  }

  if (saturated == false) {
    integral = proposedIntegral;
  }
  lastError = error;

  currentDutyCounts = rawDutyCounts;

  if (output < 0) {
    currentSide = true;
  } else {
    currentSide = false;
  }

  float theoreticalVoltage = VM_VOLTAGE * ((float)currentDutyCounts / (float)maxDutyCounts);

  if (theoreticalVoltage > SAFETY_MAX_VOLTAGE) {
    triggerShutdown("THEORETICAL VOLTAGE EXCEEDED LIMIT", theoreticalVoltage);
    return;
  }

  if (currentSide == true) {
    digitalWrite(PIN_PH, HIGH);
  } else {
    digitalWrite(PIN_PH, LOW);
  }
  analogWrite(PIN_EN, currentDutyCounts);

  printStatus(currentTemp, theoreticalVoltage);
}

void printStatus(float currentTemp, float theoreticalVoltage) {
  Serial.print("DATA,");
  Serial.print(millis());
  Serial.print(",");
  Serial.print(currentTemp, 4);
  Serial.print(",");
  Serial.print(setpointC, 2);
  Serial.print(",");
  Serial.print(currentDutyCounts);
  Serial.print(",");
  Serial.print(theoreticalVoltage, 4);
  Serial.print(",");
  Serial.print(Kp, 4);
  Serial.print(",");
  Serial.print(Ki, 4);
  Serial.print(",");
  Serial.println(Kd, 4);
}

void triggerShutdown(const char* reason, float theoreticalVoltage) {
  analogWrite(PIN_EN, 0);
  digitalWrite(PIN_PH, LOW);
  shutdownTriggered = true;
  Serial.print("SHUTDOWN: ");
  Serial.print(reason);
  Serial.print(" (V_theoretical = ");
  Serial.print(theoreticalVoltage, 4);
  Serial.println(" V)");
}