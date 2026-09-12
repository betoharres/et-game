class_name AlienTechnologyItem
extends "res://scripts/spaceship_scraps.gd"

const ItemDefinition : Script = preload("res://scripts/alien_item_definition.gd")

enum State { WORLD, INVENTORY, CARRIED, ABDUCTING }

@export var definition : ItemDefinition

# Derivado do contrato legado para nunca divergir durante coleta ou entrega.
var state : State:
	get:
		if being_abducted:
			return State.ABDUCTING
		if _stored:
			return State.INVENTORY
		return State.CARRIED if carried else State.WORLD


func _ready() -> void:
	add_to_group("pickup_items")
	if definition == null:
		push_error("Tecnologia sem definição: %s" % get_path())
		return
	item_id = definition.item_id
	display_name = definition.display_name
	slot_cost = 1 if definition.is_locator else definition.slot_cost
	score_value = definition.score_value
	two_handed = false
	freeze = not definition.transportable
	var visual : MeshInstance3D = MeshInstance3D.new()
	visual.mesh = definition.mesh
	visual.layers = 64
	var material : StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = definition.tint
	material.metallic = 0.65
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission = definition.tint
	material.emission_energy_multiplier = 0.35
	visual.material_override = material
	add_child(visual)
	var collision : CollisionShape3D = CollisionShape3D.new()
	collision.shape = definition.shape
	add_child(collision)


func begin_abduction() -> bool:
	if definition != null and definition.is_locator:
		return false
	return super.begin_abduction()


func inventory_rejection() -> String:
	if definition != null and not definition.transportable:
		return "Este objeto é grande demais para transportar."
	return ""


func store_in_inventory(player : Node3D) -> bool:
	if not inventory_rejection().is_empty():
		return false
	return super.store_in_inventory(player)


func pickup(player : Node3D) -> void:
	if inventory_rejection().is_empty():
		super.pickup(player)
