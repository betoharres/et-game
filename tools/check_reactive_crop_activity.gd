extends SceneTree

const CROP: Script = preload("res://scripts/reactive_crop.gd")
var _failures: int = 0


func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 2, 500)
	var crop: Node3D = Node3D.new()
	crop.set_script(CROP)
	crop.set("active_radius", 30.0)
	var plant: MeshInstance3D = MeshInstance3D.new()
	plant.mesh = BoxMesh.new()
	crop.add_child(plant)
	viewport.add_child(crop)
	var character: CharacterBody3D = CharacterBody3D.new()
	viewport.add_child(character)
	character.add_to_group("characters")
	character.position = Vector3(0.5, 0, 0)
	var vehicle: VehicleBody3D = VehicleBody3D.new()
	vehicle.freeze = true
	viewport.add_child(vehicle)
	vehicle.add_to_group("vehicles")
	vehicle.position = Vector3(300, 0, 300)
	await create_timer(0.35).timeout
	_require(not crop.is_processing(), "Nearby actors do not wake crops far from camera")
	_require(plant.rotation == Vector3.ZERO, "Sleeping crops do not animate")
	camera.position = Vector3(0, 2, 5)
	await create_timer(0.35).timeout
	_require(crop.is_processing(), "Timer wakes a patch when camera approaches")
	_require(plant.rotation.length() > 0.01, "Nearby character still bends the crop")
	var characters: Array = crop.call("_nearby_bodies", "characters")
	var vehicles: Array = crop.call("_nearby_bodies", "vehicles")
	_require(characters.has(character) and vehicles.is_empty(), "Interaction broad phase excludes distant bodies")
	vehicle.position = Vector3(0.5, 0, 0)
	vehicles = crop.call("_nearby_bodies", "vehicles")
	_require(vehicles.has(vehicle), "Nearby vehicles remain interactive")
	plant.hide()
	await create_timer(0.35).timeout
	_require(not crop.is_processing(), "Hidden meshes disable patch frame processing")
	var sleeping_rotation: Vector3 = plant.rotation
	await create_timer(0.3).timeout
	_require(plant.rotation == sleeping_rotation, "Hidden meshes receive no rotation updates")
	plant.show()
	await create_timer(0.35).timeout
	_require(crop.is_processing(), "Showing a mesh allows timer wakeup")
	camera.position = Vector3(0, 0, 33)
	await create_timer(0.3).timeout
	_require(crop.is_processing(), "Hysteresis avoids toggling at the active boundary")
	camera.position.z = 40
	await create_timer(0.3).timeout
	_require(not crop.is_processing(), "Leaving the sleep margin disables frame processing")
	crop.set("active_radius", 0.0)
	plant.visibility_range_end = 10.0
	plant.visibility_range_end_margin = 0.0
	await create_timer(0.3).timeout
	_require(not crop.is_processing(), "Render distance is respected even with unlimited activity radius")
	camera.position.z = 5
	camera.cull_mask = 0
	await create_timer(0.3).timeout
	_require(not crop.is_processing(), "Excluded render layers remain dormant")
	camera.cull_mask = 1048575
	await create_timer(0.3).timeout
	_require(crop.is_processing(), "Restoring the camera mask restores animation")
	crop.hide()
	await create_timer(0.3).timeout
	_require(not crop.is_processing(), "Hidden parent disables animation")
	viewport.free()
	print("Reactive crop activity: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
