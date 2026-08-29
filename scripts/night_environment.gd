extends Node3D

## Controla o clima noturno da fase: ceu, Lua, nevoa e presets de qualidade.
##
## A nevoa tem duas camadas:
## - GroundFogLayer: manta baixa e local, que segue o chao;
## - fog atmosferico do Environment, em modo Depth. Ele e o orcamento de
##   renderizacao do mapa: fecha opaco antes do alcance das cameras, entao
##   nada precisa ser desenhado alem dele. Ligado por padrao.
##
## O volumetric fog continua DESLIGADO em todos os presets, por custo. Para
## experimentar, ponha "volumetric_enabled" como true no preset desejado, em
## QUALITY_PRESETS. Ele so alimenta as luzes do grupo "volumetric_lights"
## (Lua, feixes da nave, abducao) fora do preset HIGH.
##
## Perfis de nevoa: no chao a nevoa fecha por volta de 400 m; no ar, o avioo
## precisa enxergar mais longe, entao set_fog_profile(FogProfile.FLIGHT) abre
## a nevoa ate 950 m, ainda dentro do alcance do Terrain3D. A troca e suave.
##
## Eventos alienigenas usam set_alien_fog_intensity(), que interpola densidade,
## tonalidade, scattering, movimento da nevoa e interferencia visual.

enum QualityLevel {
	LOW,
	MEDIUM,
	HIGH,
}

## Alcance da nevoa por contexto. GROUND e a pe / de caminhao; FLIGHT abre a
## nevoa enquanto o jogador pilota o aviao.
enum FogProfile {
	GROUND,
	FLIGHT,
}

## Luzes autorizadas a alimentar a volumetria fora do preset HIGH.
const VOLUMETRIC_LIGHT_GROUP : StringName = &"volumetric_lights"
## Subconjunto que ganha reforco durante eventos alienigenas.
const ALIEN_LIGHT_GROUP : StringName = &"alien_volumetric_lights"
const POST_PROCESS_GROUP : StringName = &"alien_post_process"
const UFO_GROUP : StringName = &"ufo_lighting"
const BASE_FOG_ENERGY_META : StringName = &"base_volumetric_fog_energy"

## Presets de qualidade. Ajuste aqui para calibrar LOW/MEDIUM/HIGH de uma vez.
const QUALITY_PRESETS : Array[Dictionary] = [
	{
		"volumetric_enabled": false,
		"volumetric_density_scale": 0.0,
		"volumetric_length": 40.0,
		"volumetric_anisotropy": 0.2,
		"volumetric_volume_size": 48,
		"volumetric_volume_depth": 48,
		"volumetric_filter": false,
		"fog_density_scale": 1.0,
		"fog_height_density_scale": 1.0,
		"fog_depth_scale": 0.82,
		"fog_volume_enabled": false,
		"non_alien_volumetric_lights": false,
		"particles": false,
		"ground_fog": {
			"layers": 1,
			"opacity": 0.5,
			"zones": 0,
			"far_start": 18.0,
			"far_end": 46.0,
			"height_start": 5.0,
			"height_end": 14.0,
			"soft_depth": 0.0,
			"detail": 0.0,
			"warp": 0.0,
		},
	},
	{
		"volumetric_enabled": false,
		"volumetric_density_scale": 0.85,
		"volumetric_length": 62.0,
		"volumetric_anisotropy": 0.3,
		"volumetric_volume_size": 64,
		"volumetric_volume_depth": 64,
		"volumetric_filter": false,
		"fog_density_scale": 1.0,
		"fog_height_density_scale": 1.0,
		"fog_depth_scale": 0.92,
		"fog_volume_enabled": false,
		"non_alien_volumetric_lights": false,
		"particles": true,
		"ground_fog": {
			"layers": 1,
			"opacity": 0.48,
			"zones": 4,
			"far_start": 22.0,
			"far_end": 55.0,
			"height_start": 6.0,
			"height_end": 16.0,
			"soft_depth": 0.8,
			"detail": 0.5,
			"warp": 0.8,
		},
	},
	{
		"volumetric_enabled": false,
		"volumetric_density_scale": 1.0,
		"volumetric_length": 92.0,
		"volumetric_anisotropy": 0.38,
		"volumetric_volume_size": 96,
		"volumetric_volume_depth": 96,
		"volumetric_filter": true,
		"fog_density_scale": 1.0,
		"fog_height_density_scale": 1.0,
		"fog_depth_scale": 1.0,
		"fog_volume_enabled": false,
		"non_alien_volumetric_lights": true,
		"particles": true,
		"ground_fog": {
			"layers": 2,
			"opacity": 0.46,
			"zones": 6,
			"far_start": 26.0,
			"far_end": 64.0,
			"height_start": 7.0,
			"height_end": 18.0,
			"soft_depth": 1.0,
			"detail": 1.0,
			"warp": 1.1,
		},
	},
]

