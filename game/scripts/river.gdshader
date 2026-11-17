shader_type spatial;
render_mode cull_disabled;
varying vec2 location;
void vertex(){ location=VERTEX.xz; }
void fragment(){
	float x=location.x, z=location.y;
	float center=94.0+29.0*sin(z*.021+.4)-.18*z;
	float bank=abs(x-center);
	float sparkle=sin(z*1.7+x*.2+sin(x*.46+z*.13)*1.7+TIME*.9);
	float fleck=smoothstep(.94,.997,sparkle)*smoothstep(.58,.96,sin(x*.75+z*.31+sin(z*.4)));
	vec3 deep=vec3(.047,.258,.29);
	vec3 shallows=vec3(.23,.50,.46);
	ALBEDO=mix(deep,shallows,smoothstep(8.,22.,bank)) + vec3(.22,.27,.22)*fleck*.56;
	ROUGHNESS=.44;
	SPECULAR=.32;
}
