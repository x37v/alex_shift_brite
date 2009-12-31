#define clockpin 13 // CI
#define datapin 11 // DI
#define enablepin 10 // EI
#define latchpin 9 // LI

#define TRIGGER_PIN 3
#define TRIGGER_GND 4

#define ANALOG_TRIGGER_PIN 0
#define ANALOG_TRIGGER_GND 7

#include "hsvrgb.h"
#include "math.h"

#define NumLEDs 24

#define ANALOG_THRES 170
#define TRIGGER_MIN_INTERVAL 200

volatile unsigned long trigger_next;

typedef enum {
	FADE,
	QUAD_ECHO,
	ROTATION
} pattern_t;

volatile pattern_t led_pattern;

float hsv[3];
#define HIST_LEN 4

typedef struct _fade_pattern_data_t {
	float fade_level;
	unsigned long start_evolve;
} fade_pattern_data_t;

fade_pattern_data_t fade_pattern_data;

#define FADE_PATTERN_EVOLVE_DELAY 200

typedef struct _echo_pattern_data_t {
	unsigned long next_update;
	bool on;
	long interval;
	float level;
	float level_mod;
	float hue;
} echo_pattern_data_t;

#define ECHO_PAT_LEN 4
//ms
#define ECHO_PAT_ON_LEN 40
volatile echo_pattern_data_t echo_pattern_data[ECHO_PAT_LEN];
volatile uint8_t echo_pattern_index;

#define ROTATION_GUY_COUNT 6
typedef struct _rotation_guy_t {
	bool active;
	float position;
	float position_mod;
	float hue;
	uint8_t length;
} rotation_guy_t;

typedef struct _rotation_pattern {
	rotation_guy_t guys[ROTATION_GUY_COUNT];
	uint8_t index;
	unsigned long last_time;
} rotation_pattern_t;

rotation_pattern_t rotation_pattern_data;

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

void set_pattern(pattern_t new_pat){
	led_pattern = new_pat;
	switch(led_pattern){
		case FADE:
			fade_pattern_data.fade_level = 0.0;
			fade_pattern_data.start_evolve = 0;
			break;
		case QUAD_ECHO:
			//a zero level means do not draw
			for(uint8_t i = 0; i < ECHO_PAT_LEN; i++){
				echo_pattern_data[i].level = 0.0f;
			}
			echo_pattern_index = 0;
			break;
		case ROTATION:
			rotation_pattern_data.index = 0;
			rotation_pattern_data.last_time = 0;
			for(uint8_t i = 0; i < ROTATION_GUY_COUNT; i++)
				rotation_pattern_data.guys[i].active = false;
			break;
		default:
			break;
	}
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

	//init the pattern
	set_pattern(FADE);

	hist = 0;
	but_hist = 0;
	down = false;

	trigger_next = 0;

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

	//set the analog trigger to be an output and set to zero
	pinMode(ANALOG_TRIGGER_GND, OUTPUT);
	digitalWrite(ANALOG_TRIGGER_GND, LOW);

	//set the trigger pin to be an input, with pullup
	pinMode(TRIGGER_PIN, INPUT);
	DDRD &= ~(1 << TRIGGER_PIN);
	PORTD |= (1 << TRIGGER_PIN);

	clear();
	delay(10);
	WriteLEDArray();
	hsv[0] = 0.0;
	hsv[1] = 1.0;
	hsv[2] = 0.0;

	//global_interval = 0;
	time_last = 0;
}