@export_group("Quality")
@export_enum("Low", "Medium", "High") var quality_level : int = QualityLevel.HIGH
@export var particles_enabled : bool = true
@export var ground_fog_enabled : bool = true
@export_range(0.0, 1.0, 0.05) var motion_scale : float = 1.0

@export_group("Sky")
@export_range(0.0, 1.0, 0.01) var star_density : float = 0.56
@export_range(0.0, 3.0, 0.01) var star_brightness : float = 1.15
@export_range(0.0, 3.0, 0.01) var twinkle_speed : float = 0.42
@export_range(0.0, 0.5, 0.01) var twinkle_amount : float = 0.16
@export var random_seed : int = 73021

@export_group("Moon")
@export var moon_direction : Vector3 = Vector3(0.48, 0.34, 0.81)
@export_color_no_alpha var moon_color : Color = Color(0.68, 0.76, 0.9)
@export_range(0.0, 2.0, 0.01) var moon_light_energy : float = 0.75
@export_range(0.01, 0.12, 0.001) var moon_angular_size : float = 0.028
@export_range(0.0, 0.5, 0.01) var cloud_shadow_strength : float = 0.12
@export_range(0.0, 0.1, 0.001) var cloud_speed : float = 0.008

@export_group("Shooting Stars")
@export_range(5.0, 180.0, 1.0) var shooting_star_interval_min : float = 38.0
@export_range(5.0, 240.0, 1.0) var shooting_star_interval_max : float = 85.0

@export_group("Fog and Atmosphere")
## Fog de tela cheia do Environment, em modo Depth. Fecha opaco antes do "far"
## das cameras e e o que esconde a borda do mapa.
@export var atmospheric_fog_enabled : bool = true
## Cor do fog atmosferico e do espalhamento da volumetria. Fica proxima da cor
## do horizonte do ceu: se for mais clara, o fog vira uma faixa luminosa.
@export_color_no_alpha var fog_color : Color = Color(0.022, 0.045, 0.09)
## Cor da nevoa rasteira. Ela nao recebe luz, entao precisa ser mais clara que
## o fog atmosferico para ler como nevoa iluminada pela Lua.
@export_color_no_alpha var ground_fog_color : Color = Color(0.18, 0.28, 0.35)
## Distancia em que o fog de profundidade comeca a somar (perfil GROUND).
@export_range(10.0, 2000.0, 5.0) var fog_depth_begin : float = 350.0
## Distancia em que o fog de profundidade fica opaco (perfil GROUND). Precisa
## ficar abaixo do "far" das cameras de jogo, hoje 450 m.
@export_range(20.0, 2500.0, 5.0) var fog_depth_end : float = 400.0
## Curva entre begin e end. 1.0 e linear; abaixo de 1 fecha mais cedo.
@export_range(0.1, 4.0, 0.05) var fog_depth_curve : float = 1.0
## Opacidade maxima do fog de profundidade, aplicada em fog_depth_end.
## ATENCAO: em modo Depth o Godot 4.7 MULTIPLICA a rampa de profundidade por
## Environment.fog_density. Deixar aqui o antigo 0.010 do modo exponencial
## reduz a nevoa a 1% e ela some por completo. 1.0 = parede opaca.
@export_range(0.0, 1.0, 0.01) var atmospheric_fog_opacity : float = 1.0
## Altura em que a nevoa de altura barata comeca a somar.
@export_range(0.0, 30.0, 0.5) var atmospheric_fog_height : float = 6.0
## Ganho da nevoa de altura. ATENCAO: no Godot 4.7 este termo MULTIPLICA o fog
## de profundidade. Um valor pequeno (0.006, por exemplo) derruba o depth fog
## para ~3% e a parede de nevoa simplesmente some. Fica em 0.0 de proposito:
## quem faz a nevoa de perto e o GroundFogLayer.
@export_range(0.0, 0.3, 0.001) var atmospheric_fog_height_density : float = 0.0
## Densidade do FogVolume rasteiro, usado apenas no preset HIGH.
@export_range(0.0, 0.05, 0.001) var ground_fog_density : float = 0.012
@export_range(0.0, 2.0, 0.01) var fog_drift_speed : float = 0.18
@export_range(0, 256, 1) var atmospheric_particle_amount : int = 96

