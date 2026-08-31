extends Node3D

## A nave em orbita da Terra, onde a partida comeca. O ET fica DENTRO dela, e a
## nave gira devagar, entao a Terra passa pela janela panoramica -- quem carrega
## o jogador junto com o convés e o ShipCarryField dentro de AlienShip.tscn.
##
## O terminal de missao lista o catalogo de fases
## (scripts/levels/level_catalog.gd). Confirmar uma fase apenas arma o feixe
## central; a aproximacao e a troca de cena so comecam quando o ET entra nele.
## Na fase, o ET chega parado, de pe na mesma nave, que world.gd traz descendo
## pelo ceu, e decide por conta propria quando acionar o pad de descida por la.

const MISSION_FLOW = preload("res://scripts/levels/mission_flow.gd")

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
const APPROACH_SURFACE_CLEARANCE : float = 55.0

var _earth_home_scale : Vector3
var _traveling : bool = false
var _pending_level : LevelDefinition = null

## O console e mobilia parafusada no convés, entao mora dentro da nave: como
## irmao dela ficaria parado no espaco enquanto a sala gira por baixo dele.
@onready var console : ConsoleButton = $AlienShip/ConsoleButton
@onready var ship : AlienShip = $AlienShip
@onready var mission_ui : MissionSelectUI = $MissionSelectUI
@onready var player : CharacterBody3D = $CharacterBody3D
@onready var earth : Node3D = $Earth
@onready var sun_light : DirectionalLight3D = $SunLight


func _ready() -> void:
	_earth_home_scale = earth.scale

	ship.set_player_inside(player, true)

	console.activated.connect(_on_console_activated)
	mission_ui.level_chosen.connect(_on_level_chosen)
	mission_ui.closed.connect(_on_mission_ui_closed)
	ship.descend_requested.connect(_on_transport_beam_entered)
	ship.set_transport_beam_enabled(false)


func _on_console_activated() -> void:
	player.set_movement_locked(true)
	mission_ui.open()


func _on_mission_ui_closed() -> void:
	if _traveling:
		return
	console.set_armed(true)
	player.set_movement_locked(false)


func _on_level_chosen(level : LevelDefinition) -> void:
	if _traveling or not level.can_launch():
		return
	_pending_level = level
	mission_ui.close()
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
	_play_approach(destination)


## Arremesso curto em direcao a Terra: nada aqui precisa ser fisicamente
## exato, so vender a sensacao de que a plataforma mergulha na atmosfera antes
## da iris fechar.
func _play_approach(level : LevelDefinition) -> void:
	# A nave passa a partida inteira girando, entao no instante em que a missao
	# e confirmada a janela pode estar apontada para o lado oposto ao da Terra.
	# Parar o giro alinhando a vista e o que garante que o arremesso seja
	# assistido, e nao ouvido de costas para uma parede.
	await ship.stop_spin_facing(earth.global_position, WINDOW_ALIGN_DURATION).finished

	player.camera_pivot.add_shake(APPROACH_SHAKE)

	var tween : Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(earth, "position", _approach_position(), APPROACH_DURATION)
	tween.tween_property(
		earth, "scale", _earth_home_scale * APPROACH_SCALE, APPROACH_DURATION
	)
	tween.tween_property(sun_light, "light_energy", APPROACH_SUN_ENERGY, APPROACH_DURATION)
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