void draw(pattern_t pattern, unsigned long time, bool trig){
	uint16_t rgb[3];
	rotation_guy_t * guy = NULL;

	switch(pattern){
		case FADE:
			//fade in on trig
			if(trig){
				hsv[0] = (float)random(256) / 256.0f;
				fade_pattern_data.fade_level = 0.01;
				fade_pattern_data.start_evolve = 0;

			} else if(fade_pattern_data.fade_level > 0.0f){
				fade_pattern_data.fade_level = (fade_pattern_data.fade_level + 0.003);

				if(hsv[0] >= 1.0f)
					hsv[0] -= 1.0f;

				if(fade_pattern_data.fade_level >= 1.0f){
					fade_pattern_data.fade_level = 1.0f;
					//after FADE_PATTERN_EVOLVE_DELAY, evolve
					fade_pattern_data.start_evolve = time + FADE_PATTERN_EVOLVE_DELAY;
				}
			}
			if(fade_pattern_data.start_evolve && 
					fade_pattern_data.start_evolve >= time){
				hsv[0] += 0.0001;
				if(hsv[0] >= 1.0f)
					hsv[0] -= 1.0f;
			}

			hsv[2] = sin(fade_pattern_data.fade_level * 1.57 + 4.71) + 1.0f;
			hsv2rgb(hsv, rgb);

			for(uint8_t i = 0; i < NumLEDs; i++){
				for(uint8_t j = 0; j < 3; j++)
					LEDChannels[i][j] = rgb[j];
			}
			break;
		case QUAD_ECHO:
			clear();
			if(trig){
				if(time_last != 0){
					long interval = (time - time_last) / 2;
					if(interval > (ECHO_PAT_ON_LEN + 20) && interval < 500){
						uint8_t span = 1;
						float hue = (float)random(256) / 256.0f;
						//every once in a while draw to the whole ring..
						if(random(255) > 170)
							span = 4;
						for(uint8_t i = 0; i < span; i++){
							hsv[0] = (float)random(256) / 256.0f;
							echo_pattern_data[echo_pattern_index].interval = interval;
							echo_pattern_data[echo_pattern_index].next_update = time + ECHO_PAT_ON_LEN;
							echo_pattern_data[echo_pattern_index].level = 1.0;
							echo_pattern_data[echo_pattern_index].level_mod = -0.15;
							echo_pattern_data[echo_pattern_index].on = true;
							echo_pattern_data[echo_pattern_index].hue = hue;
							echo_pattern_index = (echo_pattern_index + 1) % ECHO_PAT_LEN;
						}
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

							//if the level becomes less than or equal to zero skip this quad
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
					}

					//if the quad is on then draw it to its quad
					if(echo_pattern_data[i].on){
						hsv[0] = echo_pattern_data[i].hue;
						hsv[1] = 1.0;
						//hsv[2] = sin((1.0f - echo_pattern_data[i].level) * 1.57 + 4.71) + 1.0f;
						hsv[2] = echo_pattern_data[i].level;
						hsv2rgb(hsv, rgb);
						for(uint8_t j = (i * 6); j < (i * 6 + 6); j++){
							for(uint8_t k = 0; k < 3; k++)
								LEDChannels[j][k] = rgb[k];
						}
					}
				}
			}
			break;
		case ROTATION:
			clear();
			if(trig){
				if(rotation_pattern_data.last_time != 0){
					guy = &rotation_pattern_data.guys[rotation_pattern_data.index];
					//increment for next time
					rotation_pattern_data.index = (rotation_pattern_data.index + 1) % ROTATION_GUY_COUNT;
					guy->active = true;
					if(random(255) > 170)
						guy->length = random(4);
					else
						guy->length = 1;
					guy->position = 0.0f;
					guy->position_mod = 12.0f / (float)(time - rotation_pattern_data.last_time);
					guy->hue = (float)random(256) / 256.0f;
				}
				rotation_pattern_data.last_time = time;
			}
			for(uint8_t i = 0; i < ROTATION_GUY_COUNT; i++){
				guy = &rotation_pattern_data.guys[i];
				if(guy->active){
					//on a trig, reverse
					if(trig)
						guy->position_mod = -guy->position_mod;
					guy->position += guy->position_mod;
					//keep in range
					while(guy->position >= NumLEDs)
						guy->position -= NumLEDs;
					while(guy->position < 0.0f)
						guy->position += NumLEDs;
					hsv[0] = guy->hue;
					hsv[1] = 1.0;
					hsv[2] = 1.0;
					hsv2rgb(hsv, rgb);
					//just for now, draw over whatever is there
					for(uint8_t j = 0; j < guy->length; j++){
						uint8_t idx = (uint8_t)(j + guy->position) % NumLEDs;
						for(uint8_t k = 0; k < 3; k++)
							LEDChannels[idx][k] = rgb[k];
					}
				}
			}
			break;
		default:
			break;
	}

	WriteLEDArray();
}

void loop() {
	unsigned long time = millis();
	uint8_t analog_val = analogRead(ANALOG_TRIGGER_PIN);
	bool trig = false;

	/*
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
	*/

	//if we're above the threshold and the time is greater than
	//the time threshold
	if(analog_val >= ANALOG_THRES && time >= trigger_next ){
		trig = true;
		//set the minimum time for the next trigger
		trigger_next = time + TRIGGER_MIN_INTERVAL;
	}

	//draw on a trig, or every 2 milliseconds
	if(trig || (time % 2 == 0)){
		draw(led_pattern, time, trig);
	}
}
