shader_type spatial;
render_mode cull_disabled;
uniform sampler2D clothing : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float simulation_tick;
varying flat float wardrobe;

void vertex(){
	float beat=sin(simulation_tick*1.75+INSTANCE_CUSTOM.r*TAU)*INSTANCE_CUSTOM.g;
	float arm=UV2.x*2.-1.;
	float leg=UV2.y*2.-1.;
	float stride=clamp((.91-VERTEX.y)/.78,0.,1.);
	float swing=clamp((1.49-VERTEX.y)/.66,0.,1.);
	VERTEX.z+=beat*(leg*stride*.30-arm*swing*.20);
	VERTEX.y+=max(0.,-leg*beat)*stride*.064+abs(beat)*.017;
	float seated=INSTANCE_CUSTOM.b;
	VERTEX.z+=seated*.52*stride;
	VERTEX.y-=seated*(.41-.20*stride);
	wardrobe=INSTANCE_CUSTOM.r;
}
void fragment(){
	vec4 texel=texture(clothing,UV);
	ALPHA=texel.a;
	ALPHA_SCISSOR_THRESHOLD=.39;
	vec3 tint=mix(vec3(.89,.94,1.04),vec3(1.055,1.005,.93),wardrobe);
	vec3 cloth=texel.rgb;
	if (UV.x<.5 && UV.y<.5) {
		// Dye coloured fabric while preserving the original knit and folds.
		float dye=smoothstep(.012,.065,min(cloth.b-cloth.g,cloth.r-cloth.g));
		vec3 fabric=mix(vec3(.17,.23,.26),vec3(.44,.33,.26),wardrobe);
		float light=dot(cloth,vec3(.26,.56,.18));
		cloth=mix(cloth,fabric*light*3.7,dye)*tint;
	}
	ALBEDO=cloth;
	ROUGHNESS=.84;
	SPECULAR=.22;
}
