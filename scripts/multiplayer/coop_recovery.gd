extends Node3D

signal recovery_tick(delta: float)

const TANK_SCRIPT: Script = preload("res://scripts/multiplayer/revival_tank.gd")
const COST: int = TANK_SCRIPT.COST
const CORPSE_SCRIPT: Script = preload("res://scripts/multiplayer/shared_scrap.gd")
var victims: Dictionary[StringName, int] = {}
var revivals: Dictionary[int, Dictionary] = {}
var _session: Node3D


func _ready() -> void:
	_session = get_parent() as Node3D


func _physics_process(delta: float) -> void:
	recovery_tick.emit(delta)


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


func _publish_revivals() -> void:
	_receive_revivals(revivals)
	_receive_revivals.rpc(revivals)


@rpc("authority", "call_remote", "reliable")
func _receive_revivals(state: Dictionary) -> void:
	revivals.assign(state.duplicate(true))
	for peer_id: int in revivals:
		if not _session.players.has(peer_id):
			continue
		var player: CharacterBody3D = _session.players[peer_id]
		player.ragdoll.stop_ragdoll()
		player.character_visual.hide()
		player.collision_layer = 0
		player.collision_mask = 0
		var player_name: Label3D = player.get_node_or_null("PlayerName") as Label3D
		if player_name != null:
			player_name.hide()
	var tank: Node3D = _session.get_revival_tank()
	if tank != null:
		tank.update_visuals(revivals, _session.team_money, _session.player_names)


func restore_revivals(state: Dictionary, mapping: Dictionary) -> void:
	revivals.clear()
	for old_id: int in state:
		if mapping.has(old_id):
			revivals[int(mapping[old_id])] = state[old_id].duplicate(true)
	_receive_revivals(revivals)


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
	_receive_revivals({})
	for id: StringName in victims.keys():
		_remove_corpse(id)


func remove_peer(peer_id: int) -> void:
	if revivals.has(peer_id):
		revivals.erase(peer_id)
		_publish_revivals()
	var id: StringName = StringName("corpse_%d" % peer_id)
	if victims.has(id):
		_remove_corpse(id)
		_remove_corpse.rpc(id)


func send_snapshot(peer_id: int) -> void:
	_receive_revivals.rpc_id(peer_id, revivals)
	for id: StringName in victims:
		_spawn_corpse.rpc_id(peer_id, victims[id], _session.items[id].global_transform)
