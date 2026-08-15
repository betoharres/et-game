extends CharacterBody3D


@export var speed: float = 5.0
@export var sensitivity: float = 0.003
@export var rotation_speed: float = 10.0

@export var camera_pitch_min: float = -80.0
@export var camera_pitch_max: float = 80.0

@onready var camera_pivot: Node3D = $CameraHolder

var camera_yaw: float = 0.0
var camera_pitch: float = 0.0

# Items
var carried_item : RigidBody3D = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	camera_yaw = global_rotation.y
	camera_pitch = camera_pivot.rotation.x

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mouse_motion: Vector2 = event.relative

			camera_yaw -= mouse_motion.x * sensitivity
			camera_pitch -= -mouse_motion.y * sensitivity

			var minimum_pitch: float = deg_to_rad(camera_pitch_min)
			var maximum_pitch: float = deg_to_rad(camera_pitch_max)

			camera_pitch = clampf(camera_pitch,minimum_pitch,maximum_pitch)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
# Items
	if event.is_action_pressed("ui_accept"):
		if carried_item == null:
			try_pickup()
		else:
			carried_item.drop()
			carried_item = null

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	
	camera_pivot.global_position = global_position
	var camera_rotation : Vector3 = Vector3(camera_pitch,camera_yaw,0.0)

	camera_pivot.global_rotation = camera_rotation

	var input_direction: Vector2 = Input.get_vector("ui_right","ui_left","ui_up","ui_down")

	var camera_forward: Vector3 = Vector3(-sin(camera_yaw),0.0,-cos(camera_yaw))

	var camera_right: Vector3 = Vector3(cos(camera_yaw),0.0,-sin(camera_yaw))

	var movement_direction: Vector3 = (camera_right * input_direction.x +
		camera_forward * input_direction.y)

	movement_direction.y = 0.0

	if movement_direction.length_squared() > 0.0001:
		movement_direction = movement_direction.normalized()

		velocity.x = movement_direction.x * speed
		velocity.z = movement_direction.z * speed

		var target_angle: float = atan2(movement_direction.x,movement_direction.z)

		rotation.y = rotate_toward(rotation.y,target_angle,rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x,0.0,speed)

		velocity.z = move_toward(velocity.z,0.0,speed)

	move_and_slide()
	
func try_pickup() -> void:

	if carried_item != null:
		return

	var items : Array[Node] = get_tree().get_nodes_in_group("pickup_items")

	var closest_item : RigidBody3D = null
	var closest_distance : float = 2.0

	for item in items:
		if not item is RigidBody3D:
			continue

		var distance : float = (
			global_position.distance_to(
				item.global_position
			)
		)

		if distance < closest_distance:
			closest_distance = distance
			closest_item = item


	if closest_item != null:
		carried_item = closest_item
		closest_item.pickup(self)

func deliver_item(_delivery_area : Area3D) -> void:
	if carried_item == null:
		return

	var score : int = carried_item.score_value

	GlobalScore.add_score(score)
	carried_item.queue_free()
	carried_item = null
