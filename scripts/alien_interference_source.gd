class_name AlienInterferenceSource
extends Node3D

## Reusable spatial source sampled by AlienIncidentPostProcess. It deliberately
## avoids physics layers: any ship, beam or event can add this lightweight node.

@export var enabled : bool = true
@export_range(0.0, 30.0, 0.5) var full_strength_radius : float = 4.0
@export_range(1.0, 80.0, 0.5) var fade_radius : float = 18.0
@export_range(0.0, 1.0, 0.01) var intensity : float = 0.7
@export_range(0.0, 0.25, 0.01) var pulse_amount : float = 0.06
@export_range(0.0, 5.0, 0.05) var pulse_frequency : float = 0.45


func get_interference_at(world_position : Vector3) -> float:
	if not enabled or not is_visible_in_tree():
		return 0.0

	var inner_radius := minf(full_strength_radius, fade_radius)
	var outer_radius := maxf(fade_radius, inner_radius + 0.001)
	var distance := global_position.distance_to(world_position)
	var proximity := 1.0 - smoothstep(inner_radius, outer_radius, distance)
	if proximity <= 0.0:
		return 0.0

	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.001 * pulse_frequency * TAU) * pulse_amount
	return clampf(intensity * proximity * pulse, 0.0, 1.0)


func set_interference_enabled(value : bool) -> void:
	enabled = value


func is_interference_enabled() -> bool:
	return enabled
