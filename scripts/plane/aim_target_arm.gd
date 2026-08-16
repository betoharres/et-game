extends Node3D

@onready var plane : RigidBody3D = $".."
@export var mouse_sensitivity : float = 0.003

@export var pitch_min : float = -60.0
@export var pitch_max : float = 60.0

var yaw : float = 0.0
var pitch : float = 0.0


func _ready() -> void:

	if plane == null:
		push_error("TargetArm: Plane not found.")
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Start the arm aligned with the plane's current heading.
	yaw = plane.global_rotation.y
	pitch = 0.0

	update_rotation()


func _process(_delta : float) -> void:

	if plane == null:
		return

	# Follow the plane's POSITION only.
	global_position = plane.global_position


func _input(event : InputEvent) -> void:

	if event is InputEventMouseMotion:

		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return

		var mouse_motion : Vector2 = event.relative

		yaw -= mouse_motion.x * mouse_sensitivity
		pitch -= mouse_motion.y * mouse_sensitivity

		pitch = clampf(
			pitch,
			deg_to_rad(pitch_min),
			deg_to_rad(pitch_max)
		)

		update_rotation()


	if event.is_action_pressed("ui_cancel"):

		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func update_rotation() -> void:

	global_rotation = Vector3(
		pitch,
		yaw,
		0.0
	)
