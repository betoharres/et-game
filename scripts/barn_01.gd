extends Node3D

@onready var door1 : MeshInstance3D = $SM_Bld_Barn_01/SM_Bld_Barn_01/SM_Bld_Barn_01_Door_01
@onready var door2 : MeshInstance3D = $SM_Bld_Barn_01/SM_Bld_Barn_01/SM_Bld_Barn_01_Door_02
@onready var door3 : MeshInstance3D = $SM_Bld_Barn_01/SM_Bld_Barn_01/SM_Bld_Barn_01_Door_03
@onready var door4 : MeshInstance3D = $SM_Bld_Barn_01/SM_Bld_Barn_01/SM_Bld_Barn_01_Door_04

@export var door_offset : float = 1.5
@export var door_speed : float = 2.0

var door1_closed : Vector3
var door2_closed : Vector3
var door3_closed : Vector3
var door4_closed : Vector3

var doors_open : bool = false

func _ready() -> void:

	door1_closed = door1.position
	door2_closed = door2.position
	door3_closed = door3.position
	door4_closed = door4.position

func _process(delta : float) -> void:

	var target1 : Vector3 = door1_closed
	var target2 : Vector3 = door2_closed
	var target3 : Vector3 = door3_closed
	var target4 : Vector3 = door4_closed

	if doors_open:

		target1.z += door_offset
		target2.z -= door_offset

		target3.z += door_offset
		target4.z -= door_offset


	door1.position = door1.position.move_toward(
		target1,
		delta * door_speed
	)

	door2.position = door2.position.move_toward(
		target2,
		delta * door_speed
	)

	door3.position = door3.position.move_toward(
		target3,
		delta * door_speed
	)

	door4.position = door4.position.move_toward(
		target4,
		delta * door_speed
	)

func interact() -> void:

	doors_open = not doors_open