@export_group("Flight Fog Profile")
## Perfil usado enquanto o jogador pilota. O limite e o "far" da camera do
## aviao: o terreno some no plano distante, medido em ~1330 m com far = 1200.
## A nevoa fecha em 950 m, bem antes disso, e ainda deixa o jogador enxergar
## a fazenda inteira de 350 m de altitude.
@export_range(10.0, 2000.0, 5.0) var flight_fog_depth_begin : float = 550.0
@export_range(20.0, 2500.0, 5.0) var flight_fog_depth_end : float = 950.0
## Velocidade da transicao entre os perfis GROUND e FLIGHT.
@export_range(0.1, 8.0, 0.1) var fog_profile_response : float = 1.2

@export_group("Alien Atmosphere")
@export_color_no_alpha var alien_fog_color : Color = Color(0.09, 0.62, 0.5)
## Velocidade da transicao de set_alien_fog_intensity().
@export_range(0.1, 8.0, 0.1) var alien_fog_response : float = 1.6
@export_range(0.0, 6.0, 0.05) var alien_volumetric_density_boost : float = 1.5
@export_range(0.0, 4.0, 0.05) var alien_fog_density_boost : float = 0.5
@export_range(0.0, 0.95, 0.01) var alien_anisotropy : float = 0.72
@export_range(0.0, 4.0, 0.05) var alien_emission_energy : float = 0.5
@export_range(0.0, 4.0, 0.05) var alien_beam_fog_boost : float = 1.8
@export_range(0.0, 1.0, 0.01) var alien_interference : float = 0.55

@onready var world_environment : WorldEnvironment = $WorldEnvironment
@onready var moon_visual : Node3D = $SkyController/MoonVisual
@onready var moon_light : DirectionalLight3D = $SkyController/MoonVisual/MoonLight
@onready var shooting_stars : GPUParticles3D = $ShootingStars
@onready var atmospheric_particles : GPUParticles3D = $AtmosphericParticles
@onready var ground_fog : FogVolume = $GroundFog
@onready var ground_fog_layer : GroundFogLayer = $GroundFogLayer

var _rng : RandomNumberGenerator = RandomNumberGenerator.new()
var _sky_material : ShaderMaterial
var _base_moon_energy : float = 0.0
var _base_background_energy : float = 1.0
var _base_ambient_energy : float = 0.0
var _base_volumetric_fog_density : float = 0.0
var _base_volumetric_fog_anisotropy : float = 0.34
var _alien_lights : Array[Light3D] = []
var _moon_debug_enabled : bool = true
var _sky_debug_enabled : bool = true
var _ambient_debug_enabled : bool = true
var _fog_debug_enabled : bool = true
var _moon_debug_intensity : float = 1.0
var _sky_debug_intensity : float = 1.0
var _ambient_debug_intensity : float = 1.0
var _fog_debug_intensity : float = 1.0
var _alien_fog_target : float = 0.0
var _alien_fog_current : float = 0.0
var _fog_profile : int = FogProfile.GROUND
var _fog_profile_blend : float = 0.0
var _shooting_star_timer : float = 0.0
var _elapsed : float = 0.0


