shader_type sky;

uniform vec3 sun_direction = vec3(.7,.4,.5);
uniform float daylight = 1.;
uniform float twilight = 0.;
uniform float cover = .3;
// Two hemispherical panoramas store log2(1 + linear radiance) / 3.
uniform sampler2D cumulus : filter_linear_mipmap, repeat_enable;
uniform sampler2D stratus : filter_linear_mipmap, repeat_enable;
uniform vec2 cloud_scroll = vec2(0.);

float hash(vec2 p) {
	vec3 q=fract(vec3(p.xyx)*.1031);
	q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
void sky() {
	vec3 dir=EYEDIR;
	float height=max(dir.y,0.);
	float toward=max(dot(dir,sun_direction),0.);
	vec3 horizon=mix(vec3(.038,.054,.085),vec3(.70,.79,.89),daylight);
	vec3 zenith=mix(vec3(.007,.016,.045),vec3(.20,.39,.66),daylight);
	horizon=mix(horizon,vec3(.95,.39,.19),twilight*(.20+.80*pow(toward,3.))*(1.-.7*cover));
	zenith=mix(zenith,vec3(.16,.20,.39),twilight*.8);
	vec3 color=mix(horizon,zenith,smoothstep(-.02,mix(.70,.35,twilight),height));
	color+=vec3(1.,.68,.33)*pow(toward,54.)*(.12+.40*twilight);

	float moon=max(dot(dir,-sun_direction),0.);
	color+=vec3(.60,.72,.95)*smoothstep(.99985,.99994,moon)*(1.-daylight);
	if (dir.y>0.) {
		vec2 star=SKY_COORDS*vec2(920.,460.);
		float point=1.-smoothstep(.04,.22,length(fract(star)-.5));
		color+=vec3(.80,.86,1.)*point*step(.992,hash(floor(star)))*(1.-daylight)*smoothstep(.05,.30,height);

	}
	// Rotate the brightest cloud bank with the sun; the clock drives slow drift.
	float longitude=(atan(dir.z,dir.x)-atan(sun_direction.z,sun_direction.x))/TAU;
	float latitude=clamp(acos(clamp(height,0.,1.))/(PI*.5),.002,.998);
	float drift=.025*sin(cloud_scroll.x);
	vec3 clear_sky=exp2(texture(cumulus,vec2(longitude+.595+drift,latitude)).rgb*3.)-1.;
	vec3 grey_sky=exp2(texture(stratus,vec2(longitude+.582+drift*.64,latitude)).rgb*3.)-1.;
	vec3 clouds=mix(clear_sky,grey_sky,smoothstep(.32,.91,cover));
	float day_weight=smoothstep(-.08,.31,sun_direction.y);
	clouds*=mix(vec3(.83,.49,.33),vec3(1.),day_weight);
	color=mix(color,clouds,day_weight*mix(.65,.97,cover));
	color+=vec3(5.,4.2,3.1)*smoothstep(.99978,.99989,toward)*(1.-smoothstep(.35,.92,cover));
	COLOR=mix(color,vec3(.026,.034,.041)+.11*daylight,smoothstep(0.,.38,-dir.y));
}
