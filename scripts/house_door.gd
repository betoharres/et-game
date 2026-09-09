class_name HouseDoor
extends Node3D

## Porta de folha única. NPC abre só de chegar; quem joga aperta "interact"
## diante do aviso que aparece na folha. A folha é filha e gira em torno da
## raiz, que fica na dobradiça; o gatilho é irmão dela, parado no vão, senão a
## área giraria junto e se perderia do NPC. Trancada, ela só cede a quem tem
## chave ou a quem já está do lado de dentro.
signal lock_changed(is_locked: bool)

@export_group("Quem abre")
## Abrem só de chegar perto: NPC não tem teclado.
@export var auto_open_groups: Array[StringName] = [&"npc_actors"]
## Abrem com a ação "interact"; só estes enxergam o aviso na porta.
@export var manual_groups: Array[StringName] = [&"characters"]
## Levam chave: destrancam ao abrir, de qualquer lado.
@export var key_groups: Array[StringName] = [&"npc_actors"]

@export_group("Tranca")
@export var starts_locked: bool = false
## Sem chave ainda dá para destrancar por dentro: é o trinco do lado de cá.
@export var unlockable_from_inside: bool = true

@export_group("Folha")
@export_range(30.0, 170.0, 1.0) var open_angle: float = 95.0
## 1 abre para dentro da casa (-Z local da parede), -1 abre para fora.
@export_enum("Para fora:-1", "Para dentro:1") var open_direction: int = 1
@export_range(0.5, 6.0, 0.1) var open_speed: float = 3.4
@export_range(0.0, 10.0, 0.1) var close_delay: float = 2.5
@export_range(0.5, 4.0, 0.1) var trigger_radius: float = 2.2

@onready var leaf: Node3D = $Folha
@onready var leaf_shape: CollisionShape3D = $Folha/CollisionShape3D
@onready var trigger: Area3D = $Trigger

var locked: bool = false
var _open_target: float = 0.0
var _target: float = 0.0
var _hold: float = 0.0
var _auto_nearby: int = 0
## Aberta na mão fica aberta: fechar também é decisão de quem abriu.
var _held_open: bool = false
var _manual_bodies: Array[Node3D] = []
var _prompt: Label3D
var _audio: AudioStreamPlayer3D

# Sintetizar por porta custa caro e o resultado é sempre o mesmo.
static var _creak_stream: AudioStreamWAV
static var _latch_stream: AudioStreamWAV
static var _rattle_stream: AudioStreamWAV


func _ready() -> void:
	_open_target = deg_to_rad(open_angle) * float(open_direction)
	locked = starts_locked
	add_to_group(&"house_doors")
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = trigger_radius
	(trigger.get_node("CollisionShape3D") as CollisionShape3D).shape = shape
	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)
	_build_prompt()
	_build_audio()
	_refresh_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"interact") or event.is_echo():
		return
	var body: Node3D = _manual_body()
	if body == null:
		return
	interact(body)
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _auto_nearby <= 0 and not _held_open and _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			_target = 0.0
	_turn_leaf(delta)


## Uma tecla, dois sentidos: aberta fecha, fechada abre. Devolve false quando a
## tranca barra o corpo, para quem chamou dar o próprio retorno.
func interact(body: Node3D) -> bool:
	if is_open():
		close()
		return true
	if locked:
		if not _can_unlock(body):
			_play(_rattle(), 1.0)
			return false
		set_locked(false)
	return open_for(body)


func open_for(body: Node3D) -> bool:
	if locked:
		if not _carries_key(body):
			return false
		set_locked(false)
	if not is_equal_approx(_target, _open_target):
		_play(_creak(), randf_range(0.94, 1.06))
	_target = _open_target
	_hold = close_delay
	_held_open = _is_manual(body)
	return true


func close() -> void:
	_held_open = false
	_hold = 0.0
	if not is_zero_approx(_target):
		_play(_creak(), randf_range(0.9, 1.0))
	_target = 0.0


func set_locked(value: bool) -> void:
	if locked == value:
		return
	locked = value
	_play(_latch(), 1.15 if value else 0.95)
	_refresh_prompt()
	lock_changed.emit(locked)


func is_open() -> bool:
	return absf(leaf.rotation.y) > 0.05


## Contrato consumido por `player.gd`: com a porta ao alcance, o "interact" é
## dela, não da coleta de itens.
func reserves_interaction_for(character: Node3D) -> bool:
	return _manual_bodies.has(character)