func _ready() -> void:
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed

	var environment : Environment = world_environment.environment
	if environment != null:
		_base_background_energy = environment.background_energy_multiplier
		_base_ambient_energy = environment.ambient_light_energy
		_base_volumetric_fog_density = environment.volumetric_fog_density
		_base_volumetric_fog_anisotropy = environment.volumetric_fog_anisotropy
		if environment.sky != null:
			_sky_material = environment.sky.sky_material as ShaderMaterial

	_apply_inspector_settings()
	_apply_quality_level()
	_schedule_shooting_star()


func _process(delta : float) -> void:
	_elapsed += delta * motion_scale
	_update_alien_fog(delta)
	_update_fog_profile(delta)
	_update_cloud_shadow()
	_update_ground_atmosphere()
	_update_shooting_stars(delta)


## Troca o preset em runtime (menu de debug, opcoes ou eventos de script).
func set_quality_preset(level : int) -> void:
	var clamped : int = clampi(level, QualityLevel.LOW, QualityLevel.HIGH)
	if clamped == quality_level:
		return
	quality_level = clamped
	_apply_inspector_settings()
	_apply_quality_level()


func get_quality_preset() -> int:
	return quality_level


## Intensidade da atmosfera alienigena, de 0 (noite normal) a 1 (evento pleno).
## A transicao e suave; chame com 0.0 para voltar ao normal.
func set_alien_fog_intensity(intensity : float) -> void:
	_alien_fog_target = clampf(intensity, 0.0, 1.0)


func get_alien_fog_intensity() -> float:
	return _alien_fog_current


func _current_preset() -> Dictionary:
	return QUALITY_PRESETS[clampi(quality_level, 0, QUALITY_PRESETS.size() - 1)]


func _apply_inspector_settings() -> void:
	var normalized_moon_direction : Vector3 = moon_direction.normalized()
	if normalized_moon_direction.is_zero_approx():
		normalized_moon_direction = Vector3(0.48, 0.34, 0.81).normalized()

	if _sky_material != null:
		_sky_material.set_shader_parameter("star_density", star_density)
		_sky_material.set_shader_parameter("star_brightness", star_brightness)
		_sky_material.set_shader_parameter("twinkle_speed", twinkle_speed * motion_scale)
		_sky_material.set_shader_parameter("twinkle_amount", twinkle_amount)
		_sky_material.set_shader_parameter("star_seed", float(random_seed))
		_sky_material.set_shader_parameter("moon_direction", normalized_moon_direction)
		_sky_material.set_shader_parameter("moon_color", moon_color)
		_sky_material.set_shader_parameter("moon_angular_size", moon_angular_size)
		_sky_material.set_shader_parameter("cloud_speed", cloud_speed * motion_scale)

	moon_visual.basis = Basis.looking_at(normalized_moon_direction, Vector3.UP)
	# MoonLight is a child of the already rotated MoonVisual. Set its global basis
	# so the parent's rotation is not applied to the light direction a second time.
	moon_light.global_basis = Basis.looking_at(-normalized_moon_direction, Vector3.UP)
	moon_light.light_color = moon_color
	_base_moon_energy = moon_light_energy
	moon_light.light_energy = _base_moon_energy * _moon_debug_intensity

	ground_fog_layer.set_fog_colors(ground_fog_color, alien_fog_color)
	_apply_fog_values()


