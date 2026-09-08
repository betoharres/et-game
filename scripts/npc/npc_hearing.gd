class_name NPCHearing
extends Node3D

## Sensor de audição reutilizável. Não depende de nenhuma mudança em
## `player.gd`/`driveable_truck.gd`: varre periodicamente os grupos
## `characters`/`vehicles` por corpos em movimento acima de
## `movement_noise_speed_threshold` dentro de `hearing_radius`. Também expõe
## `hear_noise()` como ponto de extensão para eventos discretos futuros
## (tiro, porta), que qualquer sistema pode chamar via
## `get_tree().call_group(&"npc_hearing_listeners", &"hear_noise", pos, loudness)`
## sem precisar de referência direta a este nó.

@export var hearing_radius: float = 10.0
@export var movement_noise_speed_threshold: float = 2.0
@export var scan_interval: float = 0.25
@export var noise_memory_seconds: float = 5.0

var pending_noise_position: Vector3 = Vector3.ZERO
var pending_noise_time: float = -1000.0

var _scan_timer: float = 0.0


func _ready() -> void:
	add_to_group(&"npc_hearing_listeners")


func _physics_process(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = scan_interval
	_scan_ambient_noise()


func _scan_ambient_noise() -> void:
	var sources: Array[Node] = []
	sources.append_array(get_tree().get_nodes_in_group("characters"))
	sources.append_array(get_tree().get_nodes_in_group("vehicles"))

	for source in sources:
		if source == get_parent() or not (source is Node3D):
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
func hear_noise(position: Vector3, loudness: float = 1.0) -> void:
	var effective_radius: float = hearing_radius * maxf(loudness, 0.1)
	if global_position.distance_to(position) > effective_radius:
		return
	pending_noise_position = position
	pending_noise_time = Time.get_ticks_msec() / 1000.0


func has_pending_noise() -> bool:
	return (Time.get_ticks_msec() / 1000.0 - pending_noise_time) <= noise_memory_seconds


func consume_noise() -> Vector3:
	pending_noise_time = -1000.0
	return pending_noise_position
