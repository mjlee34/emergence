shader_type spatial;
uniform sampler2D road : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D walk : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D slate : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// RG stores tangent-space XY, B stores the measured roughness.
uniform sampler2D road_surface : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D walk_surface : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_surface : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D slate_surface : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_surface : filter_linear_mipmap_anisotropic, repeat_enable;
instance uniform float occupancy = 0.0;
uniform float night = 0.0;
varying vec3 local;
varying flat vec2 building_key;
void vertex(){ local=VERTEX; building_key=floor(MODEL_MATRIX[3].xz); }
float hash(vec2 p){ return fract(sin(dot(p,vec2(53.315,18.713)))*8175.15); }
void fragment(){
	int kind=int(UV2.x+.5);
	vec3 base=COLOR.rgb;
	vec3 detail=vec3(.5,.5,.87);
	float spec=.28;
	if(kind==1){
		vec2 at=UV/6.7;
		base=texture(road,at).rgb*(.78+.48*COLOR.r);
		detail=texture(road_surface,at).rgb;
	}else if(kind==2){
		vec2 at=UV/2.6;
		base=texture(walk,at).rgb*(.63+.65*COLOR.r);
		detail=texture(walk_surface,at).rgb;
	}else if(kind==3){
		vec2 at=UV/1.8;
		base=texture(brick,at).rgb*(.45+COLOR.rgb*1.05);
		detail=texture(brick_surface,at).rgb;
	}else if(kind==4){
		vec2 at=UV/2.15;
		base=texture(slate,at).rgb*(.54+COLOR.rgb*1.1);
		detail=texture(slate_surface,at).rgb;
	}else if(kind==5){
		vec2 at=UV/3.4;
		vec3 grass=texture(meadow,at).rgb;
		float variation=texture(meadow,UV*.037).g;
		base=grass*(.63+variation*1.4)*(.55+COLOR.rgb*1.2);
		detail=texture(meadow_surface,at).rgb;
	}else if(kind==6){
		vec2 pane=UV/vec2(1.38,2.25);
		float id=hash(floor(pane)+building_key);
		vec2 seam=min(fract(pane),1.-fract(pane))/max(fwidth(pane),vec2(.0001));
		float frame=smoothstep(.1,1.5,min(seam.x,seam.y));
		float blind=smoothstep(.63,.65,id)*step(fract(pane.y),id*.65);
		base=mix(vec3(.057,.066,.069),mix(vec3(.025,.048,.057),vec3(.12,.165,.18),id),frame);
		base=mix(base,vec3(.26,.24,.209),blind*.68*frame);
		EMISSION=vec3(.88,.56,.28)*step(.89-min(.59,occupancy*.075),id)*frame*night*step(.5,occupancy);
		detail.b=.18+.11*id;
		spec=.72;
		METALLIC=.32;
	}else if(kind==10){
		EMISSION=vec3(1.,.78,.49)*night*2.8;
	}else if(kind==7){
		vec2 at=UV/3.4;
		float ridge=sin(UV.x*56.);
		float resolved=1.-smoothstep(.018,.11,fwidth(UV.x));
		detail=texture(walk_surface,at).rgb;
		detail.r=.5+ridge*.18*resolved;
		base*=.68+.29*texture(walk,at).r+.14*ridge*resolved;
		detail.b=.55;
		METALLIC=.25;
	}else if(kind==8 || kind==9){
		vec2 at=UV/(kind==8?1.6:3.8);
		detail=texture(road_surface,at).rgb;
		base*=.71+texture(road,at).r*2.;
		if(kind==8) base*=.83+.17*smoothstep(.2,2.6,local.y);
	}
	vec2 xy=(detail.rg*2.-1.)*.64;
	NORMAL_MAP=vec3(xy,sqrt(max(0.,1.-dot(xy,xy))))*.5+.5;
	ALBEDO=base;
	ROUGHNESS=clamp(detail.b,.16,.98);
	SPECULAR=spec;
}