## Reaplica densidade, cor e scattering a partir do preset, do slider de debug
## e da intensidade alienigena atual.
func _apply_fog_values() -> void:
	var preset : Dictionary = _current_preset()
	var alien : float = _alien_fog_current
	var alien_tint : Color = fog_color.lerp(alien_fog_color, alien * 0.5)

	var fog_material : FogMaterial = ground_fog.material as FogMaterial
	if fog_material != null:
		fog_material.albedo = alien_tint
		fog_material.density = (
			ground_fog_density
			* _fog_debug_intensity
			* (1.0 + alien * alien_fog_density_boost)
		)

	var environment : Environment = world_environment.environment
	if environment == null:
		return

	environment.fog_enabled = atmospheric_fog_enabled and _fog_debug_enabled
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = alien_tint
	environment.fog_density = clampf(
		atmospheric_fog_opacity
		* float(preset.get("fog_density_scale", 1.0))
		* _fog_debug_intensity,
		0.0,
		1.0
	)

	# Em modo Depth a "densidade" e distancia: quanto menor o alcance, mais
	# fechada a nevoa. O preset e o slider de debug encurtam o alcance, e o
	# evento alienigena tambem aproxima a parede de nevoa.
	var depth_scale : float = (
		float(preset.get("fog_depth_scale", 1.0))
		/ maxf(_fog_debug_intensity, 0.05)
		/ (1.0 + alien * alien_fog_density_boost * 0.45)
	)
	var begin : float = lerpf(fog_depth_begin, flight_fog_depth_begin, _fog_profile_blend)
	var end : float = lerpf(fog_depth_end, flight_fog_depth_end, _fog_profile_blend)
	environment.fog_depth_begin = begin * depth_scale
	environment.fog_depth_end = maxf(
		environment.fog_depth_begin + 1.0,
		end * depth_scale
	)
	environment.fog_depth_curve = fog_depth_curve

	environment.fog_height = atmospheric_fog_height
	environment.fog_height_density = (
		atmospheric_fog_height_density
		* float(preset.get("fog_height_density_scale", 1.0))
		* _fog_debug_intensity
	)

	environment.volumetric_fog_density = (
		_base_volumetric_fog_density
		* float(preset.get("volumetric_density_scale", 1.0))
		* _fog_debug_intensity
		* (1.0 + alien * alien_volumetric_density_boost)
	)
	environment.volumetric_fog_albedo = fog_color.lerp(alien_fog_color, alien * 0.7)
	environment.volumetric_fog_anisotropy = lerpf(
		float(preset.get("volumetric_anisotropy", _base_volumetric_fog_anisotropy)),
		alien_anisotropy,
		alien
	)
	environment.volumetric_fog_emission = alien_fog_color
	environment.volumetric_fog_emission_energy = alien * alien_emission_energy

	ground_fog_layer.set_density_scale(_fog_debug_intensity)


func _apply_quality_level() -> void:
	var preset : Dictionary = _current_preset()
	var use_particles : bool = particles_enabled and bool(preset.get("particles", true))
	var use_ground_fog : bool = ground_fog_enabled and _fog_debug_enabled
	var use_fog_volume : bool = (
		use_ground_fog and bool(preset.get("fog_volume_enabled", false))
	)

	shooting_stars.visible = use_particles
	atmospheric_particles.visible = use_particles
	atmospheric_particles.emitting = use_particles
	@warning_ignore("integer_division")
	atmospheric_particles.amount = (
		atmospheric_particle_amount
		if quality_level == QualityLevel.HIGH
		else maxi(1, atmospheric_particle_amount / 2)
	)

	ground_fog.visible = use_fog_volume
	ground_fog_layer.set_fog_enabled(use_ground_fog)
	var ground_fog_config : Dictionary = preset.get("ground_fog", {})
	ground_fog_layer.apply_quality(ground_fog_config)

	_apply_volumetric_fog(preset)
	_apply_fog_values()
	_refresh_light_volumetrics.call_deferred()
	_notify_ufo_quality.call_deferred(use_particles)


func _apply_volumetric_fog(preset : Dictionary) -> void:
	var environment : Environment = world_environment.environment
	if environment == null:
		return

	var use_volumetric : bool = (
		bool(preset.get("volumetric_enabled", false)) and _fog_debug_enabled
	)
	environment.volumetric_fog_enabled = use_volumetric
	environment.volumetric_fog_length = float(preset.get("volumetric_length", 82.0))
	if not use_volumetric:
		return

	# Resolucao do froxel grid: o item mais caro da volumetria.
	RenderingServer.environment_set_volumetric_fog_volume_size(
		int(preset.get("volumetric_volume_size", 64)),
		int(preset.get("volumetric_volume_depth", 64))
	)
	RenderingServer.environment_set_volumetric_fog_filter_active(
		bool(preset.get("volumetric_filter", false))
	)


