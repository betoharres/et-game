extends Node3D

#Legs stuff
@onready var target_legR : Marker3D = $TargetLegR
@onready var target_legL : Marker3D = $TargetLegL

@export var walk_speed : float = 1.5 # 5.0 is too fast
@export var step_distance : float = 0.5
@export var step_height : float = 0.2
@export var minimum_walk_speed : float = 0.01
@export var rest_speed : float = 20.0 # lower = slower time to go to rest position

var leg_target_x_offset : float = 0.044
var legR_progress : float = 0.0
var legL_progress : float = 0.5
var step_offset : float = 0.1 + step_distance/2.0

#Arms stuff
@onready var target_handR : Marker3D = $HandR
@onready var target_handL : Marker3D = $HandL
@onready var target_elbowR : Marker3D = $ElbowR

@export var arm_distance : float = 0.3
@export var arm_height : float = 0.15
@export var intervention_hand_position : Vector3 = Vector3(-0.13, 0.72, 0.01)
@export var intervention_elbow_position : Vector3 = Vector3(-0.38, 0.62, -0.1)
@export var intervention_pose_speed : float = 7.0

var armR_progress : float = 0.5
var armL_progress : float = 0.0
var hand_x_offset : float = 0.149
var hand_rest_y : float = 0.35
var intervention_pose_requested : bool = false
var intervention_pose_weight : float = 0.0
var elbowR_rest_position : Vector3

#Hips slight shake
@onready var hips_target : Marker3D = $Hips
@export var hips_rotation_amount : float = 3.0


func _ready() -> void:
	elbowR_rest_position = target_elbowR.position


func set_intervention_pose(active : bool) -> void:
	intervention_pose_requested = active

func _physics_process(delta : float) -> void:
	var target_pose_weight := 1.0 if intervention_pose_requested else 0.0
	intervention_pose_weight = move_toward(
		intervention_pose_weight,
		target_pose_weight,
		delta * intervention_pose_speed
	)
	
	# Legs
	var parent_character : CharacterBody3D = get_parent() as CharacterBody3D

	if parent_character == null:
		return

	var velocity : Vector3 = parent_character.velocity
	var horizontal_velocity : Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var movement_speed : float = horizontal_velocity.length()

	if movement_speed < minimum_walk_speed:
		target_legR.position = target_legR.position.lerp(
			Vector3(-leg_target_x_offset, 0.0, 0.0),
			delta * rest_speed)

		target_legL.position = target_legL.position.lerp(
			Vector3(leg_target_x_offset, 0.0, 0.0),
			delta * rest_speed)
			
		target_handR.position = target_handR.position.lerp(
			Vector3(-hand_x_offset, hand_rest_y, 0.0),
			delta * rest_speed)

		target_handL.position = target_handL.position.lerp(
			Vector3(hand_x_offset, hand_rest_y, 0.0),
			delta * rest_speed)
			
		hips_target.position = hips_target.position.lerp(
			Vector3(0.0, 0.44, 1.944),
			delta * rest_speed)

		_apply_intervention_pose()

		return

	var speed_ratio : float = movement_speed / walk_speed

	legR_progress += delta * speed_ratio
	legL_progress += delta * speed_ratio

	legR_progress = fmod(legR_progress, 1.0)
	legL_progress = fmod(legL_progress, 1.0)

	update_leg(target_legR, legR_progress)
	update_leg(target_legL, legL_progress)
	
	# Arms
	armR_progress += delta * speed_ratio
	armL_progress += delta * speed_ratio

	armR_progress = fmod(armR_progress, 1.0)
	armL_progress = fmod(armL_progress, 1.0)

	update_arm(target_handR, armR_progress)
	update_arm(target_handL, armL_progress)
	
	rotate_torso()
	_apply_intervention_pose()


func _apply_intervention_pose() -> void:
	target_handR.position = target_handR.position.lerp(
		intervention_hand_position,
		intervention_pose_weight
	)
	target_elbowR.position = elbowR_rest_position.lerp(
		intervention_elbow_position,
		intervention_pose_weight
	)

func update_leg(target : Marker3D, progress : float) -> void:
	if progress < 0.5:
		var arc_progress : float = progress * 2.0

		target.position.z = lerp(0.0,step_distance,arc_progress) - step_offset
		target.position.y = sin(arc_progress * PI) * step_height

	else:
		var ground_progress : float = (progress - 0.5) * 2.0

		target.position.z = lerp(step_distance,	0.0,
			ground_progress) - step_offset

		target.position.y = 0.0
		
func update_arm(target : Marker3D, progress : float) -> void:
	var forward_position : Vector3 = Vector3(target.position.x,0.557,0.104)
	var back_position : Vector3 = Vector3(target.position.x,0.475,-0.104)
	var curve_amount : float = 0.025
	var arm_position : Vector3

	if progress < 0.5:
		var t : float = progress * 2.0

		arm_position = back_position.lerp(forward_position,t)
		arm_position.y += sin(t * PI) * curve_amount

	else:
		var t : float = (progress - 0.5) * 2.0

		arm_position = forward_position.lerp(back_position,t)
		arm_position.y += sin(t * PI) * curve_amount

	target.position = arm_position 

func rotate_torso() -> void:
	hips_target.position.x = sin(legR_progress * PI * 2.0) * 0.2
