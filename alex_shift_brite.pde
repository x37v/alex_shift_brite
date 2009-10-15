#define clockpin 13 // CI
#define datapin 11 // DI
#define enablepin 10 // EI
#define latchpin 9 // LI

#define NumLEDs 24
int LEDChannels[NumLEDs][3] = {0};
int SB_CommandMode;
int SB_RedCommand;
int SB_GreenCommand;
int SB_BlueCommand;

void clear() {
	for(uint8_t i = 0; i < NumLEDs; i++){
		for(uint8_t j = 0; j < 3; j++)
			LEDChannels[i][j] = 0;
	}
}

void SB_SendPacket() {

    if (SB_CommandMode == B01) {
     SB_RedCommand = 120;
     SB_GreenCommand = 100;
     SB_BlueCommand = 100;
    }

    SPDR = SB_CommandMode << 6 | SB_BlueCommand>>4;
    while(!(SPSR & (1<<SPIF)));
    SPDR = SB_BlueCommand<<4 | SB_RedCommand>>6;
    while(!(SPSR & (1<<SPIF)));
    SPDR = SB_RedCommand << 2 | SB_GreenCommand>>8;
    while(!(SPSR & (1<<SPIF)));
    SPDR = SB_GreenCommand;
    while(!(SPSR & (1<<SPIF)));

}

void WriteLEDArray() {

    SB_CommandMode = B00; // Write to PWM control registers
    for (int h = 0;h<NumLEDs;h++) {
	  SB_RedCommand = LEDChannels[h][0];
	  SB_GreenCommand = LEDChannels[h][1];
	  SB_BlueCommand = LEDChannels[h][2];
	  SB_SendPacket();
    }

    delayMicroseconds(15);
    digitalWrite(latchpin,HIGH); // latch data into registers
    delayMicroseconds(15);
    digitalWrite(latchpin,LOW);

    SB_CommandMode = B01; // Write to current control registers
    for (int z = 0; z < NumLEDs; z++) SB_SendPacket();
    delayMicroseconds(15);
    digitalWrite(latchpin,HIGH); // latch data into registers
    delayMicroseconds(15);
    digitalWrite(latchpin,LOW);

}

void setup() {

   pinMode(datapin, OUTPUT);
   pinMode(latchpin, OUTPUT);
   pinMode(enablepin, OUTPUT);
   pinMode(clockpin, OUTPUT);
   SPCR = (1<<SPE)|(1<<MSTR)|(0<<SPR1)|(0<<SPR0);
   digitalWrite(latchpin, LOW);
   digitalWrite(enablepin, LOW);

	clear();
	delay(10);
	WriteLEDArray();
}

void loop() {
	int tmp[3];

	for(uint8_t i = 0; i < 3; i++)
		tmp[i] = LEDChannels[NumLEDs - 1][i];

	for(uint8_t i = NumLEDs - 1; i > 0; i--){
		for(uint8_t j = 0; j < 3; j++)
			LEDChannels[i][j] = LEDChannels[i - 1][j];
	}

	if(random(16) > 14){
		uint8_t i = random(4);
		LEDChannels[0][0] = 
			LEDChannels[0][1] = 
			LEDChannels[0][2] = 0;
		if(i < 3)
			LEDChannels[0][i] = random(512);
		else {
			LEDChannels[0][0] = random(512);
			LEDChannels[0][1] = random(256);
			LEDChannels[0][2] = random(256);
		}
	} else {
		//for(uint8_t i = 0; i < 3; i++)
			//LEDChannels[0][i] = tmp[i];
	}

	//if(random(256) > 251)
		//clear();
//
   WriteLEDArray();
	delay(40);
}
