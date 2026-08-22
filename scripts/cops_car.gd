extends Node3D

# Lights
@onready var light1 : Node3D = $ArmRed1
@onready var light2 : Node3D = $ArmWhite1
@onready var light3 : Node3D = $ArmRed2
@onready var light4 : Node3D = $ArmWhite2
@onready var light5 : Node3D = $ArmRed3

var rot_speed : float = 10.0

func _physics_process(delta: float) -> void:
	light1.rotation.y += rot_speed * delta
	light2.rotation.y += rot_speed * delta
	light3.rotation.y += rot_speed * delta
	light4.rotation.y += rot_speed * delta
	light5.rotation.y += rot_speed * delta
