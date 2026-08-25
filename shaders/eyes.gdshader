shader_type spatial;

render_mode
	cull_back,
	depth_draw_opaque,
	shadows_disabled,
	specular_schlick_ggx;


// ============================================================
// EFFECTS
// ============================================================
//
// 0 = Void Liquid
// 1 = Acid Eye
// 2 = Negative Light
// 3 = Oil Slick
// 4 = Living Glass
// 5 = Digital Corruption
// 6 = Nebula Core
// 7 = Blood Moon
// 8 = Psychedelic Warp
//

uniform int effect_a : hint_range(0, 8) = 0;
uniform int effect_b : hint_range(0, 8) = 1;

uniform float transition : hint_range(0.0, 1.0) = 0.0;


// ============================================================
// GENERAL
// ============================================================

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float animation_speed : hint_range(0.0, 5.0) = 1.0;
uniform float distortion : hint_range(0.0, 2.0) = 0.45;
uniform float glow : hint_range(0.0, 10.0) = 2.0;


// ============================================================
// EYE
// ============================================================

uniform float pupil_size : hint_range(0.05, 1.0) = 0.22;
uniform float pupil_softness : hint_range(0.001, 0.5) = 0.08;


// ============================================================
// NOISE
// ============================================================

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
	float value = 0.0;
	float amplitude = 0.5;

	for (int i = 0; i < 5; i++)
	{
		value += noise(p) * amplitude;

		p *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}


float cells(vec2 p)
{
	vec2 ip = floor(p);
	vec2 fp = fract(p);

	float min_dist = 10.0;

	for (int y = -1; y <= 1; y++)
	{
		for (int x = -1; x <= 1; x++)
		{
			vec2 n = vec2(float(x), float(y));

			vec2 r = n +
				vec2(
					hash21(ip + n),
					hash21(ip + n + 17.17)
				) -
				fp;

			min_dist = min(
				min_dist,
				dot(r, r)
			);
		}
	}

	return sqrt(min_dist);
}


// ============================================================
// RAINBOW
// ============================================================

vec3 rainbow(float x)
{
	return 0.5 + 0.5 * cos(
		6.28318 *
		(
			vec3(0.0, 0.33, 0.67) +
			x
		)
	);
}


// ============================================================
// EFFECT 0
// VOID LIQUID
// ============================================================

vec3 effect_void_liquid(vec2 uv, float t)
{
	float n1 = fbm(
		uv * 8.0 +
		vec2(t * 0.18, -t * 0.13)
	);

	float n2 = fbm(
		uv * 15.0 -
		vec2(t * 0.11, t * 0.20)
	);

	float swirl = n1 * n2;

	vec3 col = mix(
		vec3(0.005, 0.0, 0.015),
		vec3(0.35, 0.01, 0.50),
		swirl
	);

	col += rainbow(
		n1 + t * 0.03
	) * n2 * 0.12;

	return col;
}


// ============================================================
// EFFECT 1
// ACID EYE
// ============================================================

vec3 effect_acid_eye(vec2 uv, float t)
{
	float acid = fbm(
		uv * 12.0 +
		vec2(t * 0.25, -t * 0.18)
	);

	float bubbles = cells(
		uv * 14.0 +
		vec2(0.0, t * 0.20)
	);

	float veins = smoothstep(
		0.32,
		0.42,
		abs(
			sin(
				uv.x * 35.0 +
				acid * 9.0 +
				t
			)
		)
	);

	vec3 col = mix(
		vec3(0.01, 0.04, 0.0),
		vec3(0.45, 1.0, 0.01),
		acid
	);

	col += vec3(0.2, 1.0, 0.0) *
		veins *
		0.5;

	col += vec3(0.5, 1.0, 0.05) *
		(1.0 - bubbles) *
		0.4;

	return col;
}


// ============================================================
// EFFECT 2
// NEGATIVE LIGHT
// ============================================================

vec3 effect_negative_light(vec2 uv, vec3 normal, float t)
{
	float n = fbm(
		uv * 9.0 +
		t * 0.05
	);

	float fake_light = dot(
		normalize(normal),
		normalize(vec3(0.3, 0.7, 0.4))
	);

	fake_light = 1.0 - fake_light * 0.5;

	vec3 col = vec3(
		n,
		n * 0.85,
		n * 0.65
	);

	col *= fake_light;

	float dark_highlight = pow(
		max(fake_light - 0.65, 0.0),
		3.0
	);

	col -= vec3(
		0.15,
		0.25,
		0.30
	) * dark_highlight;

	col += vec3(
		0.02,
		0.15,
		0.25
	);

	return col;
}


// ============================================================
// EFFECT 3
// OIL SLICK
// ============================================================

