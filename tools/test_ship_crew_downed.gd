extends SceneTree

## Confere o tripulante caido no chao da nave: a pose deitada precisa se manter
## e o jogador precisa conseguir pega-lo no colo e solta-lo de volta.

const CREW_SCENE : String = "res://scenes/NPCs/ShipCrewAlien.tscn"
const PLAYER_SCENE : String = "res://scenes/Player.tscn"
const HIPS_BONE : String = "mixamorig_Hips"
const SETTLE_FRAMES : int = 12
const MAXIMUM_HEIGHT_RATIO : float = 0.6
const PICKUP_FRAME_LIMIT : int = 3000
const MAXIMUM_SOCKET_DISTANCE : float = 0.25
const MAXIMUM_BONE_STRETCH : float = 0.01

enum Step {
	SETTLE,
	LIFTING,
	CARRIED,
}

var _standing : Node3D = null
var _downed : Node3D = null
var _player : Node3D = null
var _step : Step = Step.SETTLE
var _frames : int = 0


func _initialize() -> void:
	var crew_scene : PackedScene = load(CREW_SCENE) as PackedScene
	var player_scene : PackedScene = load(PLAYER_SCENE) as PackedScene
	if crew_scene == null or player_scene == null:
		print("FALHA: nao foi possivel carregar as cenas de teste")
		quit(1)
		return

	root.add_child(_build_floor())
	_standing = crew_scene.instantiate() as Node3D
	_downed = crew_scene.instantiate() as Node3D
	_downed.set("movement_mode", 2)
	_player = player_scene.instantiate() as Node3D
	root.add_child(_standing)
	root.add_child(_downed)
	root.add_child(_player)
	_standing.position = Vector3(20.0, 0.0, 0.0)
	_downed.position = Vector3(0.0, 0.0, 0.0)
	_player.position = Vector3(0.5, 0.0, 0.0)


## Sem chao os corpos caem em queda livre e a medida do colo perde sentido.
func _build_floor() -> StaticBody3D:
	var floor_body : StaticBody3D = StaticBody3D.new()
	var shape : CollisionShape3D = CollisionShape3D.new()
	var box : BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	return floor_body


func _process(_delta : float) -> bool:
	_frames += 1
	match _step:
		Step.SETTLE:
			return _check_downed_pose()
		Step.LIFTING:
			return _check_lift_finished()
		Step.CARRIED:
			return _check_release()
	return false


func _check_downed_pose() -> bool:
	if _frames < SETTLE_FRAMES:
		return false

	var standing_height : float = _hips_height(_standing)
	var downed_height : float = _hips_height(_downed)
	if standing_height <= 0.0:
		return _fail("quadril do tripulante em pe nao foi encontrado")

	var limit : float = standing_height * MAXIMUM_HEIGHT_RATIO
	print("quadril em pe: %.3f m | quadril caido: %.3f m | limite: %.3f m" % [
		standing_height,
		downed_height,
		limit,
	])
	if downed_height > limit:
		return _fail(
			"o tripulante DOWNED ficou em pe (quadril em %.3f m)" % downed_height
		)

	if not _downed.is_in_group("carriable_characters"):
		return _fail("o tripulante caido nao entrou no grupo carriable_characters")

	if not bool(_player.call("try_carry_character")):
		return _fail("try_carry_character() recusou o tripulante a 0.5 m")

	print("OK: pose deitada mantida e coleta aceita")
	_frames = 0
	_step = Step.LIFTING
	return false


## O corpo carregado nao e reparentado: e a pose autorada de ser carregado, com
## a raiz alinhada para o quadril cair no CarrySocket. Mede-se a distancia entre
## os dois e o comprimento dos ossos, que denuncia qualquer membro esticado.
func _check_lift_finished() -> bool:
	if float(_player.get("_carry_pickup_timer")) > 0.0:
		if _frames >= PICKUP_FRAME_LIMIT:
			return _fail(
				"a subida nao terminou em %d quadros" % PICKUP_FRAME_LIMIT
			)
		return false

	var socket : Node3D = _player.get_node_or_null("CarrySocket") as Node3D
	if socket == null:
		return _fail("o carregador nao tem CarrySocket")

	var skeleton : Skeleton3D = _find_skeleton(_downed)
	if skeleton == null:
		return _fail("o esqueleto do tripulante nao foi encontrado")

	var hips : int = skeleton.find_bone(HIPS_BONE)
	if hips < 0:
		return _fail("o osso do quadril nao foi encontrado")

	var distance : float = skeleton.to_global(
		skeleton.get_bone_global_pose(hips).origin
	).distance_to(socket.global_position)
	print("OK: no colo, quadril a %.3f m do CarrySocket" % distance)
	if distance > MAXIMUM_SOCKET_DISTANCE:
		return _fail(
			"o quadril parou a %.3f m do soquete (limite %.3f m)"
			% [distance, MAXIMUM_SOCKET_DISTANCE]
		)

	var stretch : float = _worst_bone_stretch(skeleton)
	print("maior desvio de comprimento de osso: %.4f m" % stretch)
	if stretch > MAXIMUM_BONE_STRETCH:
		return _fail(
			"a malha esticou: um osso desviou %.4f m do repouso (limite %.4f m)"
			% [stretch, MAXIMUM_BONE_STRETCH]
		)

	_player.call("release_carried_character")
	_step = Step.CARRIED
	return false


## Um osso so gira: a distancia ate o pai e o comprimento do repouso. Qualquer
## desvio significa que alguma coisa escreveu translacao no esqueleto -- e uma
## malha esticada. So vale enquanto a pose vier do AnimationPlayer: um
## SkeletonModifier3D ativo escreve depois desta leitura.
func _worst_bone_stretch(skeleton : Skeleton3D) -> float:
	var worst : float = 0.0
	for bone : int in skeleton.get_bone_count():
		if skeleton.get_bone_parent(bone) < 0:
			continue

		worst = maxf(worst, absf(
			skeleton.get_bone_pose_position(bone).length()
			- skeleton.get_bone_rest(bone).origin.length()
		))

	return worst


func _check_release() -> bool:
	if not _downed.is_in_group("carriable_characters"):
		return _fail("o tripulante solto nao voltou a ser carregavel")

	print("OK: solto no chao e carregavel de novo")
	quit(0)
	return true


func _fail(message : String) -> bool:
	print("FALHA: " + message)
	quit(1)
	return true


func _hips_height(crew : Node3D) -> float:
	var skeleton : Skeleton3D = _find_skeleton(crew)
	if skeleton == null:
		return -1.0

	var bone : int = skeleton.find_bone(HIPS_BONE)
	if bone < 0:
		return -1.0

	return skeleton.get_bone_global_pose(bone).origin.y


func _find_skeleton(node : Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D

	for child : Node in node.get_children():
		var found : Skeleton3D = _find_skeleton(child)
		if found != null:
			return found

	return null
