extends "res://scripts/recovery_ship.gd"

var session: Node3D


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and session != null and session.mission_phase == &"collecting" and not session.host_migration.active:
		super._physics_process(delta)


func _credit_cargo(item: RigidBody3D) -> void:
	session.credit_shared_delivery(item)
