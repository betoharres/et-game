class_name AlienItemDefinition
extends Resource

@export var item_id : String = "alien_part"
@export var display_name : String = "Tecnologia alienígena"
@export_range(1, 4) var slot_cost : int = 1
@export var score_value : int = 10
@export var is_locator : bool = false
@export var transportable : bool = true
@export var mesh : Mesh
@export var shape : Shape3D
@export var tint : Color = Color(0.2, 0.85, 0.75)
