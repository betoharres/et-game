extends Node3D

## A nave em orbita da Terra, onde a partida comeca. O ET fica DENTRO dela, e a
## nave gira devagar, entao a Terra passa pela janela panoramica -- quem carrega
## o jogador junto com o convés e o ShipCarryField dentro de AlienShip.tscn.
##
## O terminal de missao lista o catalogo de fases
## (scripts/levels/level_catalog.gd); escolher uma fase fecha o terminal, para o
## giro alinhando a janela com a Terra, puxa a Terra para perto num breve
## arremesso e entrega a cena escolhida com a iris calma de warp_to() -- o ET
## chega parado, de pe na mesma nave, que world.gd traz descendo pelo ceu da
## fase, e decide por conta propria quando acionar o pad de descida por la.

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

## O console e mobilia parafusada no convés, entao mora dentro da nave: como
## irmao dela ficaria parado no espaco enquanto a sala gira por baixo dele.
@onready var console : ConsoleButton = $AlienShip/Console
@onready var ship : AlienShip = $AlienShip
@onready var mission_ui : MissionSelectUI = $MissionSelectUI
@onready var player : CharacterBody3D = $CharacterBody3D
@onready var earth : Node3D = $Earth
@onready var sun_light : DirectionalLight3D = $SunLight


func _ready() -> void:
	_earth_home_scale = earth.scale

	# Aqui o ET nunca sai da nave, entao o casco nunca precisa ser desenhado:
	# sem isto a janela panoramica mostra o interior oco do casco em vez da
	# Terra (ver AlienShip.HULL_CULL_BIT).
	ship.set_hull_visible_to_player(player, false)

	var shell : Node3D = ship.get_node("Interior/Shell")
	var deck : MeshInstance3D = shell.get_node("Deck")
	var seen : Array[Vector2] = []
	for v : Vector3 in deck.mesh.get_faces():
		var xz : Vector2 = Vector2(snappedf(v.x, 0.01), snappedf(v.z, 0.01))
		if not seen.has(xz):
			seen.append(xz)
	print("[geo] PISO vertices: ", seen)

	for nome : String in ["WallBack", "GlassRight", "GlassLeft"]:
		var w : MeshInstance3D = shell.get_node(nome)
		var box : BoxMesh = w.mesh as BoxMesh
		var meio : float = box.size.x * 0.5
		var eixo : Vector3 = w.transform.basis.x.normalized()
		var a : Vector3 = w.position - eixo * meio
		var b : Vector3 = w.position + eixo * meio
		print("[geo] %-11s de (%6.2f,%6.2f) a (%6.2f,%6.2f)  comp=%.2f esp=%.2f" % [
			nome, a.x, a.z, b.x, b.z, box.size.x, box.size.z])

	var pad : Node3D = ship.get_node("Interior/DescendPad")
	print("[geo] DescendPad em (%.2f, %.2f, %.2f)" % [
		pad.position.x, pad.position.y, pad.position.z])
	var roof : Node3D = shell.get_node("Roof")
	print("[geo] Roof y=%.2f rot_y=%.1f  |  Deck y=%.2f rot_y=%.1f" % [
		roof.position.y, rad_to_deg(roof.rotation.y),
		deck.position.y, rad_to_deg(deck.rotation.y)])

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
