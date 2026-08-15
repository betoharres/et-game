extends Node

const DIRT_STEPS : Array[AudioStream] = [
	preload("res://assets/audio/footsteps/dirt/step_1.wav"),
	preload("res://assets/audio/footsteps/dirt/step_2.wav"),
	preload("res://assets/audio/footsteps/dirt/step_3.wav"),
	preload("res://assets/audio/footsteps/dirt/step_4.wav")
]
const STONE_STEPS : Array[AudioStream] = [
	preload("res://assets/audio/footsteps/stone/step_1.wav"),
	preload("res://assets/audio/footsteps/stone/step_2.wav"),
	preload("res://assets/audio/footsteps/stone/step_3.wav"),
	preload("res://assets/audio/footsteps/stone/step_4.wav")
]
const WOOD_STEPS : Array[AudioStream] = [
	preload("res://assets/audio/footsteps/wood/step_1.wav"),
	preload("res://assets/audio/footsteps/wood/step_2.wav")
]

const WOOD_SURFACE_NAMES : Array[String] = [
	"farmhouse", "barn", "shelter", "wood", "porch", "floor"
]
const STONE_SURFACE_NAMES : Array[String] = [
	"concrete", "garage", "road", "stone", "gravel", "sidewalk"
]

var _audio_player : AudioStreamPlayer
var _horizontal_speed : float = 0.0
var _grounded : bool = true
var _step_elapsed : float = 0.0
var _last_step_by_surface : Dictionary = {}
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "StepPlayer"
	_audio_player.volume_db = -10.0
	_audio_player.max_polyphony = 2
	add_child(_audio_player)


func set_motion(horizontal_speed : float, grounded : bool) -> void:
	_horizontal_speed = horizontal_speed
	_grounded = grounded


func _physics_process(delta : float) -> void:
	var character := get_parent()
	var can_step : bool = (
		character.is_physics_processing()
		and _grounded
		and _horizontal_speed > 0.45
	)

	if not can_step:
		_step_elapsed = minf(_step_elapsed, 0.12)
		return

	var speed_ratio : float = clampf((_horizontal_speed - 2.0) / 5.0, 0.0, 1.0)
	var interval : float = lerpf(0.55, 0.32, speed_ratio)
	_step_elapsed += delta

	if _step_elapsed < interval:
		return

	_step_elapsed = fmod(_step_elapsed, interval)
	_play_step(_get_surface())


func _play_step(surface : String) -> void:
	var samples : Array[AudioStream] = _get_samples(surface)

	if samples.is_empty():
		return

	var previous : int = int(_last_step_by_surface.get(surface, -1))
	var index : int = _random.randi_range(0, samples.size() - 1)

	if samples.size() > 1 and index == previous:
		index = (index + 1) % samples.size()

	_last_step_by_surface[surface] = index
	_audio_player.stream = samples[index]
	_audio_player.pitch_scale = _random.randf_range(0.94, 1.06)
	_audio_player.play()


func _get_samples(surface : String) -> Array[AudioStream]:
	match surface:
		"wood":
			return WOOD_STEPS
		"stone":
			return STONE_STEPS
		_:
			return DIRT_STEPS


func _get_surface() -> String:
	var character := get_parent() as CollisionObject3D

	if character == null:
		return "dirt"

	var from : Vector3 = character.global_position + Vector3.UP * 0.35
	var to : Vector3 = character.global_position + Vector3.DOWN * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [character.get_rid()]
	query.collide_with_areas = false

	var hit : Dictionary = character.get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return "dirt"

	var collider := hit.get("collider") as Node
	var surface_name : String = _get_hierarchy_name(collider)

	for token in WOOD_SURFACE_NAMES:
		if surface_name.contains(token):
			return "wood"

	for token in STONE_SURFACE_NAMES:
		if surface_name.contains(token):
			return "stone"

	return "dirt"


func _get_hierarchy_name(start_node : Node) -> String:
	var names : Array[String] = []
	var current : Node = start_node

	for _level in range(5):
		if current == null:
			break

		names.append(current.name.to_lower())
		current = current.get_parent()

	return " ".join(names)
