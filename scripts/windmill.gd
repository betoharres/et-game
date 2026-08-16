extends Node3D

@onready var windmill_prop : MeshInstance3D = $MeshInstance3D/MeshInstance3D2/SmPropWindmill03
@onready var windmill_neck : MeshInstance3D = $MeshInstance3D/MeshInstance3D2

@export var prop_speed : float = 1.0

var time : float = 0.0

func _physics_process(delta: float) -> void:
	time = Time.get_ticks_msec() * 0.001
	windmill_neck.rotation_degrees.y = sin(time)
	windmill_prop.rotation.z += prop_speed * delta
