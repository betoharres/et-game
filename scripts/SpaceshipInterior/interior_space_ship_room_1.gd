extends Node3D

@onready var gravity_sphere : MeshInstance3D = $SphereMesh
@export var player_array : Array[CharacterBody3D] = []

#func _physics_process(_delta: float) -> void:
	#if player == null:
	#	return
		
	#player[i].gravity_dir = (
	#	gravity_sphere.global_position -
		#player.global_position
	#).normalized()
