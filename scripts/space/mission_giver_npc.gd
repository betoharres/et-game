class_name MissionGiverNPC
extends "res://scripts/space/ship_crew_alien.gd"

## Tripulante que oferece a missão de resgate por diálogo, na nave em órbita.
## Reaproveita o corpo cenográfico do ShipCrewAlien; só acrescenta detecção de
## proximidade e o prompt de interação, no mesmo padrão independente do
## ConsoleButton (scripts/space/console_button.gd) — não passa pela arbitragem
## de coleta/porta/entrega do player.gd, que não conhece diálogo.

signal activated

const DIALOGUE_GROUP : StringName = &"dialogue_sources"

@export var interact_radius : float = 2.2
@export var marker_height : float = 1.7
@export_range(0.0, 0.3, 0.01) var marker_bob_amount : float = 0.08
@export_range(0.1, 6.0, 0.1) var marker_bob_speed : float = 2.0
@export_color_no_alpha var marker_color : Color = Color(1.0, 0.85, 0.2)

var _armed : bool = true
var _talking : bool = false
var _mission_accepted : bool = false
var _player : CharacterBody3D = null
var _marker : Label3D = null
var _marker_phase : float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group(DIALOGUE_GROUP)
	_player = get_tree().get_first_node_in_group("characters") as CharacterBody3D
	_marker = _build_marker()
	_update_marker_visibility()


func _process(delta : float) -> void:
	if _marker != null and _marker.visible:
		_marker_phase += delta * marker_bob_speed
		_marker.position.y = marker_height + sin(_marker_phase) * marker_bob_amount
	if not is_player_nearby():
		return
	if Input.is_action_just_pressed("interact"):
		activated.emit()


## Enquanto dura o diálogo, o corpo para de vagar e só acompanha o jogador
## com o olhar — quem decide não mover é este método, não a base (que
## continuaria fazendo o tripulante andar por conta própria).
func _physics_process(delta : float) -> void:
	if _talking:
		velocity = Vector3.ZERO
		if is_instance_valid(_player):
			var up : Vector3 = Vector3.UP
			var direction : Vector3 = (_player.global_position - global_position).slide(up)
			if direction.length_squared() > 0.0001:
				_face_direction(direction, up, delta)
		_update_animation()
		return
	super._physics_process(delta)


func is_player_nearby() -> bool:
	return (
		_armed
		and is_instance_valid(_player)
		and global_position.distance_to(_player.global_position) <= interact_radius
	)


## Desarma durante o diálogo, para o mesmo toque de "interact" que avança uma
## fala não reabrir a conversa assim que ela fecha.
func set_armed(armed : bool) -> void:
	_armed = armed


## Trava o corpo virado para o jogador enquanto a conversa dura; ver
## _physics_process().
func set_talking(talking : bool) -> void:
	_talking = talking
	_update_marker_visibility()


## O "!" só marca a missão ainda não aceita. Uma vez a bordo do transporte,
## não faz sentido continuar sinalizando o mesmo tripulante.
func set_mission_accepted(accepted : bool) -> void:
	_mission_accepted = accepted
	_update_marker_visibility()


func _update_marker_visibility() -> void:
	if _marker != null:
		_marker.visible = not _talking and not _mission_accepted


func _build_marker() -> Label3D:
	var label : Label3D = Label3D.new()
	label.text = "!"
	label.font_size = 64
	label.outline_size = 12
	label.modulate = marker_color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, marker_height, 0.0)
	add_child(label)
	return label