vec3 effect_oil_slick(vec2 uv, float t)
{
	vec2 p = uv - 0.5;

	float radius = length(p);

	float oil = fbm(
		uv * 6.0 +
		vec2(t * 0.08, -t * 0.12)
	);

	float angle = atan(p.y, p.x);

	float bands = sin(
		angle * 6.0 +
		radius * 35.0 +
		oil * 8.0 +
		t * 0.5
	);

	float film =
		radius +
		oil * 0.08;

	vec3 col = rainbow(
		film * 2.0 +
		bands * 0.15
	);

	return col * 0.35;
}


// ============================================================
// EFFECT 4
// LIVING GLASS
// ============================================================

vec3 effect_living_glass(vec2 uv, float t)
{
	float veins = fbm(
		uv * 18.0 -
		vec2(t * 0.08, t * 0.13)
	);

	float vein_lines = smoothstep(
		0.55,
		0.72,
		veins
	);

	float pulse =
		0.5 +
		0.5 * sin(
			t * 2.0 +
			veins * 8.0
		);

	vec3 col = vec3(
		0.04,
		0.01,
		0.06
	);

	col += vec3(
		0.70,
		0.03,
		0.25
	) * vein_lines;

	col += vec3(
		0.20,
		0.0,
		0.80
	) * pulse * 0.15;

	return col;
}


// ============================================================
// EFFECT 5
// DIGITAL CORRUPTION
// ============================================================

vec3 effect_digital_corruption(vec2 uv, float t)
{
	float scanline = floor(
		uv.y * 80.0
	);

	float glitch = hash21(
		vec2(
			scanline,
			floor(t * 8.0)
		)
	);

	float horizontal_shift =
		(glitch - 0.5) *
		step(0.72, glitch) *
		0.15;

	vec2 glitch_uv = uv;

	glitch_uv.x += horizontal_shift;

	float blocks = floor(
		glitch_uv.x * 20.0
	);

	float block_noise = hash21(
		vec2(
			blocks,
			scanline
		)
	);

	float corruption = step(
		0.82,
		block_noise
	);

	float digital = fbm(
		glitch_uv * 25.0
	);

	vec3 col = vec3(
		digital * 0.1,
		digital * 0.3,
		digital
	);

	col += rainbow(
		block_noise +
		t * 0.1
	) * corruption;

	return col;
}


// ============================================================
// EFFECT 6
// NEBULA CORE
// ============================================================

vec3 effect_nebula_core(vec2 uv, float t)
{
	float cosmic = fbm(
		uv * 4.0 +
		vec2(
			t * 0.03,
			-t * 0.025
		)
	);

	float stars = step(
		0.94,
		hash21(
			floor(uv * 80.0)
		)
	);

	float nebula = sin(
		cosmic * 8.0 +
		length(uv - 0.5) * 12.0
	);

	vec3 col = mix(
		vec3(0.02, 0.0, 0.08),
		vec3(0.25, 0.01, 0.45),
		cosmic
	);

	col += vec3(
		0.05,
		0.30,
		1.0
	) * nebula * 0.5;

	col += vec3(1.0) * stars;

	return col;
}


// ============================================================
// EFFECT 7
// BLOOD MOON
// ============================================================

vec3 effect_blood_moon(vec2 uv, float t)
{
	float blood = fbm(
		uv * 9.0 -
		vec2(
			t * 0.06,
			t * 0.09
		)
	);

	float cracks = smoothstep(
		0.58,
		0.70,
		fbm(uv * 24.0)
	);

	float pulse =
		0.5 +
		0.5 * sin(t * 1.7);

	vec3 col = mix(
		vec3(0.015, 0.0, 0.0),
		vec3(0.35, 0.005, 0.0),
		blood
	);

	col += vec3(
		1.0,
		0.015,
		0.0
	) * cracks * pulse;

	return col;
}


// ============================================================
// EFFECT 8
// PSYCHEDELIC WARP
// ============================================================

vec3 effect_psychedelic(vec2 uv, float t)
{
	vec2 p = uv - 0.5;

	float warp = fbm(
		uv * 5.0 +
		vec2(
			sin(t * 0.3),
			cos(t * 0.2)
		)
	);

	float angle = atan(p.y, p.x);

	float spiral =
		angle +
		length(p) * 12.0 +
		warp * 5.0 +
		t * 0.4;

	float psychedelic =
		sin(spiral * 4.0);

	vec3 col = rainbow(
		psychedelic * 0.5 +
		length(p) * 2.0 +
		t * 0.05
	);

	col *= 0.35 + warp;

	col += rainbow(
		warp + t * 0.1
	) * 0.3;

	return col;
}


// ============================================================
// SELECT EFFECT
// ============================================================

