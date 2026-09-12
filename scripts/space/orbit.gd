extends Node3D

## A órbita oferece fases pelo terminal e a missão de resgate pelo tripulante.
## O terminal usa o feixe da nave grande; o resgate embarca na Saucer.

const MISSION_FLOW = preload("res://scripts/levels/mission_flow.gd")
const MISSION_SAUCER : PackedScene = preload("res://scenes/Space/MissionSaucer.tscn")

## A missão do tripulante usa a Saucer após a escolha de quando partir.
const RESCUE_MISSION_LEVEL_PATH : String = "res://scenes/Space/Levels/level_country_town.tres"
const RESCUE_MISSION_SPEAKER : String = "Tripulante"
const RESCUE_MISSION_LINES : Array[String] = [
	"ET! Captamos um sinal de emergência vindo da Terra.",
	"Um grupo de prisioneiros roubou uma nave de transporte pequena — e ela caiu numa zona rural.",
	"Precisamos recuperar a tecnologia a bordo antes que os humanos encontrem os destroços.",
	"Localize o ponto da queda e traga de volta o que sobrou. Topa a missão?",
]

const APPROACH_DURATION : float = 2.4
## Direcao em que a Terra vem, medida a partir da nave. So a direcao
## importa: a distancia final e calculada em _approach_position(), para a
## esfera nunca passar por cima da camera.
##
## O mergulho e quase horizontal de proposito: agora a aproximacao e vista de
## dentro da nave, por uma janela cujo peitoril fica na altura do chao. Uma
## descida mais inclinada leva a Terra para baixo do peitoril no meio da
## animacao, e o jogador assiste ao arremesso olhando para uma parede.
const APPROACH_DIRECTION : Vector3 = Vector3(0.0, -0.12, -0.99)

## Quanto tempo a nave leva para parar de girar e apontar a janela para a Terra
## antes do arremesso comecar.
const WINDOW_ALIGN_DURATION : float = 1.6
const APPROACH_SCALE : float = 1.4
const APPROACH_SHAKE : float = 0.4
const APPROACH_SUN_ENERGY : float = 4.2

## Raio da esfera da Terra em Surface/SphereMesh, antes da escala.
const EARTH_RADIUS : float = 110.0
## Folga que sobra entre a camera e a superficie no fim da aproximacao.
const APPROACH_SURFACE_CLEARANCE : float = 70.0

var _earth_home_scale : Vector3
var _traveling : bool = false
var _pending_level : LevelDefinition = null
var _rescue_accepted : bool = false
var _choosing_departure : bool = false
var _mission_transport : Node3D = null

## O console e mobilia parafusada no convés, entao mora dentro da nave: como
## irmao dela ficaria parado no espaco enquanto a sala gira por baixo dele.
@onready var console : ConsoleButton = $AlienShip/ConsoleButton
@onready var ship : AlienShip = $AlienShip
@onready var mission_ui : MissionSelectUI = $MissionSelectUI
@onready var mission_npc : MissionGiverNPC = $AlienShip/MissionGiver
@onready var mission_dialogue : MissionDialogueUI = $MissionDialogue
@onready var player : CharacterBody3D = $CharacterBody3D
@onready var earth : Node3D = $Earth
@onready var sun_light : DirectionalLight3D = $SunLight


func _ready() -> void:
	_earth_home_scale = earth.scale

	ship.set_player_inside(player, true)

	console.activated.connect(_on_console_activated)
	mission_ui.level_chosen.connect(_on_level_chosen)
	mission_ui.closed.connect(_on_mission_ui_closed)
	mission_npc.activated.connect(_on_mission_npc_activated)
	mission_dialogue.accepted.connect(_on_rescue_mission_accepted)
	mission_dialogue.declined.connect(_on_rescue_mission_declined)
	ship.descend_requested.connect(_on_transport_beam_entered)
	ship.set_transport_beam_enabled(false)


func _on_console_activated() -> void:
	if _traveling or mission_dialogue.visible:
		return
	mission_npc.set_armed(false)
	player.set_movement_locked(true)
	mission_ui.open()


func _on_mission_ui_closed() -> void:
	if _traveling:
		return
	console.set_armed(true)
	mission_npc.set_armed(true)
	player.set_movement_locked(false)


func _on_mission_npc_activated() -> void:
	if _traveling or mission_ui.visible or mission_dialogue.visible:
		return
	console.set_armed(false)
	mission_npc.set_armed(false)
	mission_npc.set_talking(true)
	player.set_movement_locked(true)
	if _rescue_accepted:
		_open_departure_choice()
	else:
		mission_dialogue.open(RESCUE_MISSION_SPEAKER, RESCUE_MISSION_LINES)


func _on_rescue_mission_accepted() -> void:
	if _traveling:
		return
	if _choosing_departure:
		_launch_rescue()
		return
	_rescue_accepted = true
	mission_npc.set_mission_accepted(true)
	_open_departure_choice()


