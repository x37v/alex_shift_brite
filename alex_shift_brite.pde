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

typedef struct _echo_pattern_data_t {
	long next_update;
	long last_update;
	bool on;
	long interval;
	float level;
	float level_mod;
	float hue;
} echo_pattern_data_t;

#define ECHO_PAT_LEN 4
//ms
#define ECHO_PAT_ON_LEN 30
volatile echo_pattern_data_t echo_pattern_data[ECHO_PAT_LEN];
volatile uint8_t echo_pattern_index;

uint8_t but_hist;
uint8_t hist;
bool down;

int LEDChannels[NumLEDs][3];
int SB_CommandMode;
int SB_RedCommand;
int SB_GreenCommand;
int SB_BlueCommand;

//volatile unsigned long global_interval;
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

/*
void update(){
	unsigned long time = millis();

	if(time_last + 5 < time){
		hsv[0] = (float)random(256) / 256.0f;

		if(time_last != 0){
			global_interval = time - time_last;
		}
		time_last = time;
	}
}
*/

void setup() {

	//a zero level means do not draw
	for(uint8_t i = 0; i < ECHO_PAT_LEN; i++){
		echo_pattern_data[i].level = 0.0f;
	}
	echo_pattern_index = 0;

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

	//global_interval = 0;
	time_last = 0;
}

void draw(unsigned long time, bool trig){
	uint16_t rgb[3];

#if 0
	//fade in on trig
	if(trig){
		hsv[0] = (float)random(256) / 256.0f;
		level = 0.01;

		//increment the echo pattern info
		echo_pattern_index = (echo_pattern_index + 1) % ECHO_PAT_LEN;
	} else if(level > 0.0f){
		level = (level + 0.02);

		if(hsv[0] >= 1.0f)
			hsv[0] -= 1.0f;

		if(level > 1.0f){
			level = 0.0f;
		}
	}

	hsv[2] = sin(level * 1.57 + 4.71) + 1.0f;
	hsv2rgb(hsv, rgb);
#endif


	if(trig){
		if(time_last != 0){
			long interval = (time - time_last) / 2;
			if(interval > (ECHO_PAT_ON_LEN + 20) && interval < 500){
				hsv[0] = (float)random(256) / 256.0f;
				echo_pattern_data[echo_pattern_index].interval = interval;
				echo_pattern_data[echo_pattern_index].next_update = time + ECHO_PAT_ON_LEN;
				echo_pattern_data[echo_pattern_index].last_update = time;
				echo_pattern_data[echo_pattern_index].level = 1.0;
				echo_pattern_data[echo_pattern_index].level_mod = -0.3;
				echo_pattern_data[echo_pattern_index].on = true;
				echo_pattern_data[echo_pattern_index].hue  = (float)random(256) / 256.0f;
				echo_pattern_index = (echo_pattern_index + 1) % ECHO_PAT_LEN;
			}
		}
		time_last = time;
	}

	hsv[0] = hsv[1] = hsv[2] = 0.0f;

	for(uint8_t i = 0; i < ECHO_PAT_LEN; i++){
		if(echo_pattern_data[i].level > 0.0f){
			//should we update?
			if(time >= echo_pattern_data[i].next_update){
				//swap the on state
				echo_pattern_data[i].on = !echo_pattern_data[i].on;

				//if it is on
				if(echo_pattern_data[i].on){
					echo_pattern_data[i].level += 
						echo_pattern_data[i].level_mod;

					if(echo_pattern_data[i].level <= 0.0f){
						echo_pattern_data[i].level = 0;
						continue;
					}
					//next update
					echo_pattern_data[i].next_update += ECHO_PAT_ON_LEN;

					//off
				} else {
					//next update
					echo_pattern_data[i].next_update += 
						(echo_pattern_data[i].interval - ECHO_PAT_ON_LEN);
				}
				echo_pattern_data[i].last_update = time;
			}

			if(echo_pattern_data[i].on){
				hsv[0] = echo_pattern_data[i].hue;
				hsv[1] = 1.0;
				//hsv[2] = sin((1.0f - echo_pattern_data[i].level) * 1.57 + 4.71) + 1.0f;
				hsv[2] = echo_pattern_data[i].level;
			}
		}
	}
	hsv2rgb(hsv, rgb);

	for(uint8_t i = 0; i < NumLEDs; i++){
		for(uint8_t j = 0; j < 3; j++)
			LEDChannels[i][j] = rgb[j];
	}
	WriteLEDArray();
}

void loop() {
	unsigned long time = millis();
	bool trig = false;

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
			trig = true;
			down = true;
		}
	}

	if(trig || (time % 2 == 0)){
		draw(time, trig);
	}
	
	/*
	hsv[0] = (hsv[0] + 0.01);
	if(hsv[0] > 1.0f)
		hsv[0] = 0.0f;
		*/

}
