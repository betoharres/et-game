extends Node3D

## Action-specific right-arm IK. Base locomotion is authored in Mixamo and this
## node only takes control while carrying an item or signaling intervention.

@export var intervention_hand_position : Vector3 = Vector3(-0.13, 0.72, 0.01)
@export var intervention_elbow_position : Vector3 = Vector3(-0.38, 0.62, -0.1)
@export var intervention_pose_speed : float = 7.0
@export var carrying_ik_weight : float = 0.85

@onready var target_hand_right : Marker3D = $HandR
@onready var target_elbow_right : Marker3D = $ElbowR
@onready var hand_ik : TwoBoneIK3D = (
	$"../ET/ETArmature/Skeleton3D/HandR"
)

var intervention_pose_requested : bool = false
var intervention_pose_weight : float = 0.0
var carrying_item : bool = false
var _hand_rest_position : Vector3
var _elbow_rest_position : Vector3


func _ready() -> void:
	_hand_rest_position = target_hand_right.position
	_elbow_rest_position = target_elbow_right.position
	hand_ik.influence = 0.0


func set_intervention_pose(active : bool) -> void:
	intervention_pose_requested = active


func set_carrying(active : bool) -> void:
	carrying_item = active


func _physics_process(delta : float) -> void:
	var target_intervention_weight : float = (
		1.0 if intervention_pose_requested else 0.0
	)
	intervention_pose_weight = move_toward(
		intervention_pose_weight,
		target_intervention_weight,
		delta * intervention_pose_speed
	)

	target_hand_right.position = _hand_rest_position.lerp(
		intervention_hand_position,
		intervention_pose_weight
	)
	target_elbow_right.position = _elbow_rest_position.lerp(
		intervention_elbow_position,
		intervention_pose_weight
	)

	var target_ik_weight : float = intervention_pose_weight
	if carrying_item:
		target_ik_weight = maxf(target_ik_weight, carrying_ik_weight)

	hand_ik.influence = move_toward(
		hand_ik.influence,
		target_ik_weight,
		delta * intervention_pose_speed
	)
