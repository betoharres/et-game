class_name HouseDoor
extends Node3D

## Porta que gira sozinha quando alguém se aproxima e fecha ao ficar só.
## A folha é filha e gira em torno da raiz, que fica na dobradiça; o gatilho é
## irmão dela, parado no vão, senão a área giraria junto e se perderia do NPC.
@export var opener_groups: Array[StringName] = [&"characters", &"npc_actors", &"vehicles"]
@export_range(30.0, 170.0, 1.0) var open_angle: float = 95.0
## 1 abre para dentro da casa (-Z local da parede), -1 abre para fora.
@export_enum("Para fora:-1", "Para dentro:1") var open_direction: int = 1
@export_range(0.5, 6.0, 0.1) var open_speed: float = 3.4
@export_range(0.0, 10.0, 0.1) var close_delay: float = 2.5
@export_range(0.5, 4.0, 0.1) var trigger_radius: float = 2.2
@onready var leaf: Node3D = $Folha
@onready var leaf_shape: CollisionShape3D = $Folha/CollisionShape3D
@onready var trigger: Area3D = $Trigger
var _open_target: float = 0.0
var _target: float = 0.0
var _hold: float = 0.0
var _nearby: int = 0


func _ready() -> void:
	_open_target = deg_to_rad(open_angle) * float(open_direction)
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = trigger_radius
	(trigger.get_node("CollisionShape3D") as CollisionShape3D).shape = shape
	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if _nearby <= 0 and _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			_target = 0.0
	if is_equal_approx(leaf.rotation.y, _target):
		return
	leaf.rotation.y = move_toward(leaf.rotation.y, _target, open_speed * delta)
	# Aberta, a folha para de barrar: girada 90° ela fica bem no caminho de
	# quem passa, e o caminho de navegação atravessa o vão como se estivesse
	# livre -- que é o que ela é, para quem entra.
	leaf_shape.disabled = is_open()


func is_open() -> bool:
	return absf(leaf.rotation.y) > 0.05


func _on_body_entered(body: Node3D) -> void:
	if not _is_opener(body):
		return
	_nearby += 1
	_hold = close_delay
	_target = _open_target


func _on_body_exited(body: Node3D) -> void:
	if not _is_opener(body):
		return
	_nearby = maxi(0, _nearby - 1)
	if _nearby == 0:
		_hold = maxf(close_delay, 0.05)


func _is_opener(body: Node3D) -> bool:
	for group: StringName in opener_groups:
		if body.is_in_group(group):
			return true
	return false
