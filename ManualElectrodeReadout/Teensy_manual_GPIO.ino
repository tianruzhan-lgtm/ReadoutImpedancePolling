#include <Arduino.h>

// ----------------------------------------------- MUXING FUNCTIONS ----------------------------------------------


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

// -------------------- MANUAL SELECTION OF ELECTRODE PAIRS -----------------------

void handleCommand(String command) {
  command.trim();

  int commaIndex = command.indexOf(',');

  if (commaIndex == -1) {
    Serial.println("ERROR BAD_MESSAGE");
    return;
  }

  int chA = command.substring(0, commaIndex).toInt();
  int chB = command.substring(commaIndex + 1).toInt();

  if (chA >= 0 && chA < NUM_ELECTRODES && chB >= 0 && chB < NUM_ELECTRODES) {
    setMuxChannels((uint8_t)chA, (uint8_t)chB);
    Serial.print("MANUAL_SET,");
    Serial.print(chA);
    Serial.print(",");
    Serial.println(chB);
  }
  else {
    Serial.println("ERROR INVALID_CHANNEL");
  }
}

// ------------------------------------------- SETUP / LOOP ----------------------------------------

void setup() {
  Serial.begin(115200);

  pinMode(MUXA1, OUTPUT);
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
  Serial.println("Setup done. Send pair in format: a,b");
}

void loop() {
  if (Serial.available()) {
    String command = Serial.readStringUntil('\n');
    handleCommand(command);
  }
}