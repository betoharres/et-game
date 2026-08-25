shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform float effect_mode = 0.0;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;

uniform vec4 color_a : source_color = vec4(0.05, 1.0, 0.7, 1.0);
uniform vec4 color_b : source_color = vec4(0.8, 0.05, 1.0, 1.0);
uniform vec4 color_c : source_color = vec4(1.0, 0.05, 0.15, 1.0);

uniform float bubble_scale = 7.0;
uniform float distortion = 0.12;
uniform float pulse_speed = 1.4;
uniform float rotation_speed = 0.35;
uniform float transparency : hint_range(0.0, 1.0) = 1.0;

float hash21(vec2 p)
{
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p)
{
	vec2 i = floor(p);
	vec2 f = fract(p);

	f = f * f * (3.0 - 2.0 * f);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	return mix(
		mix(a, b, f.x),
		mix(c, d, f.x),
		f.y
	);
}

float fbm(vec2 p)
{
	float v = 0.0;
	float a = 0.5;

	for (int i = 0; i < 5; i++)
	{
		v += noise(p) * a;
		p *= 2.0;
		a *= 0.5;
	}

	return v;
}

mat2 rot(float a)
{
	float s = sin(a);
	float c = cos(a);

	return mat2(
		vec2(c, -s),
		vec2(s, c)
	);
}

float bubble(vec2 uv, vec2 center, float radius)
{
	float d = length(uv - center);

	float outer = smoothstep(
		radius,
		radius * 0.72,
		d
	);

	float inner = smoothstep(
		radius * 0.72,
		radius * 0.15,
		d
	);

	return outer * (1.0 - inner * 0.65);
}

