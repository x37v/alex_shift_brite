#define clockpin 13 // CI
#define datapin 11 // DI
#define enablepin 14 // EI
#define latchpin 10 // LI

/*
#define clockpin 13 // CI
#define datapin 11 // DI
#define enablepin 10 // EI
#define latchpin 9 // LI
*/

//#define PATTERN_SEL_PIN 3
//#define PATTERN_SEL_GND 4

#define PATTERN_SEL_PIN 17

#define ANALOG_TRIGGER_PIN 4
#define ANALOG_PULLUP_PIN 18
//15 == analog 1
//#define ANALOG_PATTERN_SEL_GND 15

#define SEVEN_SEG_A 2
#define SEVEN_SEG_B 3
#define SEVEN_SEG_C 4
#define SEVEN_SEG_D 5
#define SEVEN_SEG_E 6
#define SEVEN_SEG_F 7
#define SEVEN_SEG_G 8
#define SEVEN_SEG_P 9

#define NUM_LEDS 24
#define HALF_NUM_LEDS 12

#define ANALOG_THRESH_POS 700
#define ANALOG_THRESH_NEG 300
#define TRIGGER_MIN_INTERVAL 200
#define TRIG_DISPLAY_TIME 50

//ms
#define SWELL_TIME 300.0f

#define NUM_ECHOS 6

#include "hsvrgb.h"
#include "math.h"
#include <avr/pgmspace.h>


typedef enum {
	NONE = 0,
	SWELL,
	SINGLE_GUY,
	MULT_GUYS,
	MODE_WIPE,
	QUAD_ECHO,
	VERT_MIRROR,
	GATE,
	ECHO,
	ROTATION,
	//FADE,
	//WIPE,
	PATTERN_T_END
} pattern_t;

float hsv[3];
#define HIST_LEN 4

/*
typedef struct _fade_pattern_data_t {
	float fade_level;
	unsigned long start_evolve;
} fade_pattern_data_t;

fade_pattern_data_t fade_pattern_data;
*/

#define FADE_EVOLVE_DELAY 200
#define WIPE_EVOLVE_DELAY 1000

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
#define ECHO_PAT_ON_LEN 60
volatile echo_pattern_data_t echo_pattern_data[ECHO_PAT_LEN];
volatile uint8_t echo_pattern_index;

#define ROTATION_GUY_COUNT 4
#define ROTATION_ACCEL_TIME 80
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

/*
typedef struct _wipe_pattern_data_t {
	bool active;
	bool wipe_forward;
	float position;
	float position_mod;
	float hue;
	unsigned long last_time;
	unsigned long start_evolve;
} wipe_pattern_data_t;

//wipe_pattern_data_t wipe_pattern_data;
*/


//light_guy stuff

enum fbdk_t { MULT, ADD };

typedef struct _light_guy_data_t {
	bool active;
	unsigned int length;
	fbdk_t fbdk_type;
	float position;
	float position_last;
	float position_mod;
	float hv[2];
	// fbdk is hue and value
	float fbdk[2];
	//we only care about h and v 
	float draw_buffer[NUM_LEDS][2];
} light_guy_data_t;

#define NUM_LIGHT_GUYS 3
light_guy_data_t light_guys[NUM_LIGHT_GUYS];
uint8_t light_guys_index;


//uint8_t mode_wipe_ends[] = { 24, 12, 8, 6, 4, 3, 2, 2, 3, 4, 6, 8, 12, 24};
//#define MODE_WIPE_PATTERN_LEN 14
//#define HALF_MODE_WIPE_LEN 7

uint8_t mode_wipe_ends[] = { 24, 12, 8, 6, 4, 3, 3, 4, 6, 8, 12, 24};
#define MODE_WIPE_PATTERN_LEN 12
#define HALF_MODE_WIPE_LEN 6

uint8_t but_hist;
uint8_t hist;
bool down;
unsigned long draw_time_last;
unsigned long trigger_last;

int LEDChannels[NUM_LEDS][3];
int SB_CommandMode;
int SB_RedCommand;
int SB_GreenCommand;
int SB_BlueCommand;

//volatile unsigned long global_interval;
//volatile unsigned long time_last;

//prototypes
void set_display(uint8_t val);
void clear();
void SB_SendPacket();
void WriteLEDArray();
void set_pattern(pattern_t new_pat);


