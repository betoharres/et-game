extends Area3D

signal item_delivered(item_score : int)

@export var radius : float = 4.0
@export var detection_height : float = 3.0

var status_text : String = "Largue os itens dentro do círculo"


func _ready() -> void:
	add_to_group("recovery_zones")
	add_to_group("delivery_areas")
	collision_layer = 0
	collision_mask = 9
	var shape : CylinderShape3D = CylinderShape3D.new()
	shape.radius = radius
	shape.height = detection_height
	var detection : CollisionShape3D = CollisionShape3D.new()
	detection.shape = shape
	detection.position.y = detection_height * 0.5
	add_child(detection)
	var ring : MeshInstance3D = MeshInstance3D.new()
	var mesh : TorusMesh = TorusMesh.new()
	mesh.inner_radius = radius - 0.12
	mesh.outer_radius = radius
	ring.mesh = mesh
	ring.position.y = 0.08
	var material : StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.9, 0.75)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 2.0
	ring.material_override = material
	add_child(ring)
	var label : Label3D = Label3D.new()
	label.text = "PONTO DE COLETA"
	label.position.y = 2.6
	label.font_size = 48
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = material.albedo_color
	add_child(label)


func contains_position(world_position : Vector3) -> bool:
	var point : Vector3 = to_local(world_position)
	return point.y >= 0.0 and point.y <= detection_height and Vector2(point.x, point.z).length() <= radius


func available_items() -> Array[RigidBody3D]:
	var result : Array[RigidBody3D] = []
	for body : Node3D in get_overlapping_bodies():
		if not body is RigidBody3D or not body.is_in_group("pickup_items"):
			continue
		if not contains_position(body.global_position) or not body.has_meta("recovery_dropped"):
			continue
		if not body.has_method("is_available_for_abduction") or not bool(body.call("is_available_for_abduction")):
			continue
		if body is AlienTechnologyItem and body.definition != null:
			if body.definition.is_locator or not body.definition.transportable:
				continue
		result.append(body as RigidBody3D)
	return result