## Impede que todas as luzes do mapa alimentem a volumetria. Fora do preset
## HIGH, apenas o grupo "volumetric_lights" contribui.
func _refresh_light_volumetrics() -> void:
	var scene_root : Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	if scene_root == null:
		return

	var preset : Dictionary = _current_preset()
	var allow_all : bool = bool(preset.get("non_alien_volumetric_lights", true))
	_alien_lights.clear()

	for node : Node in scene_root.find_children("*", "Light3D", true, false):
		var light : Light3D = node as Light3D
		if light == null:
			continue

		var base_energy : float = light.get_meta(
			BASE_FOG_ENERGY_META,
			light.light_volumetric_fog_energy
		)
		light.set_meta(BASE_FOG_ENERGY_META, base_energy)

		var is_alien : bool = light.is_in_group(ALIEN_LIGHT_GROUP)
		if is_alien:
			_alien_lights.append(light)
		var allowed : bool = allow_all or is_alien or light.is_in_group(
			VOLUMETRIC_LIGHT_GROUP
		)
		light.light_volumetric_fog_energy = base_energy if allowed else 0.0

	_apply_alien_light_boost()


func _apply_alien_light_boost() -> void:
	for light : Light3D in _alien_lights:
		if not is_instance_valid(light):
			continue
		var base_energy : float = light.get_meta(BASE_FOG_ENERGY_META, 1.0)
		light.light_volumetric_fog_energy = base_energy * (
			1.0 + _alien_fog_current * alien_beam_fog_boost
		)


## Troca o perfil de alcance da nevoa. Chamado pelo aviao ao assumir e ao
## largar o controle. A transicao e suave; nao ha custo extra de frame, so o
## alcance em que o fog fecha muda.
func set_fog_profile(profile : int) -> void:
	_fog_profile = clampi(profile, FogProfile.GROUND, FogProfile.FLIGHT)


func get_fog_profile() -> int:
	return _fog_profile


func _update_fog_profile(delta : float) -> void:
	var target : float = 1.0 if _fog_profile == FogProfile.FLIGHT else 0.0
	if is_equal_approx(_fog_profile_blend, target):
		return

	var weight : float = 1.0 - exp(-fog_profile_response * delta)
	_fog_profile_blend = lerpf(_fog_profile_blend, target, weight)
	if absf(_fog_profile_blend - target) < 0.002:
		_fog_profile_blend = target

	_apply_fog_values()


func _update_alien_fog(delta : float) -> void:
	if is_equal_approx(_alien_fog_current, _alien_fog_target):
		return

	var weight : float = 1.0 - exp(-alien_fog_response * delta)
	_alien_fog_current = lerpf(_alien_fog_current, _alien_fog_target, weight)
	if absf(_alien_fog_current - _alien_fog_target) < 0.002:
		_alien_fog_current = _alien_fog_target

	_apply_fog_values()
	_apply_alien_light_boost()
	ground_fog_layer.set_alien_blend(_alien_fog_current)
	_notify_alien_atmosphere()


func _notify_alien_atmosphere() -> void:
	if alien_interference > 0.0:
		for node : Node in get_tree().get_nodes_in_group(POST_PROCESS_GROUP):
			if node.has_method(&"set_manual_interference"):
				node.call(
					&"set_manual_interference",
					_alien_fog_current * alien_interference
				)

	for node : Node in get_tree().get_nodes_in_group(UFO_GROUP):
		if node.has_method(&"set_alien_fog_intensity"):
			node.call(&"set_alien_fog_intensity", _alien_fog_current)


func set_debug_moon_enabled(enabled : bool) -> void:
	_moon_debug_enabled = enabled
	moon_light.visible = enabled


func is_debug_moon_enabled() -> bool:
	return _moon_debug_enabled


func set_debug_moon_intensity(intensity : float) -> void:
	_moon_debug_intensity = clampf(intensity, 0.0, 2.0)
	_update_cloud_shadow()


func get_debug_moon_intensity() -> float:
	return _moon_debug_intensity


