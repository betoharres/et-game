extends MeshInstance3D


@export var change_time: float = 4.0
@export var transition_time: float = 1.0

@export var effect_count: int = 9


var current_effect: int = 0
var next_effect: int = 1

var timer: float = 0.0
var transition_timer: float = 0.0

var transitioning: bool = false

@onready var eye_material: ShaderMaterial = surface_material_override/0

func _ready() -> void:
	if eye_material == null:
		push_warning("Spider eye has no ShaderMaterial.")
		return

	eye_material.set_shader_parameter(
		"effect_a",
		current_effect
	)

	eye_material.set_shader_parameter(
		"effect_b",
		next_effect
	)

	eye_material.set_shader_parameter(
		"transition",
		0.0
	)


func _process(delta: float) -> void:
	if eye_material == null:
		return

	if not transitioning:
		timer += delta

		if timer >= change_time:
			timer -= change_time
			_start_transition()

	else:
		transition_timer += delta

		var progress : float = transition_timer / transition_time
		progress = clampf(progress, 0.0, 1.0)

		eye_material.set_shader_parameter(
			"transition",
			progress
		)

		if progress >= 1.0:
			_finish_transition()


func _start_transition() -> void:
	transitioning = true
	transition_timer = 0.0

	next_effect = (
		current_effect + 1
	) % effect_count

	eye_material.set_shader_parameter(
		"effect_a",
		current_effect
	)

	eye_material.set_shader_parameter(
		"effect_b",
		next_effect
	)

	eye_material.set_shader_parameter(
		"transition",
		0.0
	)


func _finish_transition() -> void:
	current_effect = next_effect

	transitioning = false
	transition_timer = 0.0

	eye_material.set_shader_parameter(
		"effect_a",
		current_effect
	)

	eye_material.set_shader_parameter(
		"effect_b",
		current_effect
	)

	eye_material.set_shader_parameter(
		"transition",
		0.0
	)
