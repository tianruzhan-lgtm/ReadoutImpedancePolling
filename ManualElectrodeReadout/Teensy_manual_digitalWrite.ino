// -------------------------------- MANUAL MODE TEENSY SIDE (digitalWrite version, for debugging) -----------------------------

const int NUM_ELECTRODES = 16;

const int MUXA1 = 17;
const int MUXA2 = 16;
const int MUXA3 = 15;
const int MUXA4 = 14;

const int MUXB1 = 21;
const int MUXB2 = 20;
const int MUXB3 = 19;
const int MUXB4 = 18;

const int MUX_ENABLE = 22;

void setMuxChannels(uint8_t chA, uint8_t chB) {
  if (chA >= NUM_ELECTRODES || chB >= NUM_ELECTRODES) return;

  digitalWrite(MUXA1, (chA & 0b0001) ? HIGH : LOW);
  digitalWrite(MUXA2, (chA & 0b0010) ? HIGH : LOW);
  digitalWrite(MUXA3, (chA & 0b0100) ? HIGH : LOW);
  digitalWrite(MUXA4, (chA & 0b1000) ? HIGH : LOW);

  digitalWrite(MUXB1, (chB & 0b0001) ? HIGH : LOW);
  digitalWrite(MUXB2, (chB & 0b0010) ? HIGH : LOW);
  digitalWrite(MUXB3, (chB & 0b0100) ? HIGH : LOW);
  digitalWrite(MUXB4, (chB & 0b1000) ? HIGH : LOW);
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
    Serial.print("PAIR,");
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
  digitalWrite(MUX_ENABLE, HIGH);   // <-- see note below, check your mux's actual enable polarity

  Serial.println("Setup done. Send pair in format: a,b");
}

void loop() {
  if (Serial.available()) {
    String command = Serial.readStringUntil('\n');
    handleCommand(command);
  }
}