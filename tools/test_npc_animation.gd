extends SceneTree

## Verifica que cada cena de NPC carrega Idle/Walk no AnimationPlayer e que as
## trilhas atingem de fato os ossos do modelo — sem isso o personagem fica na
## bind pose (T-pose) ou deformado, porque a biblioteca Synty em
## `Temporarios/Animations/Polygon/` só casa com o rig de
## `Temporarios/Animations/Meshes/PolygonSyntyCharacter.fbx`.

const SCENES: Array[String] = [
	"res://scenes/NPCs/Farmer.tscn",
	"res://scenes/NPCs/Townsperson.tscn",
	"res://scenes/NPCs/PoliceOfficer.tscn",
]
const SETTLE_FRAMES: int = 5
## Quanto o osso precisa sair da rest pose para provar que a trilha foi aplicada.
const MINIMUM_POSE_DELTA: float = 0.001


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)

	var failures: Array[String] = []

	for scene_path: String in SCENES:
		var npc: NPCActor = (load(scene_path) as PackedScene).instantiate() as NPCActor
		world.add_child(npc)
		for i: int in range(SETTLE_FRAMES):
			await physics_frame

		var animation: NPCAnimation = npc.get_node_or_null("NPCAnimation") as NPCAnimation
		if animation == null:
			failures.append("%s: sem no NPCAnimation" % scene_path)
			npc.queue_free()
			continue

		var animation_player: AnimationPlayer = (
			animation.get_node_or_null(animation.animation_player_path) as AnimationPlayer
		)
		if animation_player == null:
			failures.append("%s: animation_player_path nao resolveu" % scene_path)
			npc.queue_free()
			continue

		var has_idle: bool = animation_player.has_animation(&"Idle")
		var has_walk: bool = animation_player.has_animation(&"Walk")
		if not has_idle or not has_walk:
			failures.append("%s: faltou Idle/Walk no AnimationPlayer" % scene_path)
			npc.queue_free()
			continue

		# A animação precisa mover ossos de verdade: se as trilhas apontarem
		# para um esqueleto incompatível, a pose fica idêntica à rest pose.
		var skeleton: Skeleton3D = npc.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton == null:
			failures.append("%s: sem Skeleton3D" % scene_path)
			npc.queue_free()
			continue

		animation_player.play(&"Walk")
		animation_player.seek(0.4, true)
		await physics_frame

		var moved_bones: int = 0
		for bone: int in range(skeleton.get_bone_count()):
			var rest: Transform3D = skeleton.get_bone_rest(bone)
			var pose: Transform3D = skeleton.get_bone_pose(bone)
			if rest.origin.distance_to(pose.origin) > MINIMUM_POSE_DELTA:
				moved_bones += 1
				continue
			if absf(rest.basis.get_rotation_quaternion().angle_to(
				pose.basis.get_rotation_quaternion()
			)) > MINIMUM_POSE_DELTA:
				moved_bones += 1

		print(
			scene_path, " - Idle: ", has_idle, " Walk: ", has_walk,
			" ossos animados: ", moved_bones, "/", skeleton.get_bone_count()
		)
		if moved_bones < 10:
			failures.append(
				"%s: so %d ossos sairam da rest pose - rig incompativel com os clipes"
				% [scene_path, moved_bones]
			)

		npc.queue_free()
		await physics_frame

	if not failures.is_empty():
		for failure: String in failures:
			push_error(failure)
		quit(1)
		return

	print("OK: todas as cenas de NPC animam Idle/Walk no rig correto.")
	quit(0)
