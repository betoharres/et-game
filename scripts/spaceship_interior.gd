extends Node3D

## Interior of the UFO: crew quarters, control room, and a central
## hatch/lift pad the player uses to descend back to the surface.

const EXIT_SCENE_PATH : String = "res://scenes/world.tscn"

@onready var descend_trigger : Area3D = $CentralHall/DescendPad/DescendTrigger
@onready var descend_prompt : Label3D = $CentralHall/DescendPad/DescendPrompt

var _characters_on_pad : Array[CharacterBody3D] = []


func _ready() -> void:
	descend_trigger.body_entered.connect(_on_pad_body_entered)
	descend_trigger.body_exited.connect(_on_pad_body_exited)
	descend_prompt.visible = false


func _process(_delta : float) -> void:
	_cleanup_tracked_characters()
	descend_prompt.visible = not _characters_on_pad.is_empty()

	if _characters_on_pad.is_empty():
		return

	if Input.is_action_just_pressed("interact"):
		SceneTransition.warp_to(EXIT_SCENE_PATH)


func _on_pad_body_entered(body : Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("characters"):
		var character : CharacterBody3D = body as CharacterBody3D
		if not _characters_on_pad.has(character):
			_characters_on_pad.append(character)


func _on_pad_body_exited(body : Node3D) -> void:
	if body is CharacterBody3D:
		_characters_on_pad.erase(body)


func _cleanup_tracked_characters() -> void:
	for index : int in range(_characters_on_pad.size() - 1, -1, -1):
		if not is_instance_valid(_characters_on_pad[index]):
			_characters_on_pad.remove_at(index)
