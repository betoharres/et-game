extends "res://scripts/space/saucer.gd"

@onready var engine : AudioStreamPlayer = $Engine


func board(player : CharacterBody3D) -> void:
	player.set_movement_locked(true)
	var overlay : CanvasLayer = CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	var flash : ColorRect = ColorRect.new()
	flash.color = Color(0.55, 0.92, 1.0, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(flash)
	var fade : Tween = create_tween()
	fade.tween_property(flash, "color:a", 1.0, 0.3)
	await fade.finished
	# O SpringArm do Player é montado com meia-volta na cena.
	var mount_yaw : float = player.camera_pivot.spring_arm.rotation.y
	var yaw : float = rotation.y - mount_yaw - float(player.camera_yaw)
	var turn : Basis = Basis(Vector3.UP, yaw)
	player.apply_carry(Transform3D(turn, spawn_point.global_position - turn * player.global_position), yaw)
	player.velocity = Vector3.ZERO
	player.camera_pitch = 0.0
	player.camera_pivot.set_interior_camera_mode(true)
	player.set_first_person(true)
	player.set_movement_locked(true, 65.0)
	fade = create_tween()
	fade.tween_property(flash, "color:a", 0.0, 0.65)
	await fade.finished
	overlay.queue_free()


func stop_spin_facing(target : Vector3, duration : float) -> Tween:
	var direction : Vector3 = (target - global_position).slide(Vector3.UP).normalized()
	var angle : float = (global_basis * Vector3.FORWARD).signed_angle_to(direction, Vector3.UP)
	var tween : Tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation:y", rotation.y + angle, duration)
	return tween


func begin_approach_audio(duration : float) -> void:
	engine.volume_db = -24.0
	engine.play()
	var tween : Tween = create_tween()
	tween.tween_property(engine, "volume_db", -8.0, duration)
