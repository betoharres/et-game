extends Area3D

## Farm-side door of the dungeon. Follows the same "player" detection used
## by SpaceShipInterior's descend pad: group "characters" instead of a
## dedicated "player" group. The first touch builds the dungeon layout
## (Dungeon.ensure_generated); every touch after that only teleports, since
## the dungeon caches its own "already generated" state.

@export var dungeon_path : NodePath

@onready var dungeon : Node3D = get_node(dungeon_path)
@onready var prompt : Label3D = $EntryPrompt

var _characters_nearby : Array[CharacterBody3D] = []

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	prompt.visible = false

func _process(_delta : float) -> void:
	_cleanup_characters()
	prompt.visible = not _characters_nearby.is_empty()

	if _characters_nearby.is_empty():
		return

	if Input.is_action_just_pressed("interact"):
		_enter_dungeon()


func _enter_dungeon() -> void:
	if dungeon == null:
		return

	dungeon.call("ensure_generated", global_position)

	var entry_position : Vector3 = dungeon.call("get_entry_global_position")

	for character : CharacterBody3D in _characters_nearby:
		if is_instance_valid(character):
			character.global_position = entry_position
			character.velocity = Vector3.ZERO


func _on_body_entered(body : Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("characters"):
		var character : CharacterBody3D = body as CharacterBody3D
		if not _characters_nearby.has(character):
			_characters_nearby.append(character)


func _on_body_exited(body : Node3D) -> void:
	if body is CharacterBody3D:
		_characters_nearby.erase(body)


func _cleanup_characters() -> void:
	for index : int in range(_characters_nearby.size() - 1, -1, -1):
		if not is_instance_valid(_characters_nearby[index]):
			_characters_nearby.remove_at(index)
