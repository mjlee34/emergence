shader_type canvas_item;
render_mode unshaded;
uniform float metres_per_pixel = 20.;
uniform float opacity = 1.;
float altitude(vec4 pixel) {
	vec3 raw = pixel.rgb * 255.;
	return raw.r*256. + raw.g + raw.b/256. - 32768.;
}
varying float canvas_alpha;
void vertex() { canvas_alpha=COLOR.a; }
void fragment() {
	float h=altitude(texture(TEXTURE,UV));
	vec2 e=TEXTURE_PIXEL_SIZE;
	vec2 slope=vec2(altitude(texture(TEXTURE,UV+vec2(e.x,0)))-altitude(texture(TEXTURE,UV-vec2(e.x,0))),
	                altitude(texture(TEXTURE,UV+vec2(0,e.y)))-altitude(texture(TEXTURE,UV-vec2(0,e.y))))/(2.*metres_per_pixel);
	vec3 land=mix(vec3(.61,.68,.53),vec3(.79,.77,.59),smoothstep(25.,650.,h));
	land=mix(land,vec3(.65,.59,.49),smoothstep(700.,2800.,h));
	land=mix(land,vec3(.91,.91,.86),smoothstep(2600.,4900.,h));
	float shade=clamp(dot(slope,vec2(.85,.62))*1.65,-.26,.20);
	vec3 sea=vec3(.49,.65,.68);
	vec2 edge=min(UV,1.-UV);
	float feather=smoothstep(0.,.018,min(edge.x,edge.y));
	COLOR=vec4(h<=0. ? sea : land+shade,feather*opacity*canvas_alpha);
}
