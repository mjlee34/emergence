shader_type spatial;
uniform float wave_time = 0.;
uniform float rain = 0.;
uniform vec2 wind;
varying vec2 loc;
void vertex(){loc=VERTEX.xz;}
void fragment(){
	float bank=abs(loc.x-(94.+29.*sin(loc.y*.021+.4)-.18*loc.y));
	vec2 p=loc;
	float crosswind=sin(dot(p,vec2(.55,.29))+wave_time*.71);
	float wave=sin(dot(p,vec2(2.31,.84))+crosswind*1.4-wave_time*1.16);
	float ripple=sin(dot(p,vec2(-.71,2.83))+wave*.6+wave_time*.84);
	wave*=1.-smoothstep(.18,1.4,length(fwidth(p)));
	ripple*=1.-smoothstep(.15,1.1,length(fwidth(p)));
	NORMAL=normalize(NORMAL+mat3(VIEW_MATRIX)*vec3(wave*(.032+abs(wind.x)*.048+rain*.032),0.,ripple*(.026+abs(wind.y)*.035+rain*.024)));
	ALBEDO=mix(vec3(.025,.068,.075),vec3(.075,.114,.088),smoothstep(8.,22.,bank));
	ROUGHNESS=.21+.045*crosswind+rain*.13;
	METALLIC=.25;
	SPECULAR=.83;
}
