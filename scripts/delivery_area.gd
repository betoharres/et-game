extends Area3D

signal intervention_requested
signal abduction_started(item : RigidBody3D)
signal item_delivered(item_score : int)

enum DeliveryState {
	IDLE,
	CHARGING,
	ABDUCTING,
}

@export var default_score : int = 10
@export_range(0.5, 10.0, 0.1) var signal_hold_duration : float = 3.0
@export_range(1.0, 30.0, 0.5) var abduction_duration : float = 10.0
@export_range(5.0, 60.0, 1.0) var fallback_capture_height : float = 32.0
@export_range(0.0, 10.0, 0.1) var ship_capture_offset : float = 2.8

@onready var signal_marker : Node3D = $SignalMarker
@onready var signal_light : OmniLight3D = $SignalMarker/SignalLight
@onready var abduction_origin : Marker3D = $AbductionOrigin
@onready var abduction_beam : Node3D = $AbductionBeam
@onready var beam_volume : MeshInstance3D = $AbductionBeam/BeamVolume
@onready var beam_spotlight : SpotLight3D = $AbductionBeam/BeamSpotLight
@onready var beam_ground_light : OmniLight3D = (
	$AbductionBeam/BeamGroundLight
)
@onready var prompt_root : Control = $InteractionPrompt/PromptRoot
@onready var key_icon : Label = (
	$InteractionPrompt/PromptRoot/PromptPanel/PromptMargin/PromptContent/KeyIcon
)
@onready var prompt_label : Label = (
	$InteractionPrompt/PromptRoot/PromptPanel/PromptMargin/PromptContent/PromptLabel
)
@onready var hold_progress : ProgressBar = (
	$InteractionPrompt/PromptRoot/PromptPanel/PromptMargin/PromptContent/HoldProgress
)

var _state : int = DeliveryState.IDLE
var _state_elapsed : float = 0.0
var _prompt_elapsed : float = 0.0
var _candidate_items : Array[RigidBody3D] = []
var _nearby_characters : Array[CharacterBody3D] = []
var _target_item : RigidBody3D = null
var _signaling_character : CharacterBody3D = null
var _target_start_position : Vector3
var _ufo : Node3D = null
var _ufo_start_position : Vector3
var _ufo_target_position : Vector3
var _beam_base_energy : float = 8.0
var _beam_ground_base_energy : float = 2.6


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	signal_marker.visible = false
	abduction_beam.visible = false
	prompt_root.visible = false
	hold_progress.max_value = signal_hold_duration


func _process(delta : float) -> void:
	if _state == DeliveryState.ABDUCTING:
		_state_elapsed += delta
		_update_abduction(delta)
		return

	_update_interaction_prompt(delta)


