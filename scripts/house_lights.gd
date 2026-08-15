extends Node3D

@export_color_no_alpha var window_light_color : Color = Color(1.0, 0.61, 0.28)
@export_range(0.0, 4.0, 0.01) var window_light_energy : float = 0.55
@export_range(0.0, 0.15, 0.005) var flicker_amount : float = 0.025
@export_range(0.0, 4.0, 0.01) var flicker_speed : float = 0.42
@export_range(1.0, 20.0, 0.5) var light_range : float = 6.5
@export var shadow_light_indices : PackedInt32Array = PackedInt32Array([0, 3])

var _window_lights : Array[OmniLight3D] = []
var _elapsed : float = 0.0


func _ready() -> void:
	for child : Node in find_children("*", "OmniLight3D", true, false):
		var light := child as OmniLight3D
		if light == null:
			continue
		light.light_color = window_light_color
		light.light_energy = window_light_energy
		light.omni_range = light_range
		light.shadow_enabled = shadow_light_indices.has(_window_lights.size())
		light.light_volumetric_fog_energy = 0.08
		_window_lights.append(light)


func _process(delta : float) -> void:
	_elapsed += delta
	for index : int in range(_window_lights.size()):
		var phase := float(index) * 1.91
		var slow_wave := sin(_elapsed * flicker_speed + phase)
		var secondary_wave := sin(_elapsed * flicker_speed * 0.37 + phase * 0.6)
		var variation := (slow_wave * 0.65 + secondary_wave * 0.35) * flicker_amount
		_window_lights[index].light_energy = window_light_energy * (1.0 + variation)
