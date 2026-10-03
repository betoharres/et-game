extends Node3D

const COST: int = 200
const CORPSE_SCRIPT: Script = preload("res://scripts/multiplayer/shared_scrap.gd")
var victims: Dictionary[StringName, int] = {}
var _session: Node3D


func _ready() -> void:
	_session = get_parent() as Node3D


func create_corpse(peer_id: int) -> void:
	var pose: Transform3D = _session.players[peer_id].global_transform
	_spawn_corpse(peer_id, pose)
	_spawn_corpse.rpc(peer_id, pose)


@rpc("authority", "call_remote", "reliable")
func _spawn_corpse(peer_id: int, pose: Transform3D) -> void:
	var id: StringName = StringName("corpse_%d" % peer_id)
	if victims.has(id) or not _session.players.has(peer_id):
		return
	var body: RigidBody3D = RigidBody3D.new()
	body.name = str(id)
	body.set_script(CORPSE_SCRIPT)
	body.set("network_id", id)
	body.set("two_handed", true)
	body.set("rejected_by_delivery", true)
	body.set("display_name", "Fallen teammate — return to revival tank")
	body.add_to_group(&"pickup_items")
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.5
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	collision.rotation.z = PI * 0.5
	body.add_child(collision)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.5
	mesh.mesh = capsule
	mesh.rotation.z = PI * 0.5
	mesh.layers = 64
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.75, 0.65)
	mesh.material_override = material
	body.add_child(mesh)
	var visual_count: int = 0
	var player: CharacterBody3D = _session.players[peer_id]
	for source: Node in player.character_visual.find_children("*", "MeshInstance3D", true, false):
		var original: MeshInstance3D = source as MeshInstance3D
		if original.mesh == null or not original.visible or not original.has_method("bake_mesh_from_current_skeleton_pose"):
			continue
		var baked: Mesh = original.mesh
		if original.skin != null:
			if DisplayServer.get_name() == "headless" or not original.get_node_or_null(original.skeleton) is Skeleton3D:
				continue
			baked = original.call("bake_mesh_from_current_skeleton_pose") as Mesh
		if baked == null:
			continue
		var copy: MeshInstance3D = MeshInstance3D.new()
		copy.mesh = baked
		copy.material_override = original.material_override
		copy.layers = 64
		copy.transform = pose.affine_inverse() * original.global_transform
		body.add_child(copy)
		visual_count += 1
	mesh.visible = visual_count == 0
	var label: Label3D = Label3D.new()
	label.text = "%s - REVIVE $200" % _session.player_names.get(peer_id, "ET")
	label.position.y = 0.6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	body.add_child(label)
	_session.get_node("PickupItemsContainer").add_child(body)
	body.global_transform = pose
	body.global_position.y += 0.35
	_session.items[id] = body
	_session._item_owners[id] = 0
	_session._item_revisions[id] = _session.mission_round * 1000000
	_session._item_spawns[id] = body.global_transform
	body.pickup_requested.connect(_session._on_item_pickup_requested.bind(id))
	body.drop_requested.connect(_session._on_item_drop_requested.bind(id))
	victims[id] = peer_id
	body.call("apply_network_state", null, body.global_transform, Vector3.ZERO, _session.multiplayer.is_server())
	_session.players[peer_id].ragdoll.stop_ragdoll()
	_session.players[peer_id].collision_layer = 0
	_session.players[peer_id].collision_mask = 0
	_session.players[peer_id].character_visual.hide()
	var player_name: Label3D = _session.players[peer_id].get_node_or_null("PlayerName") as Label3D
	if player_name != null:
		player_name.hide()


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or _session.mission_phase != &"collecting":
		return
	var tank: Node3D = _session.get_node_or_null("PropsContainer/RevivalTank")
	if tank == null:
		return
	var label: Label3D = tank.get_node("Label") as Label3D
	label.text = "SHIP REVIVAL TANK - $200\nDROP A TEAMMATE'S BODY INSIDE" if _session.team_money >= COST else "SHIP REVIVAL TANK - $200\nTEAM NEEDS $%d MORE - SELL SCRAP" % (COST - _session.team_money)
	for id: StringName in victims.keys():
		if not _session.items.has(id) or _session._item_owners[id] != 0 or _session.team_money < COST:
			continue
		var body: RigidBody3D = _session.items[id]
		if tank.to_local(body.global_position).distance_to(Vector3(0, 0.4, 0)) > 1.2:
			continue
		var peer_id: int = victims[id]
		_session.team_money -= COST
		_remove_corpse(id)
		_remove_corpse.rpc(id)
		_session.call("_respawn_player", peer_id)
		_session.call("_publish_economy")


@rpc("authority", "call_remote", "reliable")
func _remove_corpse(id: StringName) -> void:
	if _session.items.has(id):
		_session.items[id].queue_free()
		_session.items.erase(id)
		_session._item_owners.erase(id)
		_session._item_revisions.erase(id)
		_session._item_spawns.erase(id)
	victims.erase(id)


func reset() -> void:
	for id: StringName in victims.keys():
		_remove_corpse(id)


func remove_peer(peer_id: int) -> void:
	var id: StringName = StringName("corpse_%d" % peer_id)
	if victims.has(id):
		_remove_corpse(id)
		_remove_corpse.rpc(id)


func send_snapshot(peer_id: int) -> void:
	for id: StringName in victims:
		_spawn_corpse.rpc_id(peer_id, victims[id], _session.items[id].global_transform)
