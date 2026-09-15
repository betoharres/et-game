extends Node3D

signal quest_started
signal quest_completed(reward: RigidBody3D)

@export var interact_radius: float = 2.8
@export var requested_item_id: String = "banana_box"
@export var rewards: Array[PackedScene] = []
@export var reward_marker_path: NodePath = NodePath("../RewardSpawn")
@export var label_path: NodePath = NodePath("../QuestLabel")

var accepted: bool = false
var completed: bool = false
var _release_at: int = 0

@onready var _label: Label3D = get_node(label_path) as Label3D
@onready var _reward_marker: Marker3D = get_node(reward_marker_path) as Marker3D


func _ready() -> void:
	add_to_group(&"dialogue_sources")
	# O jogador já arbitra este grupo antes de coletar ou largar um item.
	add_to_group(&"house_doors")
	_label.text = "!\nPé-Grande — Bananas por destroços"


func _process(_delta: float) -> void:
	if completed or not Input.is_action_just_pressed("interact"):
		return
	var character: Node3D = _nearby_player()
	if character != null:
		interact(character)


func _nearby_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group(&"characters"):
		var character: Node3D = node as Node3D
		if character != null and reserves_interaction_for(character):
			return character
	return null


func is_player_nearby() -> bool:
	return not completed and _nearby_player() != null


func reserves_interaction_for(character: Node3D) -> bool:
	if completed and Time.get_ticks_msec() >= _release_at:
		return false
	if not character.is_in_group(&"characters") or not character.has_node("ExplorationInventory"):
		return false
	if bool(character.get("_movement_locked")):
		return false
	return global_position.distance_squared_to(character.global_position) <= interact_radius * interact_radius


func interact(character: Node3D) -> void:
	if completed or not reserves_interaction_for(character):
		return
	if not accepted:
		accepted = true
		_label.text = "Ei, ET! Traga uma caixa de bananas.\nEu troco por um destroço de nave!\nColete a caixa e volte para falar comigo."
		quest_started.emit()
		return
	var banana: RigidBody3D = _find_banana(character)
	if banana == null:
		_label.text = "Ainda estou com fome, ET!\nTraga uma caixa de bananas no inventário."
		return
	if rewards.is_empty():
		_label.text = "Estou sem destroços para trocar agora."
		return
	var reward_scene: PackedScene = rewards.pick_random()
	if reward_scene == null:
		return
	var reward: RigidBody3D = reward_scene.instantiate() as RigidBody3D
	if reward == null:
		return
	completed = true
	# Mantém a reserva até passar o toque que concluiu a troca.
	_release_at = Time.get_ticks_msec() + 300
	get_tree().current_scene.add_child(reward)
	reward.global_position = _reward_marker.global_position
	reward.collision_layer = 8
	banana.queue_free()
	_label.text = "Obrigado pelas bananas, ET!\nSeu destroço está aqui ao lado."
	quest_completed.emit(reward)


func _find_banana(character: Node3D) -> RigidBody3D:
	var inventory: Node = character.get_node("ExplorationInventory")
	var items: Array = inventory.get("items")
	for item: RigidBody3D in items:
		if is_instance_valid(item) and not item.is_queued_for_deletion() and str(item.get("item_id")) == requested_item_id:
			return item
	var carried: RigidBody3D = character.get("carried_item") as RigidBody3D
	if is_instance_valid(carried) and str(carried.get("item_id")) == requested_item_id:
		return carried
	return null
