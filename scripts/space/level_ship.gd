extends Node3D

signal descend_requested
signal return_to_orbit_requested

@export var return_action: StringName = &"return_to_orbit"

@onready var interior: Node3D = $Interior
@onready var spawn_point: Marker3D = $SpawnPoint
@onready var interior_ambience: AudioStreamPlayer = $ShipAudio/InteriorAmbience
@onready var movement_hum: AudioStreamPlayer = $ShipAudio/MovementHum
@onready var heavy_engine: AudioStreamPlayer = $ShipAudio/HeavyEngine
@onready var return_field: Area3D = $ReturnField
@onready var return_prompt: Label3D = $ReturnPrompt

var _beam_action_enabled: bool = true


func _ready() -> void:
	add_to_group("level_ships")
	interior.descend_requested.connect(func() -> void: descend_requested.emit())
	interior.call("set_descend_action", return_action)
	return_field.body_entered.connect(_on_return_field_body_entered)
	return_field.body_exited.connect(_on_return_field_body_exited)
	return_prompt.visible = false
	_set_return_field_enabled(true)
	_set_mp3_loop_enabled(interior_ambience.stream)
	interior_ambience.play()


func _unhandled_input(event: InputEvent) -> void:
	if not _beam_action_enabled or not event.is_action_pressed(return_action) or event.is_echo():
		return
	var character: CharacterBody3D = _get_character_near_ship()
	if character == null or bool(character.get("_movement_locked")):
		return
	for station: Node in get_tree().get_nodes_in_group("upgrade_stations"):
		if station.has_method("is_open") and bool(station.call("is_open")):
			return
	if bool(interior.call("is_player_inside", character)):
		interior.call("request_descend")
	elif return_field.overlaps_body(character):
		return_to_orbit_requested.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func set_player_inside(character: CharacterBody3D, inside: bool) -> void:
	var camera_rig: CinematicCameraRig = character.get("camera_pivot") as CinematicCameraRig
	if camera_rig != null:
		camera_rig.set_interior_camera_mode(inside)


func begin_approach_audio(_ramp_duration: float) -> void:
	movement_hum.play()
	heavy_engine.play()


func end_approach_audio(_fade_duration: float) -> void:
	heavy_engine.stop()


func set_descend_trigger_enabled(enabled: bool) -> void:
	_beam_action_enabled = enabled
	interior.set_descend_trigger_enabled(enabled)


func set_fall_guard_enabled(_enabled: bool) -> void:
	pass


func _on_return_field_body_entered(body: Node3D) -> void:
	if body.is_in_group("characters"):
		return_prompt.visible = true


func _on_return_field_body_exited(body: Node3D) -> void:
	if body.is_in_group("characters"):
		return_prompt.visible = false


func _get_character_near_ship() -> CharacterBody3D:
	for body: Node in get_tree().get_nodes_in_group("characters"):
		if body is not CharacterBody3D:
			continue
		var character: CharacterBody3D = body as CharacterBody3D
		if bool(interior.call("is_player_inside", character)) or return_field.overlaps_body(character):
			return character
	return null


func _set_return_field_enabled(enabled: bool) -> void:
	return_field.monitoring = enabled
	return_field.collision_layer = 0
	return_field.collision_mask = 1


func _set_mp3_loop_enabled(stream: AudioStream) -> void:
	var mp3_stream: AudioStreamMP3 = stream as AudioStreamMP3
	if mp3_stream != null:
		mp3_stream.loop = true
