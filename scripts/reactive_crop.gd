extends Node3D

## Shared wind and contact animation for corn, wheat and sunflowers.
## Dormant patches only check camera distance and visibility on a staggered timer.

@export var interaction_radius: float = 1.5
@export var bend_strength: float = 25.0
@export var vehicle_bend_multiplier: float = 10.0
@export var return_speed: float = 5.0

@export var wind_strength: float = 1.0
@export var wind_speed: float = 1.5

## Camera distance for animation, extended by the patch size. Zero disables distance gating.
@export var active_radius: float = 60.0
## Distancia em que as plantas somem, e a faixa em que elas derretem antes.
## Zero desliga o corte por distancia.
@export var visibility_range: float = 130.0
@export var visibility_fade: float = 20.0

## Sleeping patches must be able to wake without their own frame callback.
const CHECK_INTERVAL: float = 0.25
const SLEEP_MARGIN: float = 5.0

var _plants: Array[MeshInstance3D] = []
var _rest_rotations: Array[Vector3] = []
var _activity_timer: Timer
var _patch_radius: float = 0.0


func _ready() -> void:
	for child: Node in get_children():
		var plant: MeshInstance3D = child as MeshInstance3D
		if plant == null:
			continue
		_plants.append(plant)
		_rest_rotations.append(plant.rotation)
		_patch_radius = maxf(_patch_radius, global_position.distance_to(plant.global_position))
		if visibility_range > 0.0:
			plant.visibility_range_end = visibility_range
			plant.visibility_range_end_margin = visibility_fade
			plant.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	set_process(false)
	_activity_timer = Timer.new()
	_activity_timer.one_shot = true
	_activity_timer.timeout.connect(_refresh_activity)
	add_child(_activity_timer)
	_activity_timer.start(randf_range(0.01, CHECK_INTERVAL))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		set_process(false)
		return
	var characters: Array[Node3D] = _nearby_bodies("characters")
	var vehicles: Array[Node3D] = _nearby_bodies("vehicles")
	var time: float = Time.get_ticks_msec() / 1000.0

	for i: int in _plants.size():
		var plant: MeshInstance3D = _plants[i]
		if not is_instance_valid(plant) or not plant.is_visible_in_tree():
			continue

		var strongest_bend: float = 0.0
		var strongest_direction: Vector3 = Vector3.ZERO

		for character: Node3D in characters:
			var direction: Vector3 = plant.global_position - character.global_position
			direction.y = 0.0
			var distance: float = direction.length()
			if distance >= interaction_radius:
				continue
			var bend_amount: float = 1.0 - (distance / interaction_radius)
			bend_amount = bend_amount * bend_amount
			if bend_amount > strongest_bend:
				strongest_bend = bend_amount
				strongest_direction = direction.normalized()

		for vehicle: Node3D in vehicles:
			var direction: Vector3 = plant.global_position - vehicle.global_position
			direction.y = 0.0
			var distance: float = direction.length()
			if distance >= interaction_radius:
				continue
			var bend_amount: float = 1.0 - (distance * 1.5 / interaction_radius)
			bend_amount = bend_amount * bend_amount
			bend_amount *= vehicle_bend_multiplier
			if bend_amount > strongest_bend:
				strongest_bend = bend_amount
				strongest_direction = direction.normalized()

		var target_rotation: Vector3 = _rest_rotations[i]
		if strongest_bend > 0.0:
			var local_direction: Vector3 = plant.global_transform.basis.inverse() * strongest_direction
			target_rotation.x += local_direction.z * strongest_bend * deg_to_rad(bend_strength)
			target_rotation.z += -local_direction.x * strongest_bend * deg_to_rad(bend_strength)

		target_rotation.z += deg_to_rad(sin(time * wind_speed + float(i) * 1.73) * wind_strength)
		plant.rotation = plant.rotation.lerp(target_rotation, delta * return_speed)


func _refresh_activity() -> void:
	set_process(_should_animate())
	_activity_timer.start(CHECK_INTERVAL)


func _should_animate() -> bool:
	if not is_visible_in_tree():
		return false
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return false
	var radius: float = active_radius + _patch_radius
	if is_processing():
		radius += SLEEP_MARGIN
	if active_radius > 0.0 and global_position.distance_squared_to(camera.global_position) > radius * radius:
		return false
	for plant: MeshInstance3D in _plants:
		if not is_instance_valid(plant) or plant.mesh == null or not plant.is_visible_in_tree():
			continue
		if (plant.layers & camera.cull_mask) == 0:
			continue
		var distance_squared: float = plant.global_position.distance_squared_to(camera.global_position)
		var end: float = plant.visibility_range_end + plant.visibility_range_end_margin
		if plant.visibility_range_end > 0.0 and distance_squared > end * end:
			continue
		var begin: float = maxf(0.0, plant.visibility_range_begin - plant.visibility_range_begin_margin)
		if distance_squared < begin * begin:
			continue
		return true
	return false


func _nearby_bodies(group: String) -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	var radius: float = _patch_radius + interaction_radius
	for node: Node in get_tree().get_nodes_in_group(group):
		if group == "characters" and not node is CharacterBody3D:
			continue
		if group == "vehicles" and not node is VehicleBody3D:
			continue
		var body: Node3D = node as Node3D
		var offset: Vector3 = body.global_position - global_position
		offset.y = 0.0
		if offset.length_squared() <= radius * radius:
			bodies.append(body)
	return bodies
