class_name LevelExit
extends Node3D

const GAME_PROGRESS = preload("res://scripts/levels/game_progress.gd")
const MISSION_FLOW = preload("res://scripts/levels/mission_flow.gd")

@export_range(1.0, 5.0, 0.1) var interaction_radius: float = 4.0
var _traveling: bool = false


func _ready() -> void:
	add_to_group("level_exits")
	$"../ExitPad".body_entered.connect(_on_pad_entered)
	$"../ExitPad".body_exited.connect(_on_pad_exited)


func reserves_interaction_for(character: Node3D) -> bool:
	return character != null and global_position.distance_squared_to(character.global_position) <= interaction_radius * interaction_radius


func get_interaction_prompt(character: Node3D) -> String:
	if reserves_interaction_for(character) and _inside_ship(character):
		return "[E] Retornar à nave"
	return ""


func _input(event: InputEvent) -> void:
	if _traveling or get_tree().paused or not event.is_action_pressed("interact") or event.is_echo():
		return
	for candidate: Node in get_tree().get_nodes_in_group("players"):
		var player: Node3D = candidate as Node3D
		if player == null or not _inside_ship(player):
			continue
		if bool(player.get("carried_item")):
			return
		var inventory: Node = player.get_node_or_null("ExplorationInventory")
		if inventory != null:
			inventory.call("drop_last", player)
		_traveling = true
		if player.has_method("set_movement_locked"):
			player.call("set_movement_locked", true)
		MISSION_FLOW.ship_oxygen_remaining = GAME_PROGRESS.ship_oxygen_seconds
		var transition: Node = get_node("/root/SceneTransition")
		transition.warp_to("res://scenes/Space/Orbit.tscn", Color.BLACK)
		get_viewport().set_input_as_handled()
		return


func _inside_ship(player: Node3D) -> bool:
	return $"../ExitPad".overlaps_body(player)


func _on_pad_entered(body: Node3D) -> void:
	var prompt: Label3D = get_node_or_null("../ExitPrompt") as Label3D
	if prompt != null:
		prompt.visible = body.is_in_group("players") and not _traveling


func _on_pad_exited(body: Node3D) -> void:
	if not body.is_in_group("players"):
		return
	var prompt: Label3D = get_node_or_null("../ExitPrompt") as Label3D
	if prompt != null:
		prompt.visible = false
