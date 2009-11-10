//modified from http://easyrgb.com/index.php?X=MATH&H=19#text19
#include "hslrgb.h"

//hans

float hue2rgb(float vH, float v1, float v2){
  if ( vH < 0 ) vH += 1.;
  if ( vH > 1. ) vH -= 1.;
  if ( vH < 1./6. ) return ( v1 + ( v2 - v1 ) * 6. * vH );
  if ( vH < 1./2. ) return ( v2 );
  if ( vH < 2./3. ) return ( v1 + ( v2 - v1 ) * ( ( 2. / 3. ) - vH ) * 6. );
  else return ( v1 );
}

#define SCALE 1024.0f

void hsl2rgb(float hsl[3], uint16_t (&rgb)[3]){
	
	for(uint8_t i = 0; i < 3; i++){
		if(hsl[i] > 1.0f)
			hsl[i] = 1.0f;
	}

	float hue=hsl[0]; // 0-1.0
	float saturation=hsl[1]; // 0-1.0
	float level=hsl[2]; // 0-1.0


	if ( saturation <= 0.01 ){ // HSL from 0 to 1
		rgb[0] = (uint16_t)(level * SCALE); // RGB results from 0 to SCALE
		rgb[1] = (uint16_t)(level * SCALE);
		rgb[2] = (uint16_t)(level * SCALE);
	}
	else {
		float vred=0.0f;
		float vblue=0.0f;
		float v1=0.0f;
		float v2=0.0f;
		if ( level < 0.5 ) v2 = level * ( 1. + saturation );
		else v2 = ( level + saturation ) - ( saturation * level );
		v1 = 2. * level - v2;
		vred = hue + ( 1./3. );
		vblue = hue - ( 1./3. );
		rgb[0] = SCALE * hue2rgb( vred, v1, v2);
		rgb[1] = SCALE * hue2rgb( hue, v1, v2);
		rgb[2] = SCALE * hue2rgb( vblue, v1, v2 ); 
	}

	for(uint8_t i = 0; i < 3; i++)
		rgb[i] = rgb[i] & 0x3ff;
}