func _on_body_entered(body : Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("pickup_items"):
		var item := body as RigidBody3D
		if not _candidate_items.has(item):
			_candidate_items.append(item)
		return

	if body is CharacterBody3D and body.is_in_group("characters"):
		var character := body as CharacterBody3D
		if not _nearby_characters.has(character):
			_nearby_characters.append(character)


func _on_body_exited(body : Node3D) -> void:
	if body is RigidBody3D:
		_candidate_items.erase(body)
	elif body is CharacterBody3D:
		_nearby_characters.erase(body)


func _update_interaction_prompt(delta : float) -> void:
	_cleanup_tracked_bodies()
	_prompt_elapsed += delta

	var available_item := _find_available_item()
	var available_character := _find_available_character()
	var can_signal := available_item != null and available_character != null
	prompt_root.visible = can_signal

	if not can_signal:
		_cancel_charge()
		return

	_update_key_icon()

	if not Input.is_action_pressed("request_abduction"):
		if _state == DeliveryState.CHARGING:
			_cancel_charge()
		_update_waiting_prompt()
		return

	if _state == DeliveryState.IDLE:
		_begin_charge(available_item, available_character)

	if not _is_charge_still_valid():
		_cancel_charge()
		return

	_state_elapsed = minf(_state_elapsed + delta, signal_hold_duration)
	_update_charge_prompt()
	_update_signal_effect()
	_update_ufo_approach()

	if _state_elapsed >= signal_hold_duration:
		_complete_charge()


func _begin_charge(
	item : RigidBody3D,
	character : CharacterBody3D
) -> void:
	_state = DeliveryState.CHARGING
	_state_elapsed = 0.0
	_target_item = item
	_signaling_character = character
	signal_marker.visible = true
	_set_character_signal_pose(true)
	_prepare_ufo_approach()


func _complete_charge() -> void:
	if _target_item == null or not is_instance_valid(_target_item):
		_cancel_charge()
		return

	if _target_item.has_method("begin_abduction"):
		if not bool(_target_item.call("begin_abduction")):
			_cancel_charge()
			return
	else:
		_target_item.freeze = true
		_target_item.remove_from_group("pickup_items")

	_set_character_signal_pose(false)
	_signaling_character = null
	prompt_root.visible = false
	intervention_requested.emit()
	_start_abduction()


func _cancel_charge() -> void:
	if _state != DeliveryState.CHARGING:
		return

	_set_character_signal_pose(false)
	if _ufo != null and is_instance_valid(_ufo):
		_ufo.global_position = _ufo_start_position

	_state = DeliveryState.IDLE
	_state_elapsed = 0.0
	_target_item = null
	_signaling_character = null
	signal_marker.visible = false
	signal_marker.scale = Vector3.ONE
	hold_progress.value = 0.0


func _is_charge_still_valid() -> bool:
	if _target_item == null or not is_instance_valid(_target_item):
		return false

	if not _candidate_items.has(_target_item):
		return false

	if _signaling_character == null:
		return false

	if not is_instance_valid(_signaling_character):
		return false

	if not _nearby_characters.has(_signaling_character):
		return false

	if _target_item.has_method("is_available_for_abduction"):
		return bool(_target_item.call("is_available_for_abduction"))

	return true


func _find_available_item() -> RigidBody3D:
	var closest_item : RigidBody3D = null
	var closest_distance : float = INF

	for item : RigidBody3D in _candidate_items:
		if not is_instance_valid(item):
			continue

		if item.has_method("is_available_for_abduction"):
			if not bool(item.call("is_available_for_abduction")):
				continue

		var distance := item.global_position.distance_squared_to(
			abduction_origin.global_position
		)
		if distance < closest_distance:
			closest_distance = distance
			closest_item = item

	return closest_item


func _find_available_character() -> CharacterBody3D:
	for character : CharacterBody3D in _nearby_characters:
		if is_instance_valid(character):
			return character

	return null


func _set_character_signal_pose(active : bool) -> void:
	if _signaling_character == null:
		return

	if not is_instance_valid(_signaling_character):
		return

	if _signaling_character.has_method("set_intervention_signal_pose"):
		_signaling_character.call("set_intervention_signal_pose", active)


func _update_key_icon() -> void:
	key_icon.text = _get_action_key("request_abduction")
	if _state == DeliveryState.CHARGING:
		key_icon.modulate.a = 1.0
	else:
		key_icon.modulate.a = 0.6 + sin(_prompt_elapsed * 5.0) * 0.4


func _update_waiting_prompt() -> void:
	prompt_label.text = "SEGURE %s PARA CHAMAR A LUZ" % key_icon.text
	hold_progress.value = 0.0


func _update_charge_prompt() -> void:
	var remaining := maxf(signal_hold_duration - _state_elapsed, 0.0)
	prompt_label.text = "SINAL DE INTERVENÇÃO  %.1f s" % remaining
	hold_progress.value = _state_elapsed


func _get_action_key(action : StringName) -> String:
	for input_event : InputEvent in InputMap.action_get_events(action):
		if input_event is InputEventKey:
			var key_event := input_event as InputEventKey
			var keycode : Key = key_event.physical_keycode
			if keycode == KEY_NONE:
				keycode = key_event.keycode
			return OS.get_keycode_string(keycode)

	return "F"


func _prepare_ufo_approach() -> void:
	_ufo = get_tree().get_first_node_in_group("ufo_lighting") as Node3D
	if _ufo == null:
		return

	_ufo_start_position = _ufo.global_position
	_ufo_target_position = Vector3(
		abduction_origin.global_position.x,
		_ufo_start_position.y,
		abduction_origin.global_position.z
	)
	if _ufo.has_method("configure_external_beam"):
		_ufo.call(
			"configure_external_beam",
			beam_spotlight,
			beam_ground_light,
			beam_volume
		)
		_beam_base_energy = beam_spotlight.light_energy
		_beam_ground_base_energy = beam_ground_light.light_energy


func _update_signal_effect() -> void:
	var pulse := 1.0 + sin(_state_elapsed * TAU * 2.0) * 0.14
	signal_marker.scale = Vector3.ONE * pulse
	signal_light.light_energy = 3.0 + pulse * 2.0


func _update_ufo_approach() -> void:
	if _ufo == null or not is_instance_valid(_ufo):
		return

	var progress := clampf(_state_elapsed / signal_hold_duration, 0.0, 1.0)
	var eased_progress := ease(progress, -2.0)
	_ufo.global_position = _ufo_start_position.lerp(
		_ufo_target_position,
		eased_progress
	)


func _start_abduction() -> void:
	if _target_item == null or not is_instance_valid(_target_item):
		_reset_sequence()
		return

	_state = DeliveryState.ABDUCTING
	_state_elapsed = 0.0
	signal_marker.visible = false
	abduction_beam.visible = true
	_target_start_position = _target_item.global_position
	_configure_beam()
	abduction_started.emit(_target_item)


func _configure_beam() -> void:
	var origin := abduction_origin.global_position
	var capture_position := _get_capture_position()
	var beam_height := maxf(capture_position.y - origin.y, 1.0)

	beam_volume.global_position = origin + Vector3.UP * beam_height * 0.5
	beam_volume.global_rotation = Vector3.ZERO
	beam_volume.scale = Vector3(1.0, beam_height, 1.0)

	beam_spotlight.global_position = capture_position
	beam_spotlight.global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	beam_spotlight.spot_range = beam_height + 4.0
	beam_ground_light.global_position = origin + Vector3.UP * 0.5


func _update_abduction(delta : float) -> void:
	if _target_item == null or not is_instance_valid(_target_item):
		_reset_sequence()
		return

	var progress := clampf(_state_elapsed / abduction_duration, 0.0, 1.0)
	var lift_progress := smoothstep(0.0, 1.0, progress)
	var capture_position := _get_capture_position()
	var item_position := _target_start_position.lerp(
		capture_position,
		lift_progress
	)
	var wobble_strength := sin(progress * PI) * 0.22
	item_position.x += sin(_state_elapsed * 2.4) * wobble_strength
	item_position.z += cos(_state_elapsed * 2.1) * wobble_strength
	_target_item.global_position = item_position
	_target_item.rotate_y(delta * 1.8)
	_target_item.rotate_x(delta * 0.7)

	var beam_pulse := 1.0 + sin(_state_elapsed * 7.0) * 0.05
	beam_volume.scale.x = beam_pulse
	beam_volume.scale.z = beam_pulse
	beam_spotlight.light_energy = _beam_base_energy * beam_pulse
	beam_ground_light.light_energy = _beam_ground_base_energy * beam_pulse

	if progress >= 1.0:
		_finish_delivery()


func _get_capture_position() -> Vector3:
	if _ufo != null and is_instance_valid(_ufo):
		return _ufo.global_position + Vector3.DOWN * ship_capture_offset

	return (
		abduction_origin.global_position
		+ Vector3.UP * fallback_capture_height
	)


func _finish_delivery() -> void:
	var item_score : int = default_score
	var score_value : Variant = _target_item.get("score_value")
	if score_value != null:
		item_score = int(score_value)

	GlobalScore.add_score(item_score)
	_target_item.queue_free()
	_target_item = null
	item_delivered.emit(item_score)
	_reset_sequence()


func _reset_sequence() -> void:
	_set_character_signal_pose(false)
	_state = DeliveryState.IDLE
	_state_elapsed = 0.0
	_signaling_character = null
	signal_marker.visible = false
	signal_marker.scale = Vector3.ONE
	abduction_beam.visible = false
	prompt_root.visible = false
	hold_progress.value = 0.0


func _cleanup_tracked_bodies() -> void:
	for index : int in range(_candidate_items.size() - 1, -1, -1):
		if not is_instance_valid(_candidate_items[index]):
			_candidate_items.remove_at(index)

	for index : int in range(_nearby_characters.size() - 1, -1, -1):
		if not is_instance_valid(_nearby_characters[index]):
			_nearby_characters.remove_at(index)
