extends Node3D

const ARRIVAL_BEAM_SCENE : PackedScene = preload("res://scenes/FX/ArrivalBeam.tscn")
const MISSION_FLOW = preload("res://scripts/levels/mission_flow.gd")
const MISSION_SAUCER : PackedScene = preload("res://scenes/Space/MissionSaucer.tscn")

## Raio, a partir do marcador AlienCrashSite (country_town_poi), em que achar o
## local da queda revela os destroços espalhados pelo mapa.
const CRASH_SITE_DISCOVERY_RADIUS : float = 14.0
const CRASH_SITE_MARKER_NAME : String = "AlienCrashSite"
const DEBRIS_DISCOVERED_MESSAGE : String = "Local da queda encontrado! Destroços da nave detectados nas redondezas."

@export_range(4.0, 80.0, 1.0) var arrival_height : float = 45.0
@export_range(2.0, 12.0, 0.5) var descent_duration : float = 5.0

@onready var player : CharacterBody3D = $Player
@onready var ship : Node3D = $RecoveryPoint/RecoveryShip

var _crash_site : Node3D = null
var _debris_revealed : bool = false


func _ready() -> void:
	_hide_alien_debris()
	_crash_site = _find_crash_site()
	_play_arrival.call_deferred()


func _physics_process(_delta : float) -> void:
	if _debris_revealed or _crash_site == null or player == null:
		return
	if player.global_position.distance_to(_crash_site.global_position) <= CRASH_SITE_DISCOVERY_RADIUS:
		reveal_debris()


## A missão só oferece o objetivo "buscar os detritos" depois que a nave é
## encontrada: os destroços nascem ocultos e inertes até esse ponto.
func _hide_alien_debris() -> void:
	for node : Node in get_tree().get_nodes_in_group("alien_debris"):
		if node.has_method("set_discovered"):
			node.call("set_discovered", false)


func _find_crash_site() -> Node3D:
	for node : Node in get_tree().get_nodes_in_group("country_town_poi"):
		if node.name == CRASH_SITE_MARKER_NAME:
			return node as Node3D
	push_warning("Marcador %s não encontrado; destroços continuam ocultos." % CRASH_SITE_MARKER_NAME)
	return null


## Chamado ao entrar na área do crash site; exposto como público para testes
## que precisam simular o objetivo já cumprido sem andar até lá.
func reveal_debris() -> void:
	if _debris_revealed:
		return
	_debris_revealed = true
	for node : Node in get_tree().get_nodes_in_group("alien_debris"):
		if node.has_method("set_discovered"):
			node.call("set_discovered", true)
	var inventory : Node = player.get_node_or_null("ExplorationInventory")
	if inventory != null:
		inventory.emit_signal("feedback", DEBRIS_DISCOVERED_MESSAGE)


func _play_arrival() -> void:
	if player == null or ship == null:
		return
	var ground_position : Vector3 = player.global_position
	var start_position : Vector3 = ground_position + Vector3.UP * arrival_height
	var arrival_saucer : Node3D = null
	if MISSION_FLOW.arrival_by_saucer:
		arrival_saucer = MISSION_SAUCER.instantiate() as Node3D
		arrival_saucer.position = start_position - Vector3(0.0, 0.1, 0.65)
		add_child(arrival_saucer)
		arrival_saucer.set_fall_guard_enabled(false)
		# O feixe atravessa o piso: a física da cabine não participa da descida.
		arrival_saucer.get_node("CarryField").process_mode = Node.PROCESS_MODE_DISABLED
	MISSION_FLOW.arrived_from_orbit = false
	MISSION_FLOW.arrival_by_saucer = false
	player.set_movement_locked(true, 100.0)
	player.global_position = start_position
	player.camera_pivot.global_position = start_position
	if arrival_saucer != null:
		await get_tree().create_timer(1.2).timeout

	var beam : ArrivalBeam = ARRIVAL_BEAM_SCENE.instantiate() as ArrivalBeam
	add_child(beam)
	beam.configure(ground_position, arrival_height + 3.0)

	var tween : Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player, "global_position", ground_position, descent_duration)
	await tween.finished
	player.set_movement_locked(false)
	beam.fade_out(0.35)
	if arrival_saucer != null:
		var departure : Tween = create_tween()
		departure.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		departure.tween_property(arrival_saucer, "position:y", arrival_saucer.position.y + 120.0, 4.0)
		departure.tween_callback(arrival_saucer.queue_free)
