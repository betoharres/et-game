extends Node3D

@onready var light1 : OmniLight3D = $OmniLight3D
@onready var light2 : OmniLight3D = $OmniLight3D2
@onready var light3 : OmniLight3D = $OmniLight3D3

var base_energy : float = 1.0
var target_energy : float = 1.0

func _ready() -> void:
	base_energy = light1.light_energy
	base_energy = light2.light_energy
	base_energy = light3.light_energy
	randomize_energy()

func _process(delta: float) -> void:
	shift_energy(light1, delta)
	shift_energy(light2, delta)
	shift_energy(light3, delta)

func randomize_energy() -> void:
	target_energy = randf_range(base_energy - 0.3, base_energy + 0.3)

func shift_energy(in_light : OmniLight3D, in_delta : float) -> void:
	# Smoothly shift current energy to the target energy
	in_light.light_energy = lerp(in_light.light_energy, target_energy, in_delta * 10.0)

	# Pick a new target when close enough
	if abs(in_light.light_energy - target_energy) < 0.05:
		randomize_energy()