func set_debug_sky_enabled(enabled : bool) -> void:
	_sky_debug_enabled = enabled
	var environment : Environment = world_environment.environment
	if environment != null:
		environment.background_energy_multiplier = (
			_base_background_energy * _sky_debug_intensity if enabled else 0.0
		)


func is_debug_sky_enabled() -> bool:
	return _sky_debug_enabled


func set_debug_sky_intensity(intensity : float) -> void:
	_sky_debug_intensity = clampf(intensity, 0.0, 2.0)
	set_debug_sky_enabled(_sky_debug_enabled)


func get_debug_sky_intensity() -> float:
	return _sky_debug_intensity


func set_debug_ambient_enabled(enabled : bool) -> void:
	_ambient_debug_enabled = enabled
	var environment : Environment = world_environment.environment
	if environment != null:
		environment.ambient_light_energy = (
			_base_ambient_energy * _ambient_debug_intensity if enabled else 0.0
		)


func is_debug_ambient_enabled() -> bool:
	return _ambient_debug_enabled


func set_debug_ambient_intensity(intensity : float) -> void:
	_ambient_debug_intensity = clampf(intensity, 0.0, 2.0)
	set_debug_ambient_enabled(_ambient_debug_enabled)


func get_debug_ambient_intensity() -> float:
	return _ambient_debug_intensity


func set_debug_fog_enabled(enabled : bool) -> void:
	_fog_debug_enabled = enabled
	_apply_quality_level()


func is_debug_fog_enabled() -> bool:
	return _fog_debug_enabled


func set_debug_fog_intensity(intensity : float) -> void:
	_fog_debug_intensity = clampf(intensity, 0.0, 2.0)
	_apply_fog_values()


func get_debug_fog_intensity() -> float:
	return _fog_debug_intensity


func _notify_ufo_quality(particles_allowed : bool) -> void:
	get_tree().call_group(
		UFO_GROUP,
		"set_atmosphere_quality",
		quality_level,
		particles_allowed
	)


func _update_cloud_shadow() -> void:
	var slow_cloud : float = sin(_elapsed * cloud_speed * 2.1 + 0.8) * 0.55
	var broad_cloud : float = sin(_elapsed * cloud_speed * 0.73 + 2.4) * 0.45
	var cloud_cover : float = smoothstep(0.35, 0.92, slow_cloud + broad_cloud)
	moon_light.light_energy = _base_moon_energy * _moon_debug_intensity * (
		1.0 - cloud_cover * cloud_shadow_strength
	)


func _update_ground_atmosphere() -> void:
	var camera : Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var camera_position : Vector3 = camera.global_position
	if atmospheric_particles.visible:
		atmospheric_particles.global_position = Vector3(
			camera_position.x,
			1.6,
			camera_position.z
		)

	if not ground_fog.visible:
		return

	var fog_offset : Vector3 = Vector3(
		sin(_elapsed * fog_drift_speed * 0.11) * 10.0,
		2.2,
		cos(_elapsed * fog_drift_speed * 0.08) * 8.0
	)
	ground_fog.global_position = Vector3(
		camera_position.x,
		0.0,
		camera_position.z
	) + fog_offset


func _update_shooting_stars(delta : float) -> void:
	if not shooting_stars.visible:
		return

	_shooting_star_timer -= delta * motion_scale
	if _shooting_star_timer > 0.0:
		return

	_emit_shooting_star()
	_schedule_shooting_star()


func _emit_shooting_star() -> void:
	var camera : Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	shooting_stars.global_transform = camera.global_transform
	shooting_stars.position += camera.basis * Vector3(
		_rng.randf_range(-26.0, 10.0),
		_rng.randf_range(15.0, 28.0),
		-62.0
	)
	shooting_stars.rotation.z += _rng.randf_range(-0.18, 0.18)
	shooting_stars.restart()


func _schedule_shooting_star() -> void:
	var minimum : float = minf(shooting_star_interval_min, shooting_star_interval_max)
	var maximum : float = maxf(shooting_star_interval_min, shooting_star_interval_max)
	_shooting_star_timer = _rng.randf_range(minimum, maximum)
