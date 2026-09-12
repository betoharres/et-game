extends Node3D

const ARRIVAL_BEAM_SCENE : PackedScene = preload("res://scenes/FX/ArrivalBeam.tscn")
const MISSION_FLOW = preload("res://scripts/levels/mission_flow.gd")
const RECOVERY_SHIP_SCENE : PackedScene = preload("res://scenes/Space/RecoveryShip.tscn")
const CRASH_SITE_GUIDE_LINES : Array[String] = [
	"Esses são os destroços da nave que caiu aqui.",
	"Recupere tudo antes que os humanos encontrem a tecnologia alienígena.",
	"Use o Debris Locator para localizar as peças e leve os destroços ao ponto de recuperação.",
]

## Raio, a partir do marcador AlienCrashSite (country_town_poi), em que achar o
## local da queda revela os destroços espalhados pelo mapa.
const CRASH_SITE_DISCOVERY_RADIUS : float = 14.0
const CRASH_SITE_MARKER_NAME : String = "AlienCrashSite"
const DEBRIS_DISCOVERED_MESSAGE : String = "Local da queda encontrado! Destroços da nave detectados nas redondezas."
const MISSION_OBJECTIVE_COLLECT : String = "Colete os destroços da nave e leve-os ao ponto de recuperação."

@export_range(4.0, 80.0, 1.0) var arrival_height : float = 45.0
@export_range(2.0, 12.0, 0.5) var descent_duration : float = 5.0

@onready var player : CharacterBody3D = $Player
@onready var crash_site_guide : MissionGiverNPC = $CrashSiteGuide
@onready var mission_dialogue : MissionDialogueUI = $MissionDialogue

var _crash_site : Node3D = null
var _debris_revealed : bool = false


func _ready() -> void:
	_hide_alien_debris()
	_crash_site = _find_crash_site()
	crash_site_guide.activated.connect(_on_crash_site_guide_activated)
	mission_dialogue.closed.connect(_on_crash_site_dialogue_closed)
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
	MissionLog.update_objective(MISSION_OBJECTIVE_COLLECT)


func _on_crash_site_guide_activated() -> void:
	if mission_dialogue.visible:
		return
	crash_site_guide.set_armed(false)
	crash_site_guide.set_talking(true)
	player.set_movement_locked(true)
	mission_dialogue.open_information("Tripulante", CRASH_SITE_GUIDE_LINES)


func _on_crash_site_dialogue_closed() -> void:
	crash_site_guide.set_talking(false)
	crash_site_guide.set_armed(true)
	player.set_movement_locked(false)


func _play_arrival() -> void:
	var arrived_by_saucer : bool = MISSION_FLOW.arrival_by_saucer
	MISSION_FLOW.arrived_from_orbit = false
	MISSION_FLOW.arrival_by_saucer = false
	if player == null or not arrived_by_saucer:
		return
	var ground_position : Vector3 = player.global_position
	var start_position : Vector3 = ground_position + Vector3.UP * arrival_height
	var ship : Node3D = RECOVERY_SHIP_SCENE.instantiate() as Node3D
	ship.position = start_position - Vector3(0.0, 0.1, 0.65)
	ship.zone_path = NodePath("../RecoveryPoint/CollectionArea")
	add_child(ship)
	# A coleta só pode mover a nave depois que o passageiro descer.
	ship.set_physics_process(false)
	var arrival_saucer : Node3D = ship.get_node("Hull") as Node3D
	arrival_saucer.process_mode = Node.PROCESS_MODE_INHERIT
	arrival_saucer.get_node("CarryField").process_mode = Node.PROCESS_MODE_DISABLED
	player.set_movement_locked(true, 100.0)
	player.global_position = start_position
	player.camera_pivot.global_position = start_position

	player.camera_pivot.set_interior_camera_mode(true)
	player.set_movement_locked(false)
	var console : Node = arrival_saucer.get_node("Cabin/Console")
	await console.activated
	console.set_armed(false)
	player.camera_pivot.set_interior_camera_mode(false)
	player.set_movement_locked(true, 100.0)

	var beam : ArrivalBeam = ARRIVAL_BEAM_SCENE.instantiate() as ArrivalBeam
	add_child(beam)
	beam.configure(ground_position, arrival_height + 3.0)

	var tween : Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player, "global_position", ground_position, descent_duration)
	await tween.finished
	player.set_movement_locked(false)
	beam.fade_out(0.35)
	arrival_saucer.process_mode = Node.PROCESS_MODE_DISABLED
	ship.set_physics_process(true)
