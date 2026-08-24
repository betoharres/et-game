class_name AlienIncidentPostProcess
extends CanvasLayer

const SOURCE_GROUP : StringName = &"alien_interference_sources"

@export_group("Base Look")
@export_range(0.0, 0.08, 0.001) var grain_amount : float = 0.024
@export_range(0.0, 0.5, 0.01) var vignette_amount : float = 0.20
@export_range(0.0, 0.004, 0.0001) var chromatic_aberration : float = 0.0010
@export_range(0.0, 0.3, 0.01) var cool_shadow_amount : float = 0.15
@export_range(0.8, 1.3, 0.01) var contrast : float = 1.07
@export_range(0.0, 0.08, 0.001) var black_lift : float = 0.018

@export_group("Alien Interference")
@export_range(0.5, 20.0, 0.5) var interference_response : float = 7.0
@export_range(0.0, 1.0, 0.01) var global_interference_scale : float = 1.0

@onready var screen_filter : ColorRect = $ScreenFilter

var _material : ShaderMaterial
var _current_interference : float = 0.0
var _manual_interference : float = 0.0
var _pulse_strength : float = 0.0
var _pulse_duration : float = 0.0
var _pulse_elapsed : float = 0.0


func _ready() -> void:
	_material = screen_filter.material.duplicate() as ShaderMaterial
	screen_filter.material = _material
	_apply_base_parameters()


func _process(delta : float) -> void:
	var target : float = _sample_spatial_interference()
	target = maxf(target, _manual_interference)
	target = maxf(target, _update_pulse(delta))
	target = clampf(target * global_interference_scale, 0.0, 1.0)
	var response_weight : float = 1.0 - exp(-interference_response * delta)
	_current_interference = lerpf(
		_current_interference,
		target,
		response_weight
	)
	if _material != null:
		_material.set_shader_parameter(
			"interference_intensity",
			_current_interference
		)


func set_manual_interference(intensity_value : float) -> void:
	_manual_interference = clampf(intensity_value, 0.0, 1.0)


func clear_manual_interference() -> void:
	_manual_interference = 0.0


func pulse_interference(strength : float = 0.8, duration : float = 0.6) -> void:
	_pulse_strength = clampf(strength, 0.0, 1.0)
	_pulse_duration = maxf(duration, 0.01)
	_pulse_elapsed = 0.0


func get_interference_intensity() -> float:
	return _current_interference


func _sample_spatial_interference() -> float:
	var camera : Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return 0.0

	var combined : float = 0.0
	for source : Node in get_tree().get_nodes_in_group(SOURCE_GROUP):
		if not source.has_method("get_interference_at"):
			continue
		var contribution : float = clampf(
			float(source.call("get_interference_at", camera.global_position)),
			0.0,
			1.0
		)
		combined = 1.0 - (1.0 - combined) * (1.0 - contribution)
	return combined


func _update_pulse(delta : float) -> float:
	if _pulse_elapsed >= _pulse_duration:
		return 0.0
	_pulse_elapsed += delta
	var ratio : float = clampf(_pulse_elapsed / _pulse_duration, 0.0, 1.0)
	return _pulse_strength * sin(ratio * PI) * (1.0 - ratio * 0.35)


func _apply_base_parameters() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("grain_amount", grain_amount)
	_material.set_shader_parameter("vignette_amount", vignette_amount)
	_material.set_shader_parameter(
		"chromatic_aberration",
		chromatic_aberration
	)
	_material.set_shader_parameter("cool_shadow_amount", cool_shadow_amount)
	_material.set_shader_parameter("contrast", contrast)
	_material.set_shader_parameter("black_lift", black_lift)
