#define clockpin 13 // CI
#define datapin 11 // DI
#define enablepin 10 // EI
#define latchpin 9 // LI

#define TRIGGER_PIN 3
#define TRIGGER_GND 4

#include "hsvrgb.h"
#include "math.h"

#define NumLEDs 24

float hsv[3];
float level;
#define HIST_LEN 4

uint8_t but_hist;
uint8_t hist;
bool down;

int LEDChannels[NumLEDs][3];
int SB_CommandMode;
int SB_RedCommand;
int SB_GreenCommand;
int SB_BlueCommand;

volatile unsigned long interval;
volatile unsigned long time_last;

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
	unsigned long time = millis();

	if(time_last + 5 < time){
		hsv[0] = (float)random(256) / 256.0f;

		if(time_last != 0){
			interval = time - time_last;
		}
		time_last = time;
	}
}

void setup() {

	hist = 0;
	but_hist = 0;
	down = false;

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
	level = 0.0;
	hsv[0] = 0.0;
	hsv[1] = 1.0;
	hsv[2] = 0.0;

	interval = 0;
	time_last = 0;
}

void draw(unsigned long time){
	uint16_t rgb[3];

	level = (level + 0.005);
	if(level > 1.0f){
		level = 0.0f;
	}
	hsv[2] = sin(level * 1.57 + 4.71) + 1.0f;
	hsv2rgb(hsv, rgb);

	/*
	hsv[2] = 1.0;

	if(interval < 8 || (time % interval < (interval >> 1))){
		rgb[0] = 
			rgb[1] = 
			rgb[2] = 0;
	} else {
		hsv2rgb(hsv, rgb);
	}
	*/

	for(uint8_t i = 0; i < NumLEDs; i++){
		for(uint8_t j = 0; j < 3; j++)
			LEDChannels[i][j] = rgb[j];
	}
	WriteLEDArray();
}

void loop() {
	unsigned long time = millis();

	//check for a trigger
	if(digitalRead(TRIGGER_PIN))
		but_hist |= (1 << hist);
	else
		but_hist &= ~(1 << hist);

	hist = (hist + 1) % HIST_LEN;

	//up
	if(but_hist == 0x0F){
		down = false;
		//down
	} else if(but_hist == 0x00){
		if(!down){
			update();
			down = true;
		}
	}

	if(time % 10 == 0){
		draw(time);
	}
	
	/*
	hsv[0] = (hsv[0] + 0.01);
	if(hsv[0] > 1.0f)
		hsv[0] = 0.0f;
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
		uint16_t hsv[3];
		uint16_t rgb[3];
		hsv[0] = random(1024);
		hsv[1] = random(50);
		hsv[2] = random(50);
		hsv2rgb(hsv,rgb);

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