func _open_departure_choice() -> void:
	_choosing_departure = true
	# Nenhum destino antigo pode disparar enquanto a partida está adiada.
	_pending_level = null
	ship.set_transport_beam_enabled(false)
	mission_dialogue.open(RESCUE_MISSION_SPEAKER, [
		"A Saucer está pronta para levar você até a Terra. Quer ir agora? Se preferir se preparar, fale comigo quando estiver pronto."
	], "Ir agora", "Ir depois")


func _launch_rescue() -> void:
	var level : LevelDefinition = load(RESCUE_MISSION_LEVEL_PATH) as LevelDefinition
	if level == null or not level.can_launch():
		push_error("Fase da missão de resgate indisponível: %s" % RESCUE_MISSION_LEVEL_PATH)
		_on_rescue_mission_declined()
		return
	_traveling = true
	_choosing_departure = false
	_pending_level = null
	mission_npc.set_talking(false)
	mission_npc.set_armed(false)
	console.set_armed(false)
	ship.set_transport_beam_enabled(false)
	ship.set_player_inside(player, false)
	ship.get_node("CarryField").release_passenger(player)
	_mission_transport = MISSION_SAUCER.instantiate() as Node3D
	_mission_transport.position = Vector3(110.0, 25.0, -10.0)
	add_child(_mission_transport)
	await _mission_transport.board(player)
	MISSION_FLOW.arrived_from_orbit = true
	MISSION_FLOW.arrival_by_saucer = true
	_mission_transport.begin_approach_audio(WINDOW_ALIGN_DURATION + APPROACH_DURATION)
	_play_approach(level, _mission_transport)


func _on_rescue_mission_declined() -> void:
	_choosing_departure = false
	console.set_armed(true)
	mission_npc.set_armed(true)
	mission_npc.set_talking(false)
	player.set_movement_locked(false)


func _on_level_chosen(level : LevelDefinition) -> void:
	if _traveling or not level.can_launch():
		return
	if level.scene_path == "res://scenes/CountryTown/CountryTown.tscn":
		mission_ui.close()
		_on_mission_npc_activated()
		return
	_pending_level = level
	mission_ui.close()
	ship.play_security_alert()
	ship.set_transport_beam_enabled(true)


func _on_transport_beam_entered() -> void:
	if _traveling or _pending_level == null or not _pending_level.can_launch():
		return
	var destination : LevelDefinition = _pending_level
	_pending_level = null
	_traveling = true
	console.set_armed(false)
	ship.set_transport_beam_enabled(false)
	MISSION_FLOW.arrived_from_orbit = true
	MISSION_FLOW.arrival_by_saucer = false
	ship.begin_approach_audio(WINDOW_ALIGN_DURATION + APPROACH_DURATION)
	_play_approach(destination, ship)


## Arremesso curto em direcao a Terra: nada aqui precisa ser fisicamente
## exato, so vender a sensacao de que a plataforma mergulha na atmosfera antes
## da iris fechar.
func _play_approach(level : LevelDefinition, transport : Node3D) -> void:
	# A nave passa a partida inteira girando, entao no instante em que a missao
	# e confirmada a janela pode estar apontada para o lado oposto ao da Terra.
	# Parar o giro alinhando a vista e o que garante que o arremesso seja
	# assistido, e nao ouvido de costas para uma parede.
	var alignment : Tween = transport.stop_spin_facing(earth.global_position, WINDOW_ALIGN_DURATION)
	await alignment.finished

	player.camera_pivot.add_shake(APPROACH_SHAKE)

	var tween : Tween = create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(earth, "position", _approach_position(), APPROACH_DURATION)
	tween.tween_property(
		earth, "scale", _earth_home_scale * APPROACH_SCALE, APPROACH_DURATION
	)
	tween.tween_property(sun_light, "light_energy", APPROACH_SUN_ENERGY, APPROACH_DURATION)
	if transport == _mission_transport:
		tween.tween_property(transport, "position",
			transport.position + APPROACH_DIRECTION.normalized() * 28.0, APPROACH_DURATION)
	await tween.finished

	var scene_transition : Node = get_node("/root/SceneTransition")
	scene_transition.warp_to(level.scene_path, Color.BLACK)


## Onde a Terra para no fim da aproximacao. A distancia sai do raio da esfera
## e nao de um valor escolhido a olho: a Terra tem 110 de raio e a aproximacao
## ainda a aumenta, entao um alvo perto demais poe a camera DENTRO da esfera --
## e como o mesh so tem as faces de fora, o planeta some e o jogador ve o ceu
## do outro lado, pelo avesso.
func _approach_position() -> Vector3:
	var scaled_radius : float = EARTH_RADIUS * APPROACH_SCALE
	var distance : float = scaled_radius + APPROACH_SURFACE_CLEARANCE
	# Medida a partir da camera, nao da origem da cena: e ela que nao pode
	# atravessar a superficie.
	var camera_position : Vector3 = player.camera_pivot.camera.global_position
	return to_local(camera_position) + APPROACH_DIRECTION.normalized() * distance
