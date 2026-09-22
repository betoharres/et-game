class_name NPCHearing
extends Node3D

@export var hearing_radius: float = 10.0
@export var movement_noise_speed_threshold: float = 2.0
@export var scan_interval: float = 0.25
@export var noise_memory_seconds: float = 5.0

var pending_noise_position: Vector3 = Vector3.ZERO
var pending_noise_time: float = -1000.0

var investigating_noise: bool = false
var investigation_position: Vector3 = Vector3.ZERO

var _scan_timer: float = 0.0


func _ready() -> void:
	add_to_group(&"npc_hearing_listeners")
	_scan_timer = randf_range(0.0, scan_interval)


func hear_report(source: Vector3, last_seen: Vector3) -> void:
	if global_position.distance_to(source) > 18.0:
		return
	_remember_noise(last_seen)


func _physics_process(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = scan_interval
	var actor: NPCActor = get_parent() as NPCActor
	if actor != null and is_instance_valid(actor.player) and global_position.distance_to(actor.player.global_position) > 90.0:
		_scan_timer = 0.8
	_scan_ambient_noise()


func _scan_ambient_noise() -> void:
	var sources: Array[Node] = []
	sources.append_array(get_tree().get_nodes_in_group("characters"))
	sources.append_array(get_tree().get_nodes_in_group("vehicles"))

	for source in sources:
		if source == get_parent() or not (source is Node3D) or source.has_node("PlayerNoise"):
			continue

		var speed: float = 0.0
		if source is CharacterBody3D:
			speed = (source as CharacterBody3D).velocity.length()
		elif source is RigidBody3D:
			speed = (source as RigidBody3D).linear_velocity.length()

		if speed < movement_noise_speed_threshold:
			continue

		hear_noise((source as Node3D).global_position, 1.0)


## Registra um evento de ruído se estiver dentro do alcance efetivo
## (`hearing_radius * loudness`). `loudness = 1.0` é o padrão de um passo ou
## motor próximo; eventos mais altos (tiro, buzina) podem usar um valor maior.
func hear_noise(position2: Vector3, loudness: float = 1.0) -> void:
	var effective_radius: float = hearing_radius * maxf(loudness, 0.1)
	if global_position.distance_to(position2) > effective_radius:
		return
	_remember_noise(position2)


func hear_sound(origin: Vector3, decibels: float, radius: float) -> bool:
	var actor: Node = get_parent()
	if not is_inside_tree() or not can_process() or actor.is_queued_for_deletion():
		return false
	if actor.has_method("is_alive") and not bool(actor.call("is_alive")):
		return false
	if not origin.is_finite() or not is_finite(decibels) or not is_finite(radius) or radius <= 0.0:
		return false
	var offset: Vector3 = origin - global_position
	# O círculo no minimapa usa o mesmo alcance horizontal do sensor.
	offset.y = 0.0
	if offset.length_squared() > radius * radius:
		return false
	_remember_noise(origin)
	return true


func is_enemy_listener() -> bool:
	var actor: NPCActor = get_parent() as NPCActor
	return actor != null and actor.reaction_mode == NPCActor.ReactionMode.CHASE


func _remember_noise(origin: Vector3) -> void:
	pending_noise_position = origin
	pending_noise_time = Time.get_ticks_msec() / 1000.0
	var actor: NPCActor = get_parent() as NPCActor
	if actor != null:
		actor.refresh_awareness()


func has_noise_to_investigate() -> bool:
	return investigating_noise or has_pending_noise()


func begin_investigation() -> Vector3:
	investigation_position = consume_noise()
	investigating_noise = true
	return investigation_position


func finish_investigation() -> void:
	investigating_noise = false


func has_pending_noise() -> bool:
	return (Time.get_ticks_msec() / 1000.0 - pending_noise_time) <= noise_memory_seconds


func consume_noise() -> Vector3:
	pending_noise_time = -1000.0
	return pending_noise_position
