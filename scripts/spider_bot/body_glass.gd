extends MeshInstance3D

@export var cycle_time : float = 10.0

var effect_mode : float = 0.0
var timer : float = 0.0

@onready var mat: ShaderMaterial = material_override


func _process(delta: float) -> void:
	if material_override != null:
		timer += delta

		if timer >= cycle_time:
			timer -= cycle_time

			effect_mode += 1.0

			if effect_mode >= 5.0:
				effect_mode = 0.0

			mat.set_shader_parameter(
				"effect_mode",
				effect_mode
			)
