shader_type spatial;
render_mode cull_disabled;
uniform sampler2D crown : source_color, filter_linear_mipmap, repeat_disable;
uniform float height = 8.0;
varying float tier;
varying float variant;
varying vec3 shade;
void vertex(){
	float scale=length(MODEL_MATRIX[0].xyz);
	vec3 center=(MODEL_MATRIX*vec4(0.,height*.5,0.,1.)).xyz;
	vec3 eye=PROJECTION_MATRIX[3][3]>.5 ? INV_VIEW_MATRIX[2].xyz : normalize(INV_VIEW_MATRIX[3].xyz-center);
	float degrees_up=degrees(asin(clamp(eye.y,-1.,1.)));
	tier=clamp(degrees_up<38. ? (degrees_up-12.)/26. : 1.+(degrees_up-38.)/32.,0.,2.);
	variant=step(.5,INSTANCE_CUSTOM.r);
	shade=COLOR.rgb;
	MODELVIEW_MATRIX=mat4(vec4(scale,0.,0.,0.),vec4(0.,scale,0.,0.),vec4(0.,0.,scale,0.),VIEW_MATRIX*vec4(center,1.));
}
void fragment(){
	vec2 uv=vec2(variant+UV.x,UV.y)/vec2(2.,3.);
	vec4 a=texture(crown,uv+vec2(0.,floor(tier)/3.));
	vec4 b=texture(crown,uv+vec2(0.,min(2.,floor(tier)+1.)/3.));
	float t=smoothstep(.15,.85,fract(tier));
	ALPHA=mix(a.a,b.a,t);
	ALPHA_SCISSOR_THRESHOLD=.34;
	ALBEDO=mix(a.rgb,b.rgb,t)*shade*1.18;
	NORMAL=normalize(mat3(VIEW_MATRIX)*vec3(0.,1.,0.)+VIEW*.18);
	ROUGHNESS=.96;
	SPECULAR=.12;
}
