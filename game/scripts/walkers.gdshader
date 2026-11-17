shader_type spatial;
uniform float simulation_tick;
varying vec4 tint;
void vertex(){
	tint=COLOR;
	float beat=sin(simulation_tick*1.75+INSTANCE_CUSTOM.r*6.283)*INSTANCE_CUSTOM.g;
	float leg=clamp((.81-VERTEX.y)/.6,0.0,1.0);
	float arm=smoothstep(.16,.23,abs(VERTEX.x))*clamp((1.44-VERTEX.y)/.48,0.0,1.0);
	VERTEX.z+=sign(VERTEX.x)*beat*(leg*.24-arm*.16);
	VERTEX.y+=abs(beat)*.026;
}
void fragment(){ALBEDO=tint.rgb;ROUGHNESS=.86;}
