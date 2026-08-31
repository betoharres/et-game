extends Node3D

## Interior of the UFO: crew quarters, control room, and a central
## hatch/lift pad the player uses to descend back to the surface.
##
## The scene is pure geometry plus the pad: it does not decide where the pad
## leads. Stepping on it only emits descend_requested, and whoever owns the
## ship (see scripts/space/alien_ship.gd) runs the actual descent. That is what
## lets the same interior serve both ends of the flow -- parked in orbit, where
## the pad must stay inert until a mission is picked, and anchored above a fase,
## where it fires the arrival beam.
##
## The pad follows the same "player" detection used everywhere else in the
## project: group "characters" instead of a dedicated "player" group.

signal descend_requested

@onready var descend_trigger : Area3D = $DescendPad/DescendTrigger
@onready var descend_prompt : Label3D = $DescendPad/DescendPrompt

var _descend_trigger_enabled : bool = false
var _activate_on_enter : bool = false
var _characters_on_pad : Array[CharacterBody3D] = []


func _ready() -> void:
	descend_trigger.body_entered.connect(_on_pad_body_entered)
	descend_trigger.body_exited.connect(_on_pad_body_exited)
	descend_prompt.visible = false


func _process(_delta : float) -> void:
	_cleanup_tracked_characters()

	var character_on_pad : bool = (
		_descend_trigger_enabled and not _characters_on_pad.is_empty()
	)
	descend_prompt.visible = character_on_pad and not _activate_on_enter

	if (
		character_on_pad
		and not _activate_on_enter
		and Input.is_action_just_pressed("interact")
	):
		_request_descend()


## Arms/disarms the pad. `activate_on_enter` is used by the orbital transport
## beam, while a ship parked above a fase keeps the explicit interaction.
func set_descend_trigger_enabled(
	enabled : bool,
	activate_on_enter : bool = false
) -> void:
	_descend_trigger_enabled = enabled
	_activate_on_enter = enabled and activate_on_enter
	if not enabled:
		descend_prompt.visible = false
	elif _activate_on_enter:
		call_deferred("_request_descend_if_character_present")


func _on_pad_body_entered(body : Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("characters"):
		var character : CharacterBody3D = body as CharacterBody3D
		if not _characters_on_pad.has(character):
			_characters_on_pad.append(character)
		if _descend_trigger_enabled and _activate_on_enter:
			_request_descend()


func _on_pad_body_exited(body : Node3D) -> void:
	if body is CharacterBody3D:
		_characters_on_pad.erase(body)


func _cleanup_tracked_characters() -> void:
	for index : int in range(_characters_on_pad.size() - 1, -1, -1):
		if not is_instance_valid(_characters_on_pad[index]):
			_characters_on_pad.remove_at(index)


func _request_descend_if_character_present() -> void:
	_cleanup_tracked_characters()
	if _descend_trigger_enabled and not _characters_on_pad.is_empty():
		_request_descend()


func _request_descend() -> void:
	# Disarms immediately: while the owner changes scene or plays the descent,
	# remaining inside the pad must not fire a second request.
	set_descend_trigger_enabled(false)
	descend_requested.emit()
