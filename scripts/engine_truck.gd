extends Node3D

@export var scrap_scene: PackedScene = preload("res://scenes/Spaceship_Scraps4.tscn")
@export var interaction_distance: float = 2.5
@export var scrap_spawn_offset: Vector3 = Vector3(1.7, 0.8, 2.0)

@onready var engine: MeshInstance3D = $SM_Veh_Pickup_01_Engine
@onready var hood: MeshInstance3D = $SM_Veh_Pickup_01_Hood

var stolen: bool = false
var open: bool = false


func _ready() -> void:
	add_to_group("engine_trucks")


func can_interact(character: Node3D) -> bool:
	return not stolen and engine.global_position.distance_to(character.global_position) < interaction_distance


func interact(character: Node3D) -> void:
	if not can_interact(character):
		return
	if not open:
		open_hood()
	else:
		steal_engine()


func open_hood() -> void:
	if open:
		return
	hood.rotation_degrees.x -= 33.0
	open = true


func steal_engine() -> void:
	if not open or stolen or scrap_scene == null:
		return
	var scrap: Node3D = scrap_scene.instantiate() as Node3D
	if scrap == null:
		return
	# Spawn beside the truck so the collectible does not intersect its body or hood.
	get_parent().add_child(scrap)
	scrap.global_position = to_global(scrap_spawn_offset)
	engine.hide()
	stolen = true
