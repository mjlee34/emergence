shader_type sky;

uniform vec3 sun_direction = vec3(.7,.4,.5);
uniform float daylight = 1.;
uniform float twilight = 0.;
uniform float cover = .3;
uniform vec2 cloud_scroll = vec2(0.);

float hash(vec2 p) {
	vec3 q=fract(vec3(p.xyx)*.1031);
	q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
float value_noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.-2.*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);
}
float cloud_field(vec2 p) {
	mat2 turn=mat2(vec2(1.76,.91),vec2(-.91,1.76));
	float n=value_noise(p)*.54;
	p=turn*p+3.1; n+=value_noise(p)*.27;
	p=turn*p+7.2; n+=value_noise(p)*.13;
	return n+.06*value_noise(turn*p);
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
	color+=vec3(5.,3.7,2.4)*smoothstep(.99978,.99989,toward);
	float moon=max(dot(dir,-sun_direction),0.);
	color+=vec3(.60,.72,.95)*smoothstep(.99985,.99994,moon)*(1.-daylight);
	if (dir.y>0.) {
		vec2 star=SKY_COORDS*vec2(920.,460.);
		float point=1.-smoothstep(.04,.22,length(fract(star)-.5));
		color+=vec3(.80,.86,1.)*point*step(.992,hash(floor(star)))*(1.-daylight)*smoothstep(.05,.30,height);
		vec2 p=dir.xz/(dir.y+.16)*1.9+cloud_scroll;
		float field=cloud_field(p);
		float wisps=smoothstep(.48,.73,value_noise(p*vec2(1.9,8.1)+cloud_scroll)*.72+value_noise(p*4.3)*.28);
		color=mix(color,mix(vec3(.11,.13,.19),vec3(.95,.80,.70),daylight),wisps*.13*(1.-cover));
		float layer=smoothstep(.85-.64*cover,.96-.57*cover,field);
		float rim=clamp((field-cloud_field(p+sun_direction.xz*.12))*4.+.5,0.,1.);
		vec3 cloud=mix(vec3(.065,.088,.13),mix(vec3(.28,.34,.42),vec3(.91,.94,.98),rim*(1.-cover*.63)),daylight);
		cloud+=vec3(.36,.12,.03)*twilight*rim;
		color=mix(color,cloud,layer*smoothstep(0.,.08,dir.y));
	}
	COLOR=mix(color,vec3(.026,.034,.041)+.11*daylight,smoothstep(0.,.38,-dir.y));
}