void clear() {
	for(uint8_t i = 0; i < NUM_LEDS; i++){
		for(uint8_t j = 0; j < 3; j++) {
			LEDChannels[i][j] = 0;
		}
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
    for (int h = 0;h<NUM_LEDS;h++) {
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
    for (int z = 0; z < NUM_LEDS; z++) SB_SendPacket();
    delayMicroseconds(15);
    digitalWrite(latchpin,HIGH); // latch data into registers
    delayMicroseconds(15);
    digitalWrite(latchpin,LOW);

}

void set_pattern(pattern_t new_pat){

	//change the display
	set_display(new_pat);

	//the last time we've drawn, reset
	draw_time_last = 0;
	trigger_last = 0;

	//do all the set up we need
	clear();
	//init light_guys
	light_guys_index = 0;
	for (unsigned int i = 0; i < NUM_LIGHT_GUYS; i++) {
		light_guys[i].active = false;
		light_guys[i].position = 0;
		light_guys[i].position_last = 0;
		light_guys[i].position_mod = 0.0;
		light_guys[i].hv[0] = (float)random(256) / 256.0f;
		light_guys[i].hv[1] = 1.0f;
		light_guys[i].fbdk_type = MULT;
		light_guys[i].fbdk[0] = 0.98f;
		light_guys[i].fbdk[1] = 0.96f;
		//reset the draw buffer
		for(unsigned int j = 0; j < NUM_LEDS; j++) {
			light_guys[i].draw_buffer[j][0] = 0.0;
			light_guys[i].draw_buffer[j][1] = 0.0;
		}
	}

	hsv[0] = 0.0;
	hsv[1] = 1.0;
	hsv[2] = 0.0;

	switch(new_pat) {
		case MODE_WIPE:
			//on the first go we want to be at the last valid index so we start
			//on the first trigger at 0
			//light_guys_index = (MODE_WIPE_PATTERN_LEN << 1) - 1;
			light_guys_index = MODE_WIPE_PATTERN_LEN - 1;
			break;
		case GATE:
			light_guys[0].active = true;
			//this is a position in a sin function
			light_guys[0].hv[1] = 0.0f;
			break;
		case ECHO:
			light_guys[0].position = 0;
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
			for(uint8_t i = 0; i < ROTATION_GUY_COUNT; i++){
				rotation_pattern_data.guys[i].active = false;
				/*
				rotation_pattern_data.guys[i].position = random(NUM_LEDS);
				rotation_pattern_data.guys[i].position_mod = (float)random(24) / 127.0 + 0.001;
				if(random(2)){
					rotation_pattern_data.guys[i].position_mod = 
						-rotation_pattern_data.guys[i].position_mod;
				}
				rotation_pattern_data.guys[i].hue = (float)random(256) / 256.0f;
				rotation_pattern_data.guys[i].length = 1;
				*/
			}
			break;
		default:
			break;
	}


#if 0

	//clear what has been drawn
	clear();

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
		case WIPE:
			wipe_pattern_data.active = false;
			wipe_pattern_data.last_time = 0;
			wipe_pattern_data.position = 0;
			wipe_pattern_data.hue = (float)random(256) / 256.0f;
			wipe_pattern_data.start_evolve = 0;
			break;
		default:
			break;
	}
#endif
}

void setup() {

	Serial.begin(9600);          //  setup serial

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
	//pinMode(PATTERN_SEL_GND, OUTPUT);
	//digitalWrite(PATTERN_SEL_GND, LOW);

	//analog input shoud not have a pullup
	pinMode(ANALOG_PULLUP_PIN, INPUT);
	digitalWrite(ANALOG_PULLUP_PIN, LOW);

	//set the analog trigger to be an output and set to zero
	//pinMode(ANALOG_PATTERN_SEL_GND, OUTPUT);
	//digitalWrite(ANALOG_PATTERN_SEL_GND, LOW);

	//set the trigger pin to be an input, with pullup
	pinMode(PATTERN_SEL_PIN, INPUT);
	digitalWrite(PATTERN_SEL_PIN, HIGH);

	//seven seg display
	pinMode(SEVEN_SEG_A, OUTPUT);
	pinMode(SEVEN_SEG_B, OUTPUT);
	pinMode(SEVEN_SEG_C, OUTPUT);
	pinMode(SEVEN_SEG_D, OUTPUT);
	pinMode(SEVEN_SEG_E, OUTPUT);
	pinMode(SEVEN_SEG_F, OUTPUT);
	pinMode(SEVEN_SEG_G, OUTPUT);
	pinMode(SEVEN_SEG_P, OUTPUT);

	digitalWrite(SEVEN_SEG_A, HIGH);
	digitalWrite(SEVEN_SEG_B, HIGH);
	digitalWrite(SEVEN_SEG_C, HIGH);
	digitalWrite(SEVEN_SEG_D, HIGH);
	digitalWrite(SEVEN_SEG_E, HIGH);
	digitalWrite(SEVEN_SEG_F, HIGH);
	digitalWrite(SEVEN_SEG_G, HIGH);
	digitalWrite(SEVEN_SEG_P, HIGH);

	clear();
	delay(10);
	WriteLEDArray();

	//init the pattern
	//set_pattern(SINGLE_GUY);
	//set_pattern(MODE_WIPE);
	//set_pattern(VERT_MIRROR);
	//set_pattern(SWELL);
	//set_pattern(GATE);
	set_pattern(NONE);
}

void set_display(uint8_t val) {
	digitalWrite(SEVEN_SEG_A, HIGH);
	digitalWrite(SEVEN_SEG_B, HIGH);
	digitalWrite(SEVEN_SEG_C, HIGH);
	digitalWrite(SEVEN_SEG_D, HIGH);
	digitalWrite(SEVEN_SEG_E, HIGH);
	digitalWrite(SEVEN_SEG_F, HIGH);
	digitalWrite(SEVEN_SEG_G, HIGH);
	switch(val) {
		case 0:
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_B, LOW);
			digitalWrite(SEVEN_SEG_C, LOW);
			digitalWrite(SEVEN_SEG_D, LOW);
			digitalWrite(SEVEN_SEG_E, LOW);
			digitalWrite(SEVEN_SEG_F, LOW);
			break;
		case 1:
			digitalWrite(SEVEN_SEG_B, LOW);
			digitalWrite(SEVEN_SEG_C, LOW);
			break;
		case 2:
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_B, LOW);
			digitalWrite(SEVEN_SEG_D, LOW);
			digitalWrite(SEVEN_SEG_E, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		case 3:
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_B, LOW);
			digitalWrite(SEVEN_SEG_C, LOW);
			digitalWrite(SEVEN_SEG_D, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		case 4:
			digitalWrite(SEVEN_SEG_B, LOW);
			digitalWrite(SEVEN_SEG_C, LOW);
			digitalWrite(SEVEN_SEG_F, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		case 5:
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_C, LOW);
			digitalWrite(SEVEN_SEG_D, LOW);
			digitalWrite(SEVEN_SEG_F, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		case 6:
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_C, LOW);
			digitalWrite(SEVEN_SEG_D, LOW);
			digitalWrite(SEVEN_SEG_E, LOW);
			digitalWrite(SEVEN_SEG_F, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		case 7:
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_B, LOW);
			digitalWrite(SEVEN_SEG_C, LOW);
			break;
		case 8:
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_B, LOW);
			digitalWrite(SEVEN_SEG_C, LOW);
			digitalWrite(SEVEN_SEG_D, LOW);
			digitalWrite(SEVEN_SEG_E, LOW);
			digitalWrite(SEVEN_SEG_F, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		case 9:
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_B, LOW);
			digitalWrite(SEVEN_SEG_C, LOW);
			digitalWrite(SEVEN_SEG_D, LOW);
			digitalWrite(SEVEN_SEG_F, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		case 10:
			//a
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_B, LOW);
			digitalWrite(SEVEN_SEG_C, LOW);
			digitalWrite(SEVEN_SEG_E, LOW);
			digitalWrite(SEVEN_SEG_F, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		case 11:
			//b
			digitalWrite(SEVEN_SEG_C, LOW);
			digitalWrite(SEVEN_SEG_D, LOW);
			digitalWrite(SEVEN_SEG_E, LOW);
			digitalWrite(SEVEN_SEG_F, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		case 12:
			//c
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_D, LOW);
			digitalWrite(SEVEN_SEG_E, LOW);
			digitalWrite(SEVEN_SEG_F, LOW);
			break;
		case 13:
			//d
			digitalWrite(SEVEN_SEG_B, LOW);
			digitalWrite(SEVEN_SEG_C, LOW);
			digitalWrite(SEVEN_SEG_D, LOW);
			digitalWrite(SEVEN_SEG_E, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		case 14:
			//e
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_D, LOW);
			digitalWrite(SEVEN_SEG_E, LOW);
			digitalWrite(SEVEN_SEG_F, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		case 15:
			//f
			digitalWrite(SEVEN_SEG_A, LOW);
			digitalWrite(SEVEN_SEG_E, LOW);
			digitalWrite(SEVEN_SEG_F, LOW);
			digitalWrite(SEVEN_SEG_G, LOW);
			break;
		default:
			break;
	};
}

void draw_light_guy_fbdk(light_guy_data_t * guy) {
	for(uint8_t j = 0; j < NUM_LEDS; j++) {
		//h and v only
		//guy->draw_buffer[j][0] += guy->fbdk[0];
		if(guy->fbdk_type == MULT)
			guy->draw_buffer[j][0] *= guy->fbdk[0];
		else
			guy->draw_buffer[j][0] += guy->fbdk[0];
		//guy->draw_buffer[j][0] *= 0.98;
		while (guy->draw_buffer[j][0] > 1.0f)
			guy->draw_buffer[j][0] -= 1.0f;

		guy->draw_buffer[j][1] *= guy->fbdk[1];
		if (guy->draw_buffer[j][1] > 1.0f)
			guy->draw_buffer[j][1] = 1.0;

		//set a threshold where the color and hue no longer have effect
		if(guy->draw_buffer[j][1] < 0.001f) {
			guy->draw_buffer[j][1] = 0.0f;
			guy->draw_buffer[j][0] = 0.0f;
		}
	}
}

//pass the guy and its last position
void draw_light_guy(light_guy_data_t * guy, bool do_feedback = true){

	//update per the feedback
	if (do_feedback) {
		draw_light_guy_fbdk(guy);
	}

	//interpolate the new position lighting
	uint8_t p = guy->position;
	float res = guy->position - (float)p;
	if(res == 0.0f) {
		//draw the new guy
		guy->draw_buffer[p][0] = guy->hv[0];
		guy->draw_buffer[p][1] = guy->hv[1];
	} else {
		//find our next draw point
		uint8_t p2 = p + 1;
		if (p2 >= NUM_LEDS)
			p2 = 0;

		if (guy->position_mod >= 0) {
			res = sin(res * 1.57 + 4.71) + 1.0f;
			//hue stays the same
			guy->draw_buffer[p2][0] = guy->hv[0];
			//interpolate value
			guy->draw_buffer[p2][1] = guy->hv[1] * res * res;

			//draw inbetween values that may have been missed
			//TODO isn't correct if we cross zero
			for(uint8_t i = (guy->position_last + 1); i < p2; i++){
				guy->draw_buffer[i][0] = guy->hv[0];
				//interpolate value
				guy->draw_buffer[i][1] = guy->hv[1];
			}
			//TODO erase!

		} else {
			float res_inv = 1.0f - res;
			res_inv = sin(res_inv * 1.57 + 4.71) + 1.0f;
			guy->draw_buffer[p][0] = guy->hv[0];

			//if we're erasing then we want to turn the last guy off
			if (guy->hv[1] == 0.0f) {
				//TODO interpolate erase
				guy->draw_buffer[p][1] = 0.0f;
				//erase the last guy
				guy->draw_buffer[p2][0] = guy->hv[0];
				guy->draw_buffer[p2][1] = 0.0f;
			} else {
				//interpolate value
				guy->draw_buffer[p][1] = guy->hv[1] * res_inv * res_inv;
			}

			//TODO deal with position_last
		}
	}

}

void draw(pattern_t pattern, unsigned long time, bool trig){
	static uint8_t trigger_count = 0;
	uint16_t rgb[3];
	long interval = 1;
	unsigned long time_since_last = time - draw_time_last;
	bool faster = false;

	//we don't draw the first time around
	if (draw_time_last == 0) {
		draw_time_last = time;
		return;
	}

	if(trig){
		//increment the trigger count
		trigger_count++;
		//if we have a last time then we update the interval
		//otherwise, we ignore the trigger
		if (trigger_last != 0) {
			interval = (time - trigger_last);
		} else {
			trig = false;
		}
		trigger_last = time;
		//just in case, but this shouldn't ever happen
		if (interval <= 0)
			return;
	}


	switch (pattern) {
		case SINGLE_GUY:
		case MULT_GUYS:
			clear();
			//on trig, reset position and color
			if (trig && (trigger_count % 2) == 0) {
				if (pattern == MULT_GUYS)
					light_guys_index = (light_guys_index + 1) % NUM_LIGHT_GUYS;
				else
					light_guys_index = 0;
				light_guys[light_guys_index].active = true;
				light_guys[light_guys_index].position = random(NUM_LEDS);
				light_guys[light_guys_index].position_last
					= light_guys[light_guys_index].position;
				//position mod is per millisecond
				light_guys[light_guys_index].position_mod = (float)(NUM_LEDS) / (float)interval;

				//usually we want to go half as fast, which means we need to move
				//twice as far in the interval, every once in a while we let it go at normal rate
				if (random(16) > 1) {
					light_guys[light_guys_index].position_mod *= 0.5;
				} 
				//light_guys[light_guys_index].position_mod = 0.05;
				light_guys[light_guys_index].hv[0] = (float)random(256) / 256.0f;
				light_guys[light_guys_index].hv[1] = 1.0;
				if (random(4) > 1) {
					light_guys[light_guys_index].fbdk_type = ADD;
					light_guys[light_guys_index].fbdk[0] = (float)random(100) / 10000.0f;
				} else {
					light_guys[light_guys_index].fbdk_type = MULT;
					light_guys[light_guys_index].fbdk[0] = 0.8f + (float)random(1000) / 10000.0f;
				}
				light_guys[light_guys_index].fbdk[1] = 0.9f + (float)random(81) / 1024.0f;
				//light_guys[light_guys_index].fbdk[0] = (float)random(10) / 10000.0f;
				//light_guys[light_guys_index].fbdk[1] = 0.9f + (float)random(81) / 1024.0f;
				if (random(12) > 8) {
					light_guys[light_guys_index].position_mod = 
						-light_guys[light_guys_index].position_mod;
				}
			}


			//for now just do light guy
			for(unsigned int i = 0; i < NUM_LIGHT_GUYS; i++) {
				if(!light_guys[i].active)
					continue;
				//increment the position
				light_guys[i].position_last = light_guys[i].position;
				light_guys[i].position += ((float)time_since_last * light_guys[i].position_mod);
				//light_guys[i].position += light_guys[i].position_mod;
				//stay in range
				while (light_guys[i].position >= NUM_LEDS)
					light_guys[i].position -= NUM_LEDS;
				while (light_guys[i].position < 0)
					light_guys[i].position += NUM_LEDS;

				draw_light_guy(&light_guys[i]);
			}

			for(uint8_t i = 0; i < NUM_LEDS; i++){
				hsv[1] = 1.0f;
				for(unsigned int j = 0; j < NUM_LIGHT_GUYS; j++) {
					hsv[0] = light_guys[j].draw_buffer[i][0];
					//we want the fade to be smooth, 
					//we use the v value as the point along a sin
					hsv[2] = sin(light_guys[j].draw_buffer[i][1] * 1.57 + 4.71) + 1.0f;
					hsv2rgb(hsv, rgb);
					for(uint8_t k = 0; k < 3; k++) {
						LEDChannels[i][k] += rgb[k];
						if (LEDChannels[i][k] > 0x3ff)
							LEDChannels[i][k] = 0x3ff;
					}
				}

			}
			break;
		case MODE_WIPE:
			if (trig) {
				//increment our index
				light_guys_index = (light_guys_index + 1) % MODE_WIPE_PATTERN_LEN;

				light_guys[0].active = true;

				//update per mode [light_guys_index]
				//the 0th time we want it to go around in one beat, the 1st we draw
				//half the amount so we divide the position_mod by 2.. ..
				if ( light_guys_index < HALF_MODE_WIPE_LEN) {
					light_guys[0].position_mod = (float)NUM_LEDS / 
						(float)(interval * (light_guys_index + 1));
				} else {
					light_guys[0].position_mod = (float)NUM_LEDS / 
						(float)(interval * (MODE_WIPE_PATTERN_LEN - light_guys_index));
				}

				if ((light_guys_index % 2) == 0) {
					//drawing always starts at zero
					light_guys[0].position = 0;
				} else {
					//erasing starts at mode_wipe_ends - 1
					light_guys[0].position = mode_wipe_ends[light_guys_index] - 1;
					//we decrement position from the wipe_end - 1
					light_guys[0].position_mod = -light_guys[0].position_mod;
				}
				light_guys[0].position_last = light_guys[0].position;

				//every other time we erase, we don't care about hue
				if (light_guys_index % 2 == 0) {
					//figure out the correct hue increment
					light_guys[0].hv[0] += 0.111111;
					while(light_guys[0].hv[0] >= 1.0)
						light_guys[0].hv[0] -= 1.0;
					light_guys[0].hv[1] = 1.0;
				} else {
					light_guys[0].hv[1] = 0.0;
				}

				//XXX figure out this:
				light_guys[0].fbdk_type = ADD;
				light_guys[0].fbdk[0] = 0.005;
				light_guys[0].fbdk[1] = 1.0;

			}

			//if the guy isn't active then we break
			if (!light_guys[0].active)
				break;

			//stay in bounds, we wrap in pattern
			if (light_guys[0].position
					> (mode_wipe_ends[light_guys_index % MODE_WIPE_PATTERN_LEN] - 1)){
				light_guys[0].active = false;
			}

			//make sure we don't loop around
			if (light_guys[0].position > (NUM_LEDS - 1)) {
				light_guys[0].position = NUM_LEDS - 1;
			} else if (light_guys[0].position < 0.0f) {
				light_guys[0].position = 0.0f;
			}

			//every other time we erase
			if (light_guys_index % 2 == 0) {
				draw_light_guy(&light_guys[0]);
			} else {
				draw_light_guy(&light_guys[0], false);
				////XXX get inbetween guys
				//light_guys[0].draw_buffer[(uint8_t)light_guys[0].position % NUM_LEDS][0] = 0.0;
				//light_guys[0].draw_buffer[(uint8_t)light_guys[0].position % NUM_LEDS][1] = 0.0;
			}

			//update our position
			light_guys[0].position_last = light_guys[0].position;
			light_guys[0].position += ((float)time_since_last * light_guys[0].position_mod);

			//mirror, only if we're not at the first position in the pattern
			if ((light_guys_index != 0) && (light_guys_index != (MODE_WIPE_PATTERN_LEN - 1))) {
				const uint8_t mirror_len = mode_wipe_ends[light_guys_index % MODE_WIPE_PATTERN_LEN];
				uint8_t start_index = mirror_len;
				while(start_index < NUM_LEDS) {
					for(uint8_t i = 0; i < mirror_len; i++){
						light_guys[0].draw_buffer[i + start_index][0] =
							light_guys[0].draw_buffer[i][0];
						light_guys[0].draw_buffer[i + start_index][1] =
							light_guys[0].draw_buffer[i][1];
					}
					start_index += mirror_len;
				}
			}

			//actually update the leds
			for(uint8_t i = 0; i < NUM_LEDS; i++){
				hsv[1] = 1.0f;
				hsv[0] = light_guys[0].draw_buffer[i][0];
				//we want the fade to be smooth, 
				//we use the v value as the point along a sin
				hsv[2] = sin(light_guys[0].draw_buffer[i][1] * 1.57 + 4.71) + 1.0f;
				hsv2rgb(hsv, rgb);
				for(uint8_t k = 0; k < 3; k++) {
					//ASSIGNMENT, not addition!
					LEDChannels[i][k] = rgb[k];
					if (LEDChannels[i][k] > 0x3ff)
						LEDChannels[i][k] = 0x3ff;
				}
			}
			break;
		case VERT_MIRROR:
			if (trig) {
				light_guys[0].active = true;
				light_guys[0].position_mod = 0.5f * (float)HALF_NUM_LEDS / 
					(float)(interval);
				light_guys[0].position = 0;
				//every other time we change the direction
				if (trigger_count % 2) {
					light_guys[0].position = HALF_NUM_LEDS - 1;
					light_guys[0].position_mod = -light_guys[0].position_mod;
				}
				light_guys[0].position_last = light_guys[0].position;

				//figure out the correct hue increment
				light_guys[0].hv[0] += 0.211111;
				while(light_guys[0].hv[0] >= 1.0)
					light_guys[0].hv[0] -= 1.0;
				light_guys[0].hv[1] = 1.0;

				//XXX figure out this:
				light_guys[0].fbdk_type = ADD;
				light_guys[0].fbdk[0] = 0.001;
				light_guys[0].fbdk[1] = 0.96;
			}

			if (light_guys[0].active){
				//draw then increment position
				draw_light_guy(&light_guys[0], true);
				light_guys[0].position_last = light_guys[0].position;
				light_guys[0].position += ((float)time_since_last * light_guys[0].position_mod);

				if (light_guys[0].position < 0) {
					light_guys[0].position = 0;
					light_guys[0].active = false;
				} else if (light_guys[0].position > HALF_NUM_LEDS - 1) {
					light_guys[0].position = HALF_NUM_LEDS - 1;
					light_guys[0].active = false;
				}
			} else {
				//if it is not active then just do the feedback
				draw_light_guy_fbdk(&light_guys[0]);
			}

			//mirror
			for(uint8_t i = 0; i < HALF_NUM_LEDS; i++){
				light_guys[0].draw_buffer[NUM_LEDS - 1 - i][0] =
					light_guys[0].draw_buffer[i][0];
				light_guys[0].draw_buffer[NUM_LEDS - 1 - i][1] =
					light_guys[0].draw_buffer[i][1];
			}

			//actually update the leds
			for(uint8_t i = 0; i < NUM_LEDS; i++){
				hsv[1] = 1.0f;
				hsv[0] = light_guys[0].draw_buffer[i][0];
				//we want the fade to be smooth, 
				//we use the v value as the point along a sin
				hsv[2] = sin(light_guys[0].draw_buffer[i][1] * 1.57 + 4.71) + 1.0f;
				hsv2rgb(hsv, rgb);
				for(uint8_t k = 0; k < 3; k++) {
					//ASSIGNMENT, not addition!
					LEDChannels[i][k] = rgb[k];
					if (LEDChannels[i][k] > 0x3ff)
						LEDChannels[i][k] = 0x3ff;
				}
			}

			break;
		case SWELL:
			{
				if (trig) {
					light_guys[0].active = true;
					light_guys[0].position = 0;
					light_guys[0].position_last = light_guys[0].position;

					//figure out the correct hue increment
					light_guys[0].hv[0] += 0.211111;
					while(light_guys[0].hv[0] >= 1.0)
						light_guys[0].hv[0] -= 1.0;
					//this is not actually the hv value, we use it to go from 0 to 1 over an amount of time
					light_guys[0].hv[1] = 0.0;
				}
				if(!light_guys[0].active)
					break;

				//go from zero to one in SWELL_TIME ms
				if (time_since_last > 0)
					light_guys[0].hv[1] += time_since_last / SWELL_TIME;
				if (light_guys[0].hv[1] >= 1.0f)
					light_guys[0].active = false;

				hsv[0] = light_guys[0].hv[0];
				hsv[1] = 1.0f;
				hsv[2] = sin(light_guys[0].hv[1] * 3.14);
				hsv[2] *= hsv[2];

				hsv2rgb(hsv, rgb);

				for(uint8_t i = 0; i < NUM_LEDS; i++){
					for(uint8_t k = 0; k < 3; k++) {
						//ASSIGNMENT, not addition!
						LEDChannels[i][k] = rgb[k];
						if (LEDChannels[i][k] > 0x3ff)
							LEDChannels[i][k] = 0x3ff;
					}
				}
			}
			break;
		case GATE:
			if (trig) {
				light_guys[0].active = true;
				light_guys[0].position = 0;
				light_guys[0].position_last = light_guys[0].position;

				//figure out the correct hue increment
				light_guys[0].hv[0] += 0.211111;
				while(light_guys[0].hv[0] >= 1.0)
					light_guys[0].hv[0] -= 1.0;

				light_guys[0].fbdk[0] = 0.0008;
				light_guys[0].fbdk[1] = 0.99;
				light_guys[0].fbdk_type = ADD;

				//this is not actually the hv value, we use it to go from 0 to 1 over an amount of time
				light_guys[0].hv[1] = 0.0;
			}

			hsv[1] = 1.0f;
			if(light_guys[0].hv[1] <= 1.0f) {

				//store the hue and value for later feedback
				hsv[0] = light_guys[0].draw_buffer[0][0] = light_guys[0].hv[0];
				//fade in
				hsv[2] = sin(light_guys[0].hv[1] * 1.57 + 4.71) + 1.0f;
				hsv[2] *= hsv[2];
				light_guys[0].draw_buffer[0][1] = hsv[2];

				hsv2rgb(hsv, rgb);

				for(uint8_t i = 0; i < NUM_LEDS; i++){
					for(uint8_t k = 0; k < 3; k++) {
						//ASSIGNMENT, not addition!
						LEDChannels[i][k] = rgb[k];
						if (LEDChannels[i][k] > 0x3ff)
							LEDChannels[i][k] = 0x3ff;
					}
				}
			} else {
				draw_light_guy_fbdk(&light_guys[0]);

				hsv[0] = light_guys[0].draw_buffer[0][0];
				hsv[2] = light_guys[0].draw_buffer[0][1];

				hsv2rgb(hsv, rgb);

				for(uint8_t i = 0; i < NUM_LEDS; i++){
					for(uint8_t k = 0; k < 3; k++) {
						//ASSIGNMENT, not addition!
						LEDChannels[i][k] = rgb[k];
						if (LEDChannels[i][k] > 0x3ff)
							LEDChannels[i][k] = 0x3ff;
					}
				}
			}

			light_guys[0].hv[1] += time_since_last / SWELL_TIME;

			break;
		case ECHO:
			if(trig && (trigger_count % 2) == 0) {
				//set the guy to active
				light_guys[0].active = true;

				//index says where we start drawing..
				light_guys_index = (light_guys_index + 1) % NUM_LEDS;
				//position says the side that it is on, even is on one side, odd is on the other
				light_guys[0].position = 0;

				light_guys[0].hv[0] = (float)random(256) / 256.0f;

				light_guys[0].fbdk[0] = 0.01;
				light_guys[0].fbdk[1] = 0.8;
				light_guys[0].fbdk_type = ADD;

				//we want NUM_LEDS echos per beat, which means we want to position to count to NUM_LEDS each beat
				light_guys[0].position_mod = (float)NUM_ECHOS / (float)(2 * interval);
			}

			if(light_guys[0].active) {
				uint8_t draw_start = 7 * light_guys_index;
				float hue = light_guys[0].hv[0];
				float val = (float)NUM_ECHOS - light_guys[0].position;
				if (val > 1.0f)
					val = 1.0f;
				val = sin(val * 1.57 + 1.57);
				val = sin(val * 1.57 + 1.57);
				//on odd we start from draw_start + HALF_NUM_LEDS
				if ((uint8_t)light_guys[0].position % 2) {
					draw_start += HALF_NUM_LEDS;
					hue += 0.5f;
					if (hue >= 1.0f)
						hue -= 1.0f;
				}

				//fill 1/2 the draw buffer, erase the other half
				for (uint8_t i = 0; i < HALF_NUM_LEDS; i++) {
					light_guys[0].draw_buffer[(i + draw_start) % NUM_LEDS][0] = hue;
					light_guys[0].draw_buffer[(i + draw_start) % NUM_LEDS][1] = val;

					//light_guys[0].draw_buffer[(i + draw_start + HALF_NUM_LEDS) % NUM_LEDS][1] = 0.0;
				}
			}

			//do feedback
			draw_light_guy_fbdk(&light_guys[0]);

			//actually update the leds
			for(uint8_t i = 0; i < NUM_LEDS; i++){
				hsv[1] = 1.0f;
				hsv[0] = light_guys[0].draw_buffer[i][0];
				//we want the fade to be smooth, 
				//we use the v value as the point along a sin
				hsv[2] = sin(light_guys[0].draw_buffer[i][1] * 1.57 + 4.71) + 1.0f;
				hsv2rgb(hsv, rgb);
				for(uint8_t k = 0; k < 3; k++) {
					//ASSIGNMENT, not addition!
					LEDChannels[i][k] = rgb[k];
					if (LEDChannels[i][k] > 0x3ff)
						LEDChannels[i][k] = 0x3ff;
				}
			}

			//update "position"
			light_guys[0].position += light_guys[0].position_mod * time_since_last;
			if(light_guys[0].position >= NUM_ECHOS)
				light_guys[0].active = false;

			break;
		case QUAD_ECHO:
			clear();
			if(trig){
				if(interval >= 700)
					interval = interval >> 1;
				if(interval > (ECHO_PAT_ON_LEN + 20) && interval < 700){
					uint8_t span = 1;
					float hue = (float)random(256) / 256.0f;
					//every once in a while draw to the whole ring..
					if(random(255) > 200)
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
				unsigned long interval = time - rotation_pattern_data.last_time;
				if(rotation_pattern_data.last_time != 0 &&
						interval > 100 &&
						random(10) > 6){
					rotation_guy_t * guy = &rotation_pattern_data.guys[rotation_pattern_data.index];
					//increment for next time
					rotation_pattern_data.index = (rotation_pattern_data.index + 1) % ROTATION_GUY_COUNT;
					guy->active = true;
					if(random(255) > 170)
						guy->length = random(3) + 1;
					else
						guy->length = 1;
					guy->position = random(NUM_LEDS);
					guy->position_mod = (float)NUM_LEDS / (float)(interval);
					guy->hue = (float)random(256) / 256.0f;
				}
				//very seldomly, change direction
				if(random(255) > 230){
					for(uint8_t i = 0; i < ROTATION_GUY_COUNT; i++){
						rotation_pattern_data.guys[i].position_mod = 
							-rotation_pattern_data.guys[i].position_mod;
					}
				}
				rotation_pattern_data.last_time = time;
				faster = true;
			} else if(rotation_pattern_data.last_time + ROTATION_ACCEL_TIME > time){
				faster = true;
			}
			for(uint8_t i = 0; i < ROTATION_GUY_COUNT; i++){
				rotation_guy_t * guy = &rotation_pattern_data.guys[i];
				if(guy->active){
					/*
					//on a trig, reverse
					if(trig)
					guy->position_mod = -guy->position_mod;
					 */
					if(faster)
						guy->position += (4 * guy->position_mod);
					else
						guy->position += guy->position_mod;
					//keep in range
					while(guy->position >= NUM_LEDS)
						guy->position -= NUM_LEDS;
					while(guy->position < 0.0f)
						guy->position += NUM_LEDS;
					hsv[0] = guy->hue;
					hsv[1] = 1.0;
					hsv[2] = 1.0;
					hsv2rgb(hsv, rgb);
					//just for now, draw over whatever is there
					for(uint8_t j = 0; j < guy->length; j++){
						uint8_t idx = (uint8_t)(j + guy->position) % NUM_LEDS;
						for(uint8_t k = 0; k < 3; k++)
							LEDChannels[idx][k] = rgb[k];
					}
				}
			}
			break;
		case NONE:
		default:
			clear();
			break;
	}

#if 0
	switch(pattern){
		case FADE:
			hsv[1] = 1.0;
			//fade in on trig
			if(trig){
				hsv[0] = (float)random(256) / 256.0f;
				fade_pattern_data.fade_level = 0.01;
				fade_pattern_data.start_evolve = 0;

			} else if(fade_pattern_data.start_evolve == 0 && 
					fade_pattern_data.fade_level > 0.0f){
				fade_pattern_data.fade_level = (fade_pattern_data.fade_level + 0.003);

				if(hsv[0] >= 1.0f)
					hsv[0] -= 1.0f;

				if(fade_pattern_data.fade_level >= 1.0f){
					fade_pattern_data.fade_level = 1.0f;
					//after FADE_EVOLVE_DELAY, evolve
					fade_pattern_data.start_evolve = time + FADE_EVOLVE_DELAY;
				}
			} else if(fade_pattern_data.start_evolve && 
					fade_pattern_data.start_evolve <= time){
				//increment the color slowly over time
				hsv[0] += 0.0001;
				if(hsv[0] >= 1.0f)
					hsv[0] -= 1.0f;
				//reduce the brightness to half during the evolving colors
				if(fade_pattern_data.fade_level > 0.5)
					fade_pattern_data.fade_level -= 0.001;
			}

			hsv[2] = sin(fade_pattern_data.fade_level * 1.57 + 4.71) + 1.0f;
			hsv2rgb(hsv, rgb);

			for(uint8_t i = 0; i < NUM_LEDS; i++){
				for(uint8_t j = 0; j < 3; j++)
					LEDChannels[i][j] = rgb[j];
			}
			break;
		case WIPE:
			if(trig){
				if(wipe_pattern_data.last_time != 0){
					unsigned long interval = time - wipe_pattern_data.last_time;
					if(interval > 20){
						wipe_pattern_data.position = 0;
						wipe_pattern_data.wipe_forward = !wipe_pattern_data.wipe_forward;
						wipe_pattern_data.position_mod = (float)NUM_LEDS / (float)(interval >> 1);
						wipe_pattern_data.active = true;
						if(wipe_pattern_data.wipe_forward)
							wipe_pattern_data.hue += 0.2511;
						else
							wipe_pattern_data.hue += 0.501;
						while(wipe_pattern_data.hue >= 1.0)
							wipe_pattern_data.hue -= 1.0;
						wipe_pattern_data.start_evolve = 0;
					}
				}
				wipe_pattern_data.last_time = time;
			}
			if(wipe_pattern_data.active){
				//if we're in range, draw
				if(wipe_pattern_data.position < NUM_LEDS){
					int8_t idx;
					hsv[0] = wipe_pattern_data.hue;
					hsv[1] = 1.0;
					hsv[2] = 1.0;
					hsv2rgb(hsv, rgb);
					if(wipe_pattern_data.wipe_forward)
						idx = (int8_t)wipe_pattern_data.position;
					else
						idx = NUM_LEDS - (int8_t)wipe_pattern_data.position - 1;

					if(idx < 0)
						idx = 0;
					else if(idx >= NUM_LEDS)
						idx = NUM_LEDS - 1;

					for(uint8_t i = 0; i < 3; i++)
						LEDChannels[idx][i] = rgb[i];
					//increment position
					wipe_pattern_data.position += wipe_pattern_data.position_mod;
				} else {
					wipe_pattern_data.active = false;
					wipe_pattern_data.start_evolve = time + WIPE_EVOLVE_DELAY;
					//now used as a level
					wipe_pattern_data.position = 1.0;
				}
			} else if(wipe_pattern_data.start_evolve) {
				if(time >= wipe_pattern_data.start_evolve){
					if(time % 10 == 0){
						//use position as level
						wipe_pattern_data.position -= 0.001;
						if(wipe_pattern_data.position < 0.0)
							wipe_pattern_data.position = 0;
						if(wipe_pattern_data.position > 1.0)
							wipe_pattern_data.position = 1.0;

						hsv[0] = wipe_pattern_data.hue;
						hsv[1] = 1.0;
						hsv[2] = wipe_pattern_data.position;
						hsv2rgb(hsv, rgb);
						for(uint8_t i = 0; i < NUM_LEDS; i++){
							for(uint8_t j = 0; j < 3; j++)
								LEDChannels[i][j] = rgb[j];
						}
					}
				}
			}
			break;
		default:
			break;
	}
#endif

	WriteLEDArray();
	//store the time
	draw_time_last = time;
}

void loop() {
	static pattern_t led_pattern = NONE;
	static unsigned long trigger_next = 0;
	static unsigned long trigger_last = 0;
	unsigned long time = millis();
	uint16_t analog_val = analogRead(ANALOG_TRIGGER_PIN);
	bool trig = false;

	//check for a trigger
	if(digitalRead(PATTERN_SEL_PIN))
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
			down = true;
			////XXX temp! just using the button for trigger now
			led_pattern = (pattern_t)((led_pattern + 1) % PATTERN_T_END);
			set_pattern(led_pattern);

			//trig = true;
			//digitalWrite(SEVEN_SEG_P, HIGH);
		}
	}

	//if we're above the threshold and the time is greater than
	//the time threshold
	if((analog_val >= ANALOG_THRESH_POS || analog_val <= ANALOG_THRESH_NEG) && time >= trigger_next ){
		Serial.println(analog_val);
		trig = true;
		//set the minimum time for the next trigger
		trigger_next = time + TRIGGER_MIN_INTERVAL;
		trigger_last = time;
		digitalWrite(SEVEN_SEG_P, LOW);
	} else if(trigger_last + TRIG_DISPLAY_TIME < time){
		digitalWrite(SEVEN_SEG_P, HIGH);
	}

	//draw on a trig, or every 2 milliseconds
	if(trig || (time % 2 == 0)){
		draw(led_pattern, time, trig);
	}
}
