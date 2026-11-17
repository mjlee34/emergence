shader_type spatial;
render_mode blend_add, unshaded, fog_disabled, cull_disabled, shadows_disabled, depth_draw_never;
uniform float fall_phase = 0.;
uniform float intensity = 0.;
uniform vec2 wind;
uniform vec3 center;
uniform vec2 span = vec2(45.,25.);
varying float opacity;
void vertex() {
	// A wrapped, world-anchored volume follows the camera without dragging drops along with it.
	vec3 random=INSTANCE_CUSTOM.rgb;
	float cycle=fract(random.y-fall_phase);
	vec2 drift=(1.-cycle)*span.y*wind*.16;
	vec2 xz=center.xz+mod(random.xz*span.x+drift-center.xz+span.x*.5,span.x)-span.x*.5;
	vec3 base=vec3(xz.x,center.y+cycle*span.y-span.y*.5,xz.y);
	float distance_to_eye=distance(base,CAMERA_POSITION_WORLD);
	float width=clamp(distance_to_eye*.0010,.020,.22);
	float streak=clamp(distance_to_eye*.015,.43,2.8);
	vec3 drop=normalize(vec3(wind.x*.16,-1.,wind.y*.16));
	vec3 right=normalize(cross(drop,normalize(CAMERA_POSITION_WORLD-base))+vec3(.000001));
	VERTEX=base+right*VERTEX.x*width-drop*VERTEX.y*streak;
	opacity=(.22+.38*INSTANCE_CUSTOM.a)*smoothstep(0.,.08,cycle)*(1.-smoothstep(.94,1.,cycle));
}
void fragment() {
	float edge=clamp(1.-abs(UV.x*2.-1.),0.,1.);
	float tail=sin(clamp(UV.y,0.,1.)*PI);
	ALBEDO=vec3(.62,.73,.82);
	ALPHA=edge*tail*opacity*smoothstep(.009,.12,intensity);
}
