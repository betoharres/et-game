extends RefCounted

const MODELS: Array[String] = ["Small", "Sedan", "Taxi", "Van", "Medium", "Muscle"]


static func build(number: int) -> Node3D:
	var model: String = MODELS[number % MODELS.size()]
	var path: String = "res://PolygonCity/FBX/Veh/SM_Veh_Car_%s_01.fbx" % model
	var source: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	var car: Node3D = Node3D.new()
	car.name = "ParkedCar"
	car.set_meta("source_scene", path)
	car.set_meta("country_town_block", true)
	var material: StandardMaterial3D = (load("res://Materiais/PolygonCity1A.tres") as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.albedo_color = Color.from_hsv(float(number % 7) / 7.0, 0.12, 0.88 + (number % 3) * 0.06)
	_copy_meshes(source, car, Transform3D.IDENTITY, material)
	source.free()
	var bounds: AABB
	var first: bool = true
	for child: Node in car.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		var box: AABB = mesh.transform * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	# Todas as variantes cabem na vaga existente de 3,6 m, com apoio das rodas no piso.
	var factor: float = minf(1.0, minf(2.35 / bounds.size.x, 5.6 / bounds.size.z))
	for child: Node3D in car.get_children():
		child.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * factor), Vector3(0, -bounds.position.y * factor, 0)) * child.transform
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = bounds.size * factor * Vector3(0.94, 1.0, 0.95)
	collision.shape = shape
	collision.position = Vector3(bounds.get_center().x, bounds.size.y * 0.5, bounds.get_center().z) * factor
	body.add_child(collision)
	car.add_child(body)
	return car


static func _copy_meshes(node: Node3D, car: Node3D, parent_transform: Transform3D, material: Material) -> void:
	var combined: Transform3D = parent_transform * node.transform
	if node is MeshInstance3D:
		var source: MeshInstance3D = node as MeshInstance3D
		if source.mesh != null:
			var visual: MeshInstance3D = MeshInstance3D.new()
			visual.name = node.name
			visual.mesh = source.mesh
			visual.transform = combined
			visual.material_override = material
			visual.layers = 8
			visual.visibility_range_end = 230.0
			visual.visibility_range_end_margin = 20.0
			car.add_child(visual)
	for child: Node in node.get_children():
		if child is Node3D:
			_copy_meshes(child as Node3D, car, combined, material)
