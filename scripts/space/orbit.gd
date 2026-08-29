extends Node3D

## A nave parada em orbita da Terra, onde a partida comeca. O terminal de
## missao lista o catalogo de fases (scripts/levels/level_catalog.gd); escolher
## uma fase fecha o terminal, puxa a Terra para perto num breve arremesso e
## entrega a cena escolhida com a iris calma de warp_to() -- o ET chega parado,
## de pe na mesma nave, que world.gd traz descendo pelo ceu da fase, e decide
## por conta propria quando acionar o pad de descida por la.

const MISSION_FLOW = preload("res://scripts/levels/mission_flow.gd")

const APPROACH_DURATION : float = 2.4
## Direcao em que a Terra vem, medida a partir da nave. So a direcao
## importa: a distancia final e calculada em _approach_position(), para a
## esfera nunca passar por cima da camera.
const APPROACH_DIRECTION : Vector3 = Vector3(0.0, -0.27, -0.96)
const APPROACH_SCALE : float = 1.4
const APPROACH_SHAKE : float = 0.4
const APPROACH_SUN_ENERGY : float = 4.2

## Raio da esfera da Terra em Surface/SphereMesh, antes da escala.
const EARTH_RADIUS : float = 110.0
## Folga que sobra entre a camera e a superficie no fim da aproximacao.
const APPROACH_SURFACE_CLEARANCE : float = 55.0

var _earth_home_scale : Vector3
var _traveling : bool = false

@onready var console : ConsoleButton = $Console
@onready var mission_ui : MissionSelectUI = $MissionSelectUI
@onready var player : CharacterBody3D = $CharacterBody3D
@onready var earth : Node3D = $Earth
@onready var sun_light : DirectionalLight3D = $SunLight


func _ready() -> void:
	_earth_home_scale = earth.scale

	console.activated.connect(_on_console_activated)
	mission_ui.level_chosen.connect(_on_level_chosen)
	mission_ui.closed.connect(_on_mission_ui_closed)


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
	_traveling = true
	MISSION_FLOW.arrived_from_orbit = true
	mission_ui.close()
	_play_approach(level)


## Arremesso curto em direcao a Terra: nada aqui precisa ser fisicamente
## exato, so vender a sensacao de que a plataforma mergulha na atmosfera antes
## da iris fechar.
func _play_approach(level : LevelDefinition) -> void:
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
