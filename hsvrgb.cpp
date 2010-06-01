#include "hsvrgb.h"

#define SCALE 256.0f

//http://en.wikipedia.org/wiki/HSL_and_HSV#Conversion_from_HSV_to_RGB
//using h between 0 and 1, not 0 and 360.
void hsv2rgb(float hsv[3], uint16_t (&rgb)[3]){
	float p, q, t, h_6, f, v;
	uint8_t h_i;
	//clamp
	for (unsigned int i = 0; i < 3; i++) {
		if (hsv[i] > 1.0f)
			hsv[i] = 1.0f;
		else if (hsv[i] < 0.0f)
			hsv[i] = 0.0f;
	}

	h_6 = hsv[0] * 6;
	h_i = (uint8_t)h_6 % 6;
	f = h_6 - (uint8_t)h_6;

	v = hsv[2];
	p = v * (1 - hsv[1]);
	q = v * (1 - f * hsv[1]);
	t = v * (1 - (1 - f) * hsv[1]);

	switch(h_i){
		case 0:
			rgb[0] = v * SCALE;
			rgb[1] = t * SCALE;
			rgb[2] = p * SCALE;
			break;
		case 1:
			rgb[0] = q * SCALE;
			rgb[1] = v * SCALE;
			rgb[2] = p * SCALE;
			break;
		case 2:
			rgb[0] = p * SCALE;
			rgb[1] = v * SCALE;
			rgb[2] = t * SCALE;
			break;
		case 3:
			rgb[0] = p * SCALE;
			rgb[1] = q * SCALE;
			rgb[2] = v * SCALE;
			break;
		case 4:
			rgb[0] = t * SCALE;
			rgb[1] = p * SCALE;
			rgb[2] = v * SCALE;
			break;
		case 5:
		default:
			rgb[0] = v * SCALE;
			rgb[1] = p * SCALE;
			rgb[2] = q * SCALE;
			break;
	};
}
