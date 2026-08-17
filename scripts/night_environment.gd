extends Node3D

enum QualityLevel {
	LOW,
	MEDIUM,
	HIGH,
}

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
@export_color_no_alpha var fog_color : Color = Color(0.1, 0.18, 0.32)
@export_range(0.0, 0.05, 0.001) var ground_fog_density : float = 0.018
@export_range(0.0, 2.0, 0.01) var fog_drift_speed : float = 0.18
@export_range(0, 256, 1) var atmospheric_particle_amount : int = 96

@onready var world_environment : WorldEnvironment = $WorldEnvironment
@onready var moon_visual : Node3D = $SkyController/MoonVisual
@onready var moon_light : DirectionalLight3D = $SkyController/MoonVisual/MoonLight
@onready var shooting_stars : GPUParticles3D = $ShootingStars
@onready var atmospheric_particles : GPUParticles3D = $AtmosphericParticles
@onready var ground_fog : FogVolume = $GroundFog

var _rng := RandomNumberGenerator.new()
var _sky_material : ShaderMaterial
var _base_moon_energy : float = 0.0
var _base_background_energy : float = 1.0
var _base_ambient_energy : float = 0.0
var _base_volumetric_fog_density : float = 0.0
var _moon_debug_enabled : bool = true
var _sky_debug_enabled : bool = true
var _ambient_debug_enabled : bool = true
var _fog_debug_enabled : bool = true
var _moon_debug_intensity : float = 1.0
var _sky_debug_intensity : float = 1.0
var _ambient_debug_intensity : float = 1.0
var _fog_debug_intensity : float = 1.0
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
		if environment.sky != null:
			_sky_material = environment.sky.sky_material as ShaderMaterial

	_apply_inspector_settings()
	_apply_quality_level()
	_schedule_shooting_star()


func _process(delta : float) -> void:
	_elapsed += delta * motion_scale
	_update_cloud_shadow()
	_update_ground_atmosphere()
	_update_shooting_stars(delta)


func _apply_inspector_settings() -> void:
	var normalized_moon_direction := moon_direction.normalized()
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

	var fog_material := ground_fog.material as FogMaterial
	if fog_material != null:
		fog_material.albedo = fog_color
		fog_material.density = ground_fog_density * _fog_debug_intensity
	var environment := world_environment.environment
	if environment != null:
		environment.volumetric_fog_density = (
			_base_volumetric_fog_density * _fog_debug_intensity
		)


func _apply_quality_level() -> void:
	var use_particles := particles_enabled and quality_level != QualityLevel.LOW
	var use_fog := (
		ground_fog_enabled
		and quality_level != QualityLevel.LOW
		and _fog_debug_enabled
	)
	shooting_stars.visible = use_particles
	atmospheric_particles.visible = use_particles
	atmospheric_particles.emitting = use_particles
	atmospheric_particles.amount = (
		atmospheric_particle_amount
		if quality_level == QualityLevel.HIGH
		else maxi(1, atmospheric_particle_amount / 2)
	)
	ground_fog.visible = use_fog
	world_environment.environment.volumetric_fog_enabled = use_fog
	_notify_ufo_quality.call_deferred(use_particles)


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
	var environment := world_environment.environment
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
	var environment := world_environment.environment
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
	var fog_material := ground_fog.material as FogMaterial
	if fog_material != null:
		fog_material.density = ground_fog_density * _fog_debug_intensity
	var environment := world_environment.environment
	if environment != null:
		environment.volumetric_fog_density = (
			_base_volumetric_fog_density * _fog_debug_intensity
		)


func get_debug_fog_intensity() -> float:
	return _fog_debug_intensity


func _notify_ufo_quality(particles_allowed : bool) -> void:
	get_tree().call_group(
		"ufo_lighting",
		"set_atmosphere_quality",
		quality_level,
		particles_allowed
	)


func _update_cloud_shadow() -> void:
	var slow_cloud := sin(_elapsed * cloud_speed * 2.1 + 0.8) * 0.55
	var broad_cloud := sin(_elapsed * cloud_speed * 0.73 + 2.4) * 0.45
	var cloud_cover := smoothstep(0.35, 0.92, slow_cloud + broad_cloud)
	moon_light.light_energy = _base_moon_energy * _moon_debug_intensity * (
		1.0 - cloud_cover * cloud_shadow_strength
	)


func _update_ground_atmosphere() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var camera_position := camera.global_position
	atmospheric_particles.global_position = Vector3(
		camera_position.x,
		1.6,
		camera_position.z
	)
	var fog_offset := Vector3(
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
	if not particles_enabled or quality_level == QualityLevel.LOW:
		return

	_shooting_star_timer -= delta * motion_scale
	if _shooting_star_timer > 0.0:
		return

	_emit_shooting_star()
	_schedule_shooting_star()


func _emit_shooting_star() -> void:
	var camera := get_viewport().get_camera_3d()
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
	var minimum := minf(shooting_star_interval_min, shooting_star_interval_max)
	var maximum := maxf(shooting_star_interval_min, shooting_star_interval_max)
	_shooting_star_timer = _rng.randf_range(minimum, maximum)
