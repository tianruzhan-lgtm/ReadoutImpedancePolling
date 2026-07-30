// ---- SYSTEM SETTINGS ----

// time constants (all in microseconds)
const unsigned long CYCLE_TARGET_TIME = 10000000;
const unsigned long TIMEOUT_TIME = 5000000;                                    // need to set

unsigned long cycleStartTime;
unsigned long stateTimer;
unsigned long currentTime;

// serial message values
const char* PAIR_INCOMING_MESSAGE = "P,";
const char* DONE_MESSAGE = "D";


// ---- READOUT TEENSY SIDE ----

// ---- MUXING FUNCTIONS ---- 
// FYI: bitmask values depend on mux pins

// system settings
const int NUM_ELECTRODES = 16;
const int MAX_PAIRS = (NUM_ELECTRODES * (NUM_ELECTRODES - 1)) / 2;

// mux pins for declaring pin direction

const int MUXA1 = 17;
const int MUXA2 = 16;
const int MUXA3 = 15;
const int MUXA4 = 14;

const int MUXB1 = 21;
const int MUXB2 = 20;
const int MUXB3 = 19;
const int MUXB4 = 18;

const int MUX_ENABLE = 29;

// output ports that hold pins for setting mux channels
// GPIO6 hosts pins 21-14 (MUXA1 - MUXB4)
uint32_t maskGPIO6;

// tables that hold the bit values pushed to output ports that turn on each channel
uint32_t muxABitsGPIO6[NUM_ELECTRODES];
uint32_t muxBBitsGPIO6[NUM_ELECTRODES];


void setupMuxLookupTables() {

  for (int channel = 0; channel < NUM_ELECTRODES; channel++) {      // set up bitmask table for mux A
    uint32_t bitsMuxA = 0;                                          // each table index holds bitmask to turn on respective channel
    if (channel & 0b0001) { bitsMuxA |= CORE_PIN17_BITMASK; }
    if (channel & 0b0010) { bitsMuxA |= CORE_PIN16_BITMASK; }
    if (channel & 0b0100) { bitsMuxA |= CORE_PIN15_BITMASK; }
    if (channel & 0b1000) { bitsMuxA |= CORE_PIN14_BITMASK; }

    muxABitsGPIO6[channel] = bitsMuxA;
  }

  for (int channel = 0; channel < NUM_ELECTRODES; channel++) {      // set up bitmask table for mux B
    uint32_t bitsMuxB6 = 0; 
    if (channel & 0b0001) { bitsMuxB6 |= CORE_PIN21_BITMASK; }
    if (channel & 0b0010) { bitsMuxB6 |= CORE_PIN20_BITMASK; }
    if (channel & 0b0100) { bitsMuxB6 |= CORE_PIN19_BITMASK; }
    if (channel & 0b1000) { bitsMuxB6 |= CORE_PIN18_BITMASK; }

    muxBBitsGPIO6[channel] = bitsMuxB6;
  }

  maskGPIO6 = CORE_PIN14_BITMASK | CORE_PIN15_BITMASK | CORE_PIN16_BITMASK | CORE_PIN17_BITMASK
              | CORE_PIN18_BITMASK | CORE_PIN19_BITMASK | CORE_PIN20_BITMASK | CORE_PIN21_BITMASK; 

}


inline void setMuxChannels(uint8_t chA, uint8_t chB) {
  if (chA >= NUM_ELECTRODES || chB >= NUM_ELECTRODES) { return; }                 // check if passed channels are valid

  GPIO6_DR = (GPIO6_DR & ~maskGPIO6) | muxABitsGPIO6[chA] | muxBBitsGPIO6[chB];   // send appropiate bitmask to output registers without modifying other bits
}


// ---- SERIAL RECEIVING FUNCTIONS ----

const int SERIAL_BUF_SIZE = 32;                                 // max message length
char serialBuf[SERIAL_BUF_SIZE];
int serialBufIndex = 0;

bool readMessage(char* outBuf, int outBufSize) {                // copies received serial message into a buffer, which caller then reads
    while (Serial.available()) {
        char c = Serial.read();

        if (c == '\n') {
            serialBuf[serialBufIndex] = '\0';
            snprintf(outBuf, outBufSize, "%s", serialBuf);

            serialBufIndex = 0;
            return true;
        }
        else if (serialBufIndex < SERIAL_BUF_SIZE - 1) {
            serialBuf[serialBufIndex] = c;
            serialBufIndex++;
        }
        else {
            serialBufIndex = 0;
        }
    }
    return false;
}

// ---- STATE MACHINE ----

// state machine declarations
struct electrodePair {
  uint8_t firstElectrode;
  uint8_t secondElectrode;
};

electrodePair pairTable[MAX_PAIRS];
int pairIndex = 0;



enum SystemState {
  SET_ELECTRODES,
  WAIT_IMPEDANCE,
  PAD_CYCLE,
  ERROR_HALT
};

SystemState currentState = SET_ELECTRODES;

void advanceToNextPair() {
  pairIndex++;

  if (pairIndex >= MAX_PAIRS) {
    pairIndex = 0;
    currentState = PAD_CYCLE;
  } 

  else {
    currentState = SET_ELECTRODES;
  }
}

void updateReadout() {
  currentTime = micros();

  if (currentState == SET_ELECTRODES) {
    electrodePair pair = pairTable[pairIndex];
    setMuxChannels(pair.firstElectrode, pair.secondElectrode);

    Serial.print(PAIR_INCOMING_MESSAGE);
    Serial.print(pair.firstElectrode);
    Serial.print(",");
    Serial.println(pair.secondElectrode);

    stateTimer = currentTime;
    currentState = WAIT_IMPEDANCE;
  }

  else if (currentState == WAIT_IMPEDANCE) {
    char incoming[SERIAL_BUF_SIZE];

    if (readMessage(incoming, sizeof(incoming))) {
      if (strcmp(incoming, DONE_MESSAGE) == 0) {
        advanceToNextPair();
      }
    }
    else if (currentTime - stateTimer > TIMEOUT_TIME) {
      Serial.print("ERROR,TIMEOUT,PAIR,");
      Serial.println(pairIndex);
      currentState = ERROR_HALT;
    }
  }

  else if (currentState == PAD_CYCLE) {
    if (currentTime - cycleStartTime > CYCLE_TARGET_TIME) {
      cycleStartTime = currentTime;
      currentState = SET_ELECTRODES;
    }
  }

  else if (currentState == ERROR_HALT) {
    // sweep stopped, do nothing further until reset
  }
}

// ---- SETUP / LOOP ----

void setup() {

  for (uint8_t i = 0; i < NUM_ELECTRODES - 1; i++) {                // set up electrode pairs
    for (uint8_t j = i + 1; j < NUM_ELECTRODES; j++) {
      pairTable[pairIndex] = {i, j};
      pairIndex++;
    }
  }

  pairIndex = 0;

  pinMode(MUXA1, OUTPUT);                                   // set direction of all Teensy pins used
  pinMode(MUXA2, OUTPUT);
  pinMode(MUXA3, OUTPUT);
  pinMode(MUXA4, OUTPUT);

  pinMode(MUXB1, OUTPUT);
  pinMode(MUXB2, OUTPUT);
  pinMode(MUXB3, OUTPUT);
  pinMode(MUXB4, OUTPUT);

  pinMode(MUX_ENABLE, OUTPUT);
  digitalWrite(MUX_ENABLE, HIGH);

  setupMuxLookupTables();

  cycleStartTime = micros();
}



void loop() {
  updateReadout();
}