void fragment()
{
	vec2 uv = UV;
	vec2 centered = uv - 0.5;

	float t = TIME;

	//----------------------------------------------------------
	// LIQUID WORLD
	//----------------------------------------------------------

	vec2 liquid_uv = centered;

	float n1 = fbm(
		centered * 4.0 +
		vec2(t * 0.12, -t * 0.08)
	);

	float n2 = fbm(
		centered * 8.0 -
		vec2(t * 0.18, t * 0.11)
	);

	liquid_uv += vec2(
		n1 - 0.5,
		n2 - 0.5
	) * distortion * intensity;

	//----------------------------------------------------------
	// WRITHING RADIAL STRUCTURE
	//----------------------------------------------------------

	float radius = length(centered);
	float angle = atan(centered.y, centered.x);

	float tentacles = sin(
		angle * 13.0
		+ radius * 24.0
		- t * rotation_speed * 4.0
	);

	tentacles *= smoothstep(
		0.75,
		0.05,
		radius
	);

	//----------------------------------------------------------
	// ROTATING RINGS
	//----------------------------------------------------------

	vec2 ring_uv = centered;
	ring_uv *= rot(t * rotation_speed);

	float ring_radius = length(ring_uv);

	float rings = sin(
		ring_radius * 55.0
		- t * 3.0
		+ fbm(ring_uv * 5.0) * 5.0
	);

	rings = smoothstep(
		0.15,
		0.85,
		rings
	);

	//----------------------------------------------------------
	// BUBBLES
	//----------------------------------------------------------

	float bubbles = 0.0;

	for (int x = -2; x <= 2; x++)
	{
		for (int y = -2; y <= 2; y++)
		{
			vec2 cell = vec2(float(x), float(y));

			vec2 id = floor(
				liquid_uv * bubble_scale
			) + cell;

			float h = hash21(id);

			vec2 bubble_pos =
				(id + vec2(
					hash21(id + 4.1),
					hash21(id + 9.7)
				)) / bubble_scale;

			bubble_pos.y +=
				mod(
					t * (0.03 + h * 0.08),
					1.2
				) - 0.6;

			float r =
				0.012 +
				h * 0.035;

			bubbles += bubble(
				liquid_uv,
				bubble_pos,
				r
			);
		}
	}

	//----------------------------------------------------------
	// ORGANIC PULSE
	//----------------------------------------------------------

	float pulse =
		sin(t * pulse_speed) * 0.5 + 0.5;

	pulse =
		pow(pulse, 3.0);

	float heartbeat =
		sin(t * pulse_speed * 2.0);

	//----------------------------------------------------------
	// COLOR FIELD
	//----------------------------------------------------------

	float field =
		fbm(liquid_uv * 5.0 + t * 0.08);

	float color_mix =
		sin(
			field * 8.0 +
			t * 0.4
		) * 0.5 + 0.5;

	vec3 alien_color =
		mix(
			color_a.rgb,
			color_b.rgb,
			color_mix
		);

	alien_color =
		mix(
			alien_color,
			color_c.rgb,
			pulse * 0.45
		);

	//----------------------------------------------------------
	// MODE-SPECIFIC WEIRDNESS
	//----------------------------------------------------------

	float mode = floor(effect_mode);

	if (mode == 0.0)
	{
		// LIQUID ORGANISM

		alien_color *=
			1.0 +
			tentacles * 0.7;

		alien_color +=
			bubbles * color_a.rgb * 1.5;

		alien_color *=
			0.7 +
			pulse * 0.8;
	}

	else if (mode == 1.0)
	{
		// NEGATIVE LIGHT

		float negative =
			smoothstep(
				0.0,
				0.9,
				fbm(liquid_uv * 7.0)
			);

		alien_color =
			mix(
				alien_color,
				vec3(1.0) - alien_color,
				negative * 0.85
			);

		alien_color +=
			bubbles * vec3(
				1.0,
				0.2,
				0.8
			) * 2.0;
	}

	else if (mode == 2.0)
	{
		// ROTATING EYE

		float eye =
			smoothstep(
				0.55,
				0.05,
				radius
			);

		float iris =
			sin(
				angle * 21.0 +
				radius * 80.0 -
				t * 5.0
			);

		iris *= eye;

		alien_color =
			mix(
				color_b.rgb,
				color_a.rgb,
				iris * 0.5 + 0.5
			);

		alien_color +=
			vec3(1.0, 0.0, 0.1)
			* heartbeat
			* eye;
	}

	else if (mode == 3.0)
	{
		// COSMIC ABOMINATION

		float cosmic =
			fbm(
				liquid_uv * 12.0
				+ vec2(
					t * 0.2,
					-t * 0.13
				)
			);

		alien_color =
			mix(
				vec3(0.0),
				color_c.rgb,
				cosmic
			);

		alien_color +=
			color_b.rgb *
			rings *
			1.8;

		alien_color +=
			color_a.rgb *
			bubbles *
			2.5;
	}

	else if (mode == 4.0)
	{
		// FULL PSYCHOTIC MODE

		alien_color +=
			tentacles *
			color_c.rgb;

		alien_color +=
			rings *
			color_b.rgb;

		alien_color +=
			bubbles *
			color_a.rgb *
			3.0;

		alien_color *=
			1.0 +
			pulse * 1.5;
	}

	//----------------------------------------------------------
	// CHROMATIC ABERRATION
	//----------------------------------------------------------

	float aberration =
		0.008 +
		0.02 * pulse;

	float red =
		fbm(
			liquid_uv * 9.0 +
			vec2(aberration, 0.0)
		);

	float green =
		fbm(
			liquid_uv * 9.0
		);

	float blue =
		fbm(
			liquid_uv * 9.0 -
			vec2(aberration, 0.0)
		);

	vec3 chromatic =
		vec3(
			red,
			green,
			blue
		);

	alien_color =
		mix(
			alien_color,
			alien_color * (0.5 + chromatic * 1.5),
			0.35
		);

	//----------------------------------------------------------
	// FRESNEL-ISH DOME EDGE
	//----------------------------------------------------------

	float edge =
		smoothstep(
			0.25,
			0.5,
			radius
		);

	alien_color +=
		edge *
		color_a.rgb *
		0.8;

	//----------------------------------------------------------
	// GLITCH / SCANLINES
	//----------------------------------------------------------

	float scanline =
		sin(
			UV.y * 900.0 +
			t * 12.0
		);

	float glitch =
		step(
			0.94,
			hash21(
				vec2(
					floor(UV.y * 80.0),
					floor(t * 8.0)
				)
			)
		);

	alien_color *=
		1.0 +
		scanline * 0.08 +
		glitch * 0.4;

	//----------------------------------------------------------
	// VIGNETTE
	//----------------------------------------------------------

	float vignette =
		1.0 -
		smoothstep(
			0.25,
			0.72,
			radius
		);

	alien_color *=
		0.45 +
		vignette * 0.75;

	//----------------------------------------------------------
	// OUTPUT
	//----------------------------------------------------------

	ALBEDO = alien_color;
	EMISSION = alien_color * 1.8;
	ALPHA = transparency;
	
	ROUGHNESS = 0.15;
	METALLIC = 0.0;
}