func _turn_leaf(delta: float) -> void:
	if is_equal_approx(leaf.rotation.y, _target):
		return
	# Dobradiça de verdade não parte na velocidade final: a folha ganha corpo no
	# meio do arco e chega mansa nas duas pontas.
	var span: float = maxf(absf(_open_target), 0.001)
	var remaining: float = clampf(absf(_target - leaf.rotation.y) / span, 0.0, 1.0)
	var speed: float = open_speed * (0.3 + 0.7 * sin(PI * remaining))
	leaf.rotation.y = move_toward(leaf.rotation.y, _target, speed * delta)
	# Aberta, a folha para de barrar: girada 90° ela fica bem no caminho de
	# quem passa, e o caminho de navegação atravessa o vão como se estivesse
	# livre -- que é o que ela é, para quem entra.
	leaf_shape.disabled = is_open()
	if is_zero_approx(_target) and is_zero_approx(leaf.rotation.y):
		_play(_latch(), 0.85)
	_refresh_prompt()


func _on_body_entered(body: Node3D) -> void:
	if _is_auto(body):
		_auto_nearby += 1
		_hold = close_delay
		if locked and _carries_key(body):
			set_locked(false)
		open_for(body)
		return
	if _is_manual(body) and not _manual_bodies.has(body):
		_manual_bodies.append(body)
		_refresh_prompt()


func _on_body_exited(body: Node3D) -> void:
	if _is_auto(body):
		_auto_nearby = maxi(0, _auto_nearby - 1)
		if _auto_nearby == 0:
			_hold = maxf(close_delay, 0.05)
		return
	if _manual_bodies.has(body):
		_manual_bodies.erase(body)
		_refresh_prompt()


func _manual_body() -> Node3D:
	for index: int in range(_manual_bodies.size() - 1, -1, -1):
		if not is_instance_valid(_manual_bodies[index]):
			_manual_bodies.remove_at(index)
	if _manual_bodies.is_empty():
		return null
	return _manual_bodies[0]


func _in_groups(body: Node3D, groups: Array[StringName]) -> bool:
	for group: StringName in groups:
		if body.is_in_group(group):
			return true
	return false


func _is_auto(body: Node3D) -> bool:
	return _in_groups(body, auto_open_groups)


## Quem abre sozinho nunca conta como manual, mesmo estando nos dois grupos.
func _is_manual(body: Node3D) -> bool:
	return not _is_auto(body) and _in_groups(body, manual_groups)


func _carries_key(body: Node3D) -> bool:
	return _in_groups(body, key_groups)


func _can_unlock(body: Node3D) -> bool:
	if body == null:
		return false
	return _carries_key(body) or (unlockable_from_inside and _is_inside(body))


## O interior fica no -Z local da parede, o mesmo lado que `open_direction`
## chama de "para dentro".
func _is_inside(body: Node3D) -> bool:
	return to_local(body.global_position).z < 0.0


func _build_prompt() -> void:
	# Criado em código porque `tools/build_house_01.gd` regrava as cenas das
	# portas: nó posto à mão no .tscn some na próxima geração.
	_prompt = Label3D.new()
	_prompt.name = "Aviso"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.fixed_size = true
	_prompt.pixel_size = 0.0011
	_prompt.outline_size = 12
	_prompt.modulate = Color(1.0, 0.96, 0.82)
	_prompt.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_prompt.render_priority = 1
	_prompt.position = Vector3(0.5, 1.75, 0.0)
	_prompt.visible = false
	add_child(_prompt)


func _build_audio() -> void:
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "Audio"
	_audio.max_distance = 18.0
	_audio.unit_size = 3.0
	_audio.volume_db = -6.0
	_audio.position = Vector3(0.5, 1.0, 0.0)
	add_child(_audio)


func _refresh_prompt() -> void:
	if _prompt == null:
		return
	var body: Node3D = _manual_body()
	_prompt.visible = body != null
	if body == null:
		return
	var key: String = _action_key()
	if is_open():
		_prompt.text = "[%s] Fechar" % key
	elif not locked:
		_prompt.text = "[%s] Abrir" % key
	elif _can_unlock(body):
		_prompt.text = "[%s] Destrancar" % key
	else:
		_prompt.text = "Trancada"


func _action_key() -> String:
	for event: InputEvent in InputMap.action_get_events(&"interact"):
		if event is InputEventKey:
			var key_event: InputEventKey = event as InputEventKey
			var keycode: Key = key_event.physical_keycode
			if keycode == KEY_NONE:
				keycode = key_event.keycode
			return OS.get_keycode_string(keycode)
	return "E"


func _play(stream: AudioStreamWAV, pitch: float) -> void:
	if _audio == null:
		return
	_audio.stream = stream
	_audio.pitch_scale = pitch
	_audio.play()


func _creak() -> AudioStreamWAV:
	if _creak_stream == null:
		_creak_stream = ProceduralSFX.door_creak()
	return _creak_stream


func _latch() -> AudioStreamWAV:
	if _latch_stream == null:
		_latch_stream = ProceduralSFX.door_latch()
	return _latch_stream


func _rattle() -> AudioStreamWAV:
	if _rattle_stream == null:
		_rattle_stream = ProceduralSFX.door_rattle()
	return _rattle_stream
