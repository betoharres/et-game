class_name CinematicCameraRig
extends Node3D

## A lightly detached third-person camera. Input updates the desired pose while
## this rig eases toward it, leaving SpringArm3D responsible for obstructions.

@export_group("Framing")
@export_range(0.0, 2.0, 0.01) var pivot_height : float = 1.08
@export_range(-1.5, 1.5, 0.01) var shoulder_offset : float = 0.72

@export_group("Response")
@export_range(1.0, 30.0, 0.5) var position_response : float = 7.0
@export_range(1.0, 30.0, 0.5) var rotation_response : float = 9.0
@export_range(0.1, 3.0, 0.05) var maximum_follow_lag : float = 1.1
@export_range(1.0, 30.0, 0.5) var teleport_snap_distance : float = 8.0

@export_group("Organic Motion")
@export_range(0.0, 0.08, 0.001) var walk_sway_amount : float = 0.026
@export_range(0.0, 0.04, 0.001) var walk_vertical_amount : float = 0.012
@export_range(0.0, 5.0, 0.05) var walk_sway_frequency : float = 1.65
@export_range(0.0, 0.03, 0.001) var idle_breath_amount : float = 0.008
@export_range(0.0, 2.0, 0.05) var idle_breath_frequency : float = 0.22
@export_range(0.0, 0.2, 0.005) var turn_parallax_amount : float = 0.11

@onready var pitch_pivot : Node3D = $PitchPivot
@onready var shoulder : Node3D = $PitchPivot/ShoulderOffset
@onready var spring_arm : SpringArm3D = $PitchPivot/ShoulderOffset/SpringArm3D
@onready var camera : Camera3D = (
	$PitchPivot/ShoulderOffset/SpringArm3D/Camera3D
)

var _target_position : Vector3
var _target_yaw : float = 0.0
var _target_pitch : float = 0.0
var _target_crouch_drop : float = 0.0
var _target_speed : float = 0.0
var _target_grounded : bool = true
var _motion_blend : float = 0.0
var _sway_phase : float = 0.0
var _elapsed : float = 0.0
var _has_target : bool = false

## XRAY stuff
@export var null_material : StandardMaterial3D
@onready var xray_camera : Camera3D = $PitchPivot/ShoulderOffset/SpringArm3D/XRAYCamera
@onready var binos_mesh : MeshInstance3D = $"../ET/ETArmature/Skeleton3D/ET/FarSightGoggles"
@export var xray_material : ShaderMaterial

@export var normal_fov : float = 60.0
@export var min_fov : float = 15.0
@export var max_fov : float = 75.0
@export var zoom_speed : float = 35.0

@export var xray_radius : float = 35.0
@export var xray_inner_radius : float = 12.0

var binos_active : bool = false
var current_fov : float = 60.0
var _xray_states : Array[Dictionary] = []

func _ready() -> void:
	top_level = true
	process_priority = 10

	var followed_body : CollisionObject3D = get_parent() as CollisionObject3D
	if followed_body != null:
		spring_arm.add_excluded_object(followed_body.get_rid())

	_target_position = global_position
	_target_yaw = global_rotation.y
	_target_pitch = pitch_pivot.rotation.x

	## XRAY Stuff
	xray_camera.current = false

	current_fov = normal_fov

	xray_material.set_shader_parameter(
		"xray_radius",
		xray_radius
	)

	xray_material.set_shader_parameter(
		"inner_radius",
		xray_inner_radius
	)
	

func _exit_tree() -> void:
	_restore_materials()


func set_target_pose(
	position_in : Vector3,
	yaw : float,
	pitch : float,
	crouch_drop : float,
	horizontal_speed : float,
	grounded : bool,
	snap : bool = false
) -> void:
	_target_position = position_in
	_target_yaw = yaw
	_target_pitch = pitch
	_target_crouch_drop = crouch_drop
	_target_speed = horizontal_speed
	_target_grounded = grounded
	_has_target = true

	if snap or global_position.distance_to(position_in) >= teleport_snap_distance:
		_snap_to_target()


func get_camera() -> Camera3D:
	return camera


func _input(event : InputEvent) -> void:
	# Checked on the event itself: Input.is_action_just_pressed() stays true for
	# the whole frame, and _input() runs once per event, so mouse motion in the
	# same frame would toggle the binoculars a second time and cancel it out.
	if event.is_action_pressed("binos"):
		if binos_active:
			deactivate_binos()
		else:
			activate_binos()

func _process(delta : float) -> void:
	if not _has_target:
		return

	#XRAY, pass delta
	if binos_active:
		update_binos(delta)
		
	_elapsed += delta
	var position_weight : float = 1.0 - exp(-position_response * delta)
	var rotation_weight : float = 1.0 - exp(-rotation_response * delta)

	global_position = global_position.lerp(_target_position, position_weight)
	var follow_offset : Vector3 = global_position - _target_position
	if follow_offset.length() > maximum_follow_lag:
		global_position = (
			_target_position + follow_offset.normalized() * maximum_follow_lag
		)

	rotation.y = lerp_angle(rotation.y, _target_yaw, rotation_weight)
	pitch_pivot.rotation.x = lerp_angle(
		pitch_pivot.rotation.x,
		_target_pitch,
		rotation_weight
	)

	_update_organic_motion(delta, position_weight, rotation_weight)

