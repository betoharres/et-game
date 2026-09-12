class_name NPCRangedCombat
extends Node

signal health_changed(current: float, maximum: float)
signal died

const LASER_SHOT: AudioStream = preload("res://assets/audio/gun/laser-gun-shooting-sound.mp3")
const FIREARM_SHOT: AudioStream = preload("res://assets/audio/gun/firearm-shooting-sound.mp3")

var health: float = 0.0
var _cooldown: float = 0.0
var _aim_elapsed: float = 0.0
var _burst_shots: int = 0

@onready var _npc: PursuitNPC = get_parent() as PursuitNPC
@onready var _appearance: PursuitAppearance = get_node("../Appearance") as PursuitAppearance
@onready var _audio: AudioStreamPlayer3D = $"../GunshotAudio"


func _ready() -> void:
	health = _npc.profile.max_health
	_audio.pitch_scale = _npc.profile.shot_pitch
	_audio.volume_db = _npc.profile.shot_volume_db
	_audio.max_db = _npc.profile.shot_volume_db
	_audio.stream = LASER_SHOT if _npc.profile.laser_shots else FIREARM_SHOT


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func can_engage() -> bool:
	if health <= 0.0 or not _npc.is_player_alive():
		return false
	if _npc.vision == null or not _npc.vision.has_detected_player or not _npc.vision.is_currently_visible:
		return false
	if _npc.global_position.distance_to(_npc.player.global_position) > _npc.profile.attack_range:
		return false
	var hit: Dictionary = _ray_to(_target_position())
	return _is_target(hit.get("collider"))


func aim_and_fire(delta: float) -> void:
	var direction: Vector3 = _npc.player.global_position - _npc.global_position
	direction.y = 0.0
	_npc.face_direction(direction)
	if _npc.global_basis.z.dot(direction.normalized()) < 0.96:
		_aim_elapsed = 0.0
		return
	_aim_elapsed += delta
	if _aim_elapsed < _npc.profile.aim_time or _cooldown > 0.0:
		return
	var origin: Vector3 = _appearance.muzzle.global_position
	var target: Vector3 = _target_position()
	var spread: float = tan(deg_to_rad(_npc.profile.spread_degrees)) * origin.distance_to(target)
	target += _npc.global_basis.x * randf_range(-spread, spread)
	target += Vector3.UP * randf_range(-spread, spread)
	var shot_direction: Vector3 = (target - origin).normalized()
	var hit: Dictionary = _ray_to(origin + shot_direction * _npc.profile.attack_range)
	var end: Vector3 = hit.get("position", origin + shot_direction * _npc.profile.attack_range)
	_appearance.show_shot(end)
	_audio.play()
	_burst_shots += 1
	if _burst_shots >= _npc.profile.burst_size:
		_burst_shots = 0
		_cooldown = maxf(_npc.profile.burst_pause, _npc.profile.shot_interval)
	else:
		_cooldown = maxf(_npc.profile.shot_interval, 0.05)
	if _is_target(hit.get("collider")) and _npc.player.has_method("take_damage"):
		_npc.player.call("take_damage", _npc.profile.damage, shot_direction, 0.0)


func interrupt_aim() -> void:
	_aim_elapsed = 0.0


func take_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, _npc.profile.max_health)
	if health <= 0.0:
		died.emit()
		var tree: BeehaveTree = _npc.get_node("NPCBehaviorTree") as BeehaveTree
		tree.enabled = false
		_npc.stop_moving()
		_npc.queue_free()


func _target_position() -> Vector3:
	return _npc.player.global_position + Vector3.UP * _npc.vision.player_target_height


func _ray_to(target: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		_appearance.muzzle.global_position, target, 1, [_npc.get_rid()]
	)
	return _npc.get_world_3d().direct_space_state.intersect_ray(query)


func _is_target(collider: Object) -> bool:
	return collider == _npc.player or (collider is Node and _npc.player.is_ancestor_of(collider as Node))
