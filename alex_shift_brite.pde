#define clockpin 13 // CI
#define datapin 11 // DI
#define enablepin 10 // EI
#define latchpin 9 // LI

#define TRIGGER_PIN 3
#define TRIGGER_GND 4

#include "hslrgb.h"

#define NumLEDs 24

float hsl[3];

int LEDChannels[NumLEDs][3];
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
	  SB_RedCommand = LEDChannels[h][0] & 0x3ff;
	  SB_GreenCommand = LEDChannels[h][1] & 0x3ff;
	  SB_BlueCommand = LEDChannels[h][2] & 0x3ff;
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

void update(){
	hsl[0] = (float)random(256) / 256.0f;
	hsl[1] = (float)random(256) / 256.0f;
}

void setup() {

   pinMode(datapin, OUTPUT);
   pinMode(latchpin, OUTPUT);
   pinMode(enablepin, OUTPUT);
   pinMode(clockpin, OUTPUT);
   SPCR = (1<<SPE)|(1<<MSTR)|(0<<SPR1)|(0<<SPR0);
   digitalWrite(latchpin, LOW);
   digitalWrite(enablepin, LOW);

	//set the trigger ground to be an output, set it to zero
	pinMode(TRIGGER_GND, OUTPUT);
	digitalWrite(TRIGGER_GND, LOW);
	//set the trigger pin to be an input, with pullup
	pinMode(TRIGGER_PIN, INPUT);
	DDRD &= ~(1 << TRIGGER_PIN);
	PORTD |= (1 << TRIGGER_PIN);

	clear();
	delay(10);
	WriteLEDArray();
	hsl[0] = 0.9;
	hsl[1] = 0.5;
	hsl[2] = 0.1;

	//interrupt on button down
	attachInterrupt(1, update, FALLING);
}

void loop() {
	uint16_t rgb[3];

	hsl2rgb(hsl, rgb);
	for(uint8_t i = 0; i < NumLEDs; i++){
		for(uint8_t j = 0; j < 3; j++)
			LEDChannels[i][j] = rgb[j];
	}
	WriteLEDArray();
	delay(5);
	
	/*
	hsl[0] = (hsl[0] + 0.01);
	if(hsl[0] > 1.0f)
		hsl[0] = 0.0f;
	*/

#if 0
	int tmp[3];

	for(uint8_t i = 0; i < 3; i++)
		tmp[i] = LEDChannels[NumLEDs - 1][i];

	for(uint8_t i = NumLEDs - 1; i > 0; i--){
		for(uint8_t j = 0; j < 3; j++)
			LEDChannels[i][j] = LEDChannels[i - 1][j];
	}

	if(random(16) > 14){
		uint16_t hsl[3];
		uint16_t rgb[3];
		hsl[0] = random(1024);
		hsl[1] = random(50);
		hsl[2] = random(50);
		hsl2rgb(hsl,rgb);

		/*
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
		*/
		for(uint8_t i = 0; i < 3; i++)
			LEDChannels[0][i] = rgb[i];
	} else {
		for(uint8_t i = 0; i < 3; i++)
			LEDChannels[0][i] = tmp[i];
	}

	if(random(256) > 251)
		clear();

   WriteLEDArray();
	delay(40);
#endif
}