func _snap_to_target() -> void:
	global_position = _target_position
	rotation = Vector3(0.0, _target_yaw, 0.0)
	pitch_pivot.rotation.x = _target_pitch


func _update_organic_motion(delta : float, position_weight : float, rotation_weight : float) -> void:
	
	var desired_motion : float = 0.0
	if _target_grounded:
		desired_motion = clampf(_target_speed / 3.0, 0.0, 1.0)
	_motion_blend = lerpf(_motion_blend, desired_motion, position_weight)
	_sway_phase += delta * walk_sway_frequency * TAU * lerpf(
		0.72, 1.12, _motion_blend)

	var breath : float = sin(_elapsed * idle_breath_frequency * TAU)
	var lateral_sway : float = sin(_sway_phase) * walk_sway_amount * _motion_blend
	var vertical_sway : float = (
		(0.5 - 0.5 * cos(_sway_phase * 2.0))
		* walk_vertical_amount
		* _motion_blend
	)
	vertical_sway += breath * idle_breath_amount * (1.0 - _motion_blend * 0.7)

	pitch_pivot.position = Vector3(
		lateral_sway,
		pivot_height - _target_crouch_drop + vertical_sway,
		0.0
	)

	var yaw_lag : float = wrapf(_target_yaw - rotation.y, -PI, PI)
	var parallax : float = clampf(
		yaw_lag * turn_parallax_amount,
		-turn_parallax_amount,
		turn_parallax_amount
	)
	shoulder.position.x = lerpf(
		shoulder.position.x,
		shoulder_offset + parallax,
		rotation_weight
	)

	var walk_roll : float = sin(_sway_phase) * deg_to_rad(0.10) * _motion_blend
	var turn_roll : float = clampf(yaw_lag * 0.012, -0.004, 0.004)
	var idle_roll : float = breath * deg_to_rad(0.025) * (1.0 - _motion_blend)
	camera.rotation.z = lerpf(
		camera.rotation.z,
		walk_roll + turn_roll + idle_roll,
		rotation_weight
	)


## XRAY Stuff
func activate_binos() -> void:

	binos_active = true
	binos_mesh.visible = true

	current_fov = normal_fov

	_apply_xray_materials()
	camera.current = false
	xray_camera.current = true


func deactivate_binos() -> void:

	binos_active = false
	binos_mesh.visible = false

	xray_camera.current = false
	camera.current = true

	camera.fov = normal_fov
	_restore_materials()


func update_binos(delta : float) -> void:

	# +/- zoom
	if Input.is_action_pressed("binos_zoom_in"):
		current_fov -= zoom_speed * delta

	if Input.is_action_pressed("binos_zoom_out"):
		current_fov += zoom_speed * delta

	current_fov = clamp(
		current_fov,
		min_fov,
		max_fov
	)

	xray_camera.fov = current_fov

	# Keep X-ray camera synchronized with normal camera.
	xray_camera.global_transform = camera.global_transform


	# X-ray center is in front of camera.
	var zoom_amount : float = inverse_lerp(
		max_fov,
		min_fov,
		current_fov
	)

	var xray_distance : float = lerp(
		12.0,
		35.0,
		zoom_amount
	)

	var center : Vector3 = \
		xray_camera.global_position \
		- xray_camera.global_transform.basis.z * xray_distance

	xray_material.set_shader_parameter("xray_center", center)


func _apply_xray_materials() -> void:
	_restore_materials()
	var scene_root : Node = get_tree().current_scene
	if (
		scene_root == null
		or xray_material == null
		or not is_instance_valid(xray_material)
	):
		return

	for node : Node in scene_root.find_children("*", "GeometryInstance3D", true, false):
		var geometry : GeometryInstance3D = node as GeometryInstance3D
		if geometry == null:
			continue

		var state : Dictionary = {
			"geometry": weakref(geometry),
			"material_override": geometry.material_override,
			"surface_overrides": [],
		}
		if geometry is MeshInstance3D:
			var mesh_instance : MeshInstance3D = geometry as MeshInstance3D
			var surface_overrides : Array[Material] = []
			if mesh_instance.mesh != null:
				for surface_index : int in range(mesh_instance.mesh.get_surface_count()):
					surface_overrides.append(
						mesh_instance.get_surface_override_material(surface_index)
					)
					mesh_instance.set_surface_override_material(
						surface_index,
						xray_material
					)
			state["surface_overrides"] = surface_overrides

		_xray_states.append(state)
		geometry.material_override = xray_material


func _restore_materials() -> void:
	for state : Dictionary in _xray_states:
		var geometry_reference : WeakRef = state["geometry"] as WeakRef
		var geometry : GeometryInstance3D = (
			geometry_reference.get_ref() as GeometryInstance3D
		)
		if geometry == null:
			continue

		if geometry is MeshInstance3D:
			var mesh_instance : MeshInstance3D = geometry as MeshInstance3D
			var surface_overrides : Array = state["surface_overrides"]
			var surface_count : int = 0
			if mesh_instance.mesh != null:
				surface_count = mini(
					surface_overrides.size(),
					mesh_instance.mesh.get_surface_count()
				)
			for surface_index : int in range(surface_count):
				var original_surface_override : Material = surface_overrides[surface_index]
				mesh_instance.set_surface_override_material(
					surface_index,
					original_surface_override
				)

		var original_override : Material = state["material_override"] as Material
		geometry.material_override = original_override

	_xray_states.clear()
