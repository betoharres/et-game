class_name ArrivalBeam
extends Node3D

## Tractor-beam visual used for the fase's arrival intro. Same shader/recipe
## as DeliveryArea's AbductionBeam, kept as a standalone reusable effect.

const SPOT_LIGHT_ENERGY : float = 5.2
const GROUND_LIGHT_ENERGY : float = 1.6
const CORE_LIGHT_ENERGY : float = 1.5

@onready var beam_volume : MeshInstance3D = $BeamVolume
@onready var beam_core : MeshInstance3D = $BeamCore
@onready var spot_light : SpotLight3D = $BeamSpotLight
@onready var ground_light : OmniLight3D = $BeamGroundLight
@onready var core_light : OmniLight3D = $BeamCoreLight


func configure(origin : Vector3, height : float) -> void:
	var mid_point : Vector3 = origin + Vector3.UP * height * 0.5
	beam_volume.global_position = mid_point
	beam_volume.scale = Vector3(1.0, height, 1.0)
	beam_core.global_position = mid_point
	beam_core.scale = Vector3(1.0, height, 1.0)

	spot_light.global_position = origin + Vector3.UP * height
	spot_light.global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	spot_light.spot_range = height + 4.0
	spot_light.light_energy = SPOT_LIGHT_ENERGY

	ground_light.global_position = origin + Vector3.UP * 0.5
	ground_light.light_energy = GROUND_LIGHT_ENERGY

	core_light.global_position = origin + Vector3.UP * clampf(height * 0.16, 0.4, 2.5)
	core_light.light_energy = CORE_LIGHT_ENERGY

	visible = true


func fade_out(duration : float) -> void:
	var tween : Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(spot_light, "light_energy", 0.0, duration)
	tween.tween_property(ground_light, "light_energy", 0.0, duration)
	tween.tween_property(core_light, "light_energy", 0.0, duration)
	await tween.finished
	queue_free()
