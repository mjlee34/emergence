shader_type spatial;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
instance uniform vec4 paint : source_color = vec4(.48,.52,.54,1.);
instance uniform float wheel_travel = 0.;
uniform float lamps = 0.;
uniform float wetness = 0.;
varying flat int finish;
varying vec3 cabin_pos;
varying flat vec3 local_eye;

void vertex() {
	finish = UV2.y > 1. ? 3 : int(round(UV2.y * 10.));
	cabin_pos = VERTEX;
	local_eye = (inverse(MODELVIEW_MATRIX) * vec4(0.,0.,0.,1.)).xyz;
	if (finish == 3) {
		vec2 axle = vec2((UV2.x - .5) * 6., UV2.y - 1.);
		float angle = wheel_travel / max(.1,axle.y);
		float s = sin(angle);
		float c = cos(angle);
		mat2 spin = mat2(vec2(c,-s), vec2(s,c));
		VERTEX.xy = axle + spin * (VERTEX.xy - axle);
		NORMAL.xy = spin * NORMAL.xy;
	}
}

// Intersect the view ray with the seat cushions behind the tinted glazing.
float cushion(vec3 origin, vec3 ray, vec3 center, vec3 half_size) {
	vec3 inv = sign(ray) / max(abs(ray), vec3(.0001));
	vec3 t = (center-origin)*inv;
	vec3 span = abs(inv)*half_size;
	vec3 near = t-span;
	vec3 far = t+span;
	float entry = max(0.,max(near.x,max(near.y,near.z)));
	float exit_at = min(far.x,min(far.y,far.z));
	return smoothstep(0.,.045,exit_at-entry);
}

void fragment() {
	vec4 texel = texture(atlas,UV);
	ALBEDO = texel.rgb;
	ROUGHNESS = .64;
	if (finish == 0) {
		float coat = clamp((texel.a-.251)/.749,0.,1.);
		ALBEDO *= mix(vec3(1.),paint.rgb,coat);
		METALLIC = mix(.14,.43,coat);
		ROUGHNESS = mix(.58,mix(.30,.19,wetness),coat);
		CLEARCOAT = coat*.92;
		CLEARCOAT_ROUGHNESS = .17;
	} else if (finish == 1) {
		vec3 ray = normalize(cabin_pos-local_eye);
		// Light from the opposite window falls off below the beltline.
		float side = ray.z >= 0. ? 1. : -1.;
		float across = clamp((side*.73-cabin_pos.z)/(side*max(abs(ray.z),.001)),0.,2.5);
		float far_height = cabin_pos.y+ray.y*across;
		float far_window = smoothstep(.92,1.22,far_height);
		float seats = 0.;
		for (int row=0; row<2; row++) {
			float x = .11-float(row)*.83;
			for (int i=0; i<2; i++) {
				float z = float(i)*.79-.395;
				seats=max(seats,cushion(cabin_pos,ray,vec3(x,.79,z),vec3(.12,.24,.22)));
				seats=max(seats,cushion(cabin_pos,ray,vec3(x-.025,1.055,z),vec3(.085,.10,.13)));
			}
		}
		vec3 cabin=mix(vec3(.010,.015,.017),vec3(.034,.049,.050),far_window);
		ALBEDO=mix(cabin,vec3(.014,.018,.019),seats);
		ROUGHNESS = .115;
		METALLIC = .24;
		SPECULAR = .84;
	} else if (finish == 2) {
		ROUGHNESS = .17;
		METALLIC = .28;
		float rear = step(texel.g*2.+.025,texel.r);
		EMISSION = texel.rgb * (.045 + lamps * mix(4.,2.5,rear));
	} else {
		float rim = smoothstep(.035,.25,max(texel.r,max(texel.g,texel.b)));
		METALLIC = rim*.82;
		ROUGHNESS = mix(.85,.29,rim)-wetness*.14;
	}
}
