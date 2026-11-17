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
// Workfront is a plane in mesh coordinates. The UV2 offset stages road layers.
instance uniform vec4 workfront = vec4(0.,0.,0.,2.);
instance uniform float built_height = 10000.;
instance uniform float occupancy = 0.0;
uniform float night = 0.0;
uniform float wetness = 0.;
uniform float rain = 0.;
uniform float clouds = 0.;
uniform vec2 cloud_scroll;
uniform float wave_time = 0.;
varying vec3 world_pos;
varying vec3 local;
varying flat vec2 building_key;
void vertex(){ local=VERTEX; world_pos=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz; building_key=floor(MODEL_MATRIX[3].xz); }
float hash(vec2 p){ return fract(sin(dot(p,vec2(53.315,18.713)))*8175.15); }
void fragment(){
	if(local.y>built_height || dot(local.xz,workfront.xy)+workfront.z+UV2.y>workfront.w) discard;
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
	float absorb=kind==5 ? .15 : .27;
	vec2 xy=(detail.rg*2.-1.)*.64;
	if(kind==1 || kind==2){
		// Uneven asphalt and stone collect a thin film first in their depressions.
		float low=.50+.22*sin(dot(world_pos.xz,vec2(.59,.31)))+.17*sin(world_pos.x*.21-world_pos.z*.48);
		float film=wetness*smoothstep(.14,.72,low+.18*wetness);
		float pooled=smoothstep(.33,.82,film);
		base*=1.-wetness*.30-film*.28;
		detail.b=mix(detail.b,.12,film);
		spec=mix(spec,.90,film);
		xy*=1.-film*.78;
		vec2 cell=world_pos.xz*2.0;
		vec2 delta=fract(cell)-.5;
		float ring=fract(wave_time*1.9+hash(floor(cell)));
		float radius=length(delta);
		float splash=sin((radius-ring*.55)*64.)*exp(-abs(radius-ring*.55)*25.)*(1.-ring);
		xy+=delta/(radius+.08)*splash*rain*pooled*.14*(1.-smoothstep(.08,.5,length(fwidth(cell))));
	}else if(kind==3 || kind==4 || kind==5 || kind==8 || kind==9){
		base*=1.-wetness*absorb;
		detail.b-=wetness*.13;
	}
	NORMAL_MAP=vec3(xy,sqrt(max(0.,1.-dot(xy,xy))))*.5+.5;
	vec2 shadow_at=world_pos.xz*.018+cloud_scroll*3.;
	float patches=smoothstep(-.65,.7,sin(shadow_at.x+.8*sin(shadow_at.y))*.64+sin(shadow_at.y*.79)*.36);
	float broken=4.*clouds*(1.-clouds);
	ALBEDO=base*(1.-patches*broken*(1.-night)*.14);
	ROUGHNESS=clamp(detail.b,.16,.98);
	SPECULAR=spec;
}