vec3 get_effect(
	int id,
	vec2 uv,
	vec3 normal,
	float t
)
{
	if (id == 0)
	{
		return effect_void_liquid(uv, t);
	}
	else if (id == 1)
	{
		return effect_acid_eye(uv, t);
	}
	else if (id == 2)
	{
		return effect_negative_light(
			uv,
			normal,
			t
		);
	}
	else if (id == 3)
	{
		return effect_oil_slick(uv, t);
	}
	else if (id == 4)
	{
		return effect_living_glass(uv, t);
	}
	else if (id == 5)
	{
		return effect_digital_corruption(uv, t);
	}
	else if (id == 6)
	{
		return effect_nebula_core(uv, t);
	}
	else if (id == 7)
	{
		return effect_blood_moon(uv, t);
	}

	return effect_psychedelic(
		uv,
		t
	);
}


// ============================================================
// VERTEX
// ============================================================

void vertex()
{
	// Very subtle breathing of the dome.
	float pulse = sin(
		TIME * animation_speed * 0.7
	);

	VERTEX += NORMAL *
		pulse *
		0.001 *
		distortion;
}


// ============================================================
// FRAGMENT
// ============================================================

void fragment()
{
	float t = TIME * animation_speed;

	vec2 uv = UV;

	vec2 centered = uv - 0.5;

	float radius = length(centered);

	// --------------------------------------------------------
	// Liquid UV distortion
	// --------------------------------------------------------

	float n1 = fbm(
		uv * 5.0 +
		t * 0.08
	);

	float n2 = fbm(
		uv * 13.0 -
		t * 0.11
	);

	vec2 flow = vec2(
		n1 - 0.5,
		n2 - 0.5
	);

	uv += flow *
		distortion *
		0.08;

	// --------------------------------------------------------
	// Get both effects
	// --------------------------------------------------------

	vec3 color_a = get_effect(
		effect_a,
		uv,
		NORMAL,
		t
	);

	vec3 color_b = get_effect(
		effect_b,
		uv,
		NORMAL,
		t
	);

	// --------------------------------------------------------
	// Transition
	// --------------------------------------------------------

	float trans = smoothstep(
		0.0,
		1.0,
		transition
	);

	vec3 col = mix(
		color_a,
		color_b,
		trans
	);

	// --------------------------------------------------------
	// Eye pupil
	// --------------------------------------------------------

	float pupil = smoothstep(
		pupil_size + pupil_softness,
		pupil_size - pupil_softness,
		radius
	);

	// Slight vertical slit.
	float slit = smoothstep(
		pupil_size * 0.55 + pupil_softness,
		pupil_size * 0.55 - pupil_softness,
		length(
			vec2(
				centered.x * 2.2,
				centered.y
			)
		)
	);

	pupil = max(
		pupil,
		slit
	);

	// --------------------------------------------------------
	// Pupil distortion
	// --------------------------------------------------------

	float pupil_noise = fbm(
		centered * 18.0 +
		t * 0.4
	);

	float pupil_edge = smoothstep(
		0.25,
		0.75,
		pupil_noise
	);

	pupil *=
		0.9 +
		pupil_edge * 0.1;

	// Make pupil extremely dark.
	col *=
		1.0 -
		pupil * 0.98;

	// --------------------------------------------------------
	// Transition corruption
	// --------------------------------------------------------

	float transition_noise = fbm(
		uv * 30.0 -
		t * 2.0
	);

	float transition_edge =
		smoothstep(
			0.15,
			0.85,
			transition
		);

	float corruption = smoothstep(
		0.35,
		0.65,
		transition_noise +
		transition_edge
	);

	// Horizontal tearing.
	float tear = step(
		0.82,
		hash21(
			vec2(
				floor(uv.y * 70.0),
				floor(t * 12.0)
			)
		)
	);

	col += rainbow(
		transition_noise +
		t * 0.2
	) *
		corruption *
		tear *
		transition_edge *
		1.5;

	// --------------------------------------------------------
	// Violent flash near the middle of transition
	// --------------------------------------------------------

	float flash =
		smoothstep(
			0.40,
			0.50,
			transition
		) *
		smoothstep(
			0.60,
			0.50,
			transition
		);

	col += rainbow(
		t * 0.1 +
		transition_noise
	) *
		flash *
		2.0;

	// --------------------------------------------------------
	// Rim
	// --------------------------------------------------------

	float rim = pow(
		smoothstep(
			0.2,
			0.8,
			radius
		),
		3.0
	);

	col += rainbow(
		rim * 1.5 +
		t * 0.03
	) *
		rim *
		0.15 *
		intensity;

	// --------------------------------------------------------
	// Output
	// --------------------------------------------------------

	ALBEDO = col * intensity;

	EMISSION =
		col *
		glow;

	ROUGHNESS = 0.08;
	METALLIC = 0.15;
	SPECULAR = 1.0;
}
