extends Node3D

const COST: int = 200
const REVIVAL_SECONDS: float = 20.0
const TANK_COUNT: int = 4
var _session: Node3D
var _visual_bases: Dictionary[Node3D, Transform3D] = {}


func _ready() -> void:
	var ancestor: Node = get_parent()
	while ancestor != null and not ancestor.has_method("get_revival_tank"):
		ancestor = ancestor.get_parent()
	_session = ancestor as Node3D
	if _session == null:
		queue_free()
		return
	add_to_group("coop_revival_tanks")
	_connect_recovery.call_deferred()
	for slot: int in TANK_COUNT:
		var visual: Node3D = get_node("Tank%d/ET%d" % [slot + 3, slot + 1]) as Node3D
		_visual_bases[visual] = visual.transform
		visual.hide()


func _connect_recovery() -> void:
	if is_instance_valid(_session):
		_session.recovery.recovery_tick.connect(_on_recovery_tick)


func _on_recovery_tick(delta: float) -> void:
	if _session == null or _session.get("recovery") == null:
		return
	var recovery: Node3D = _session.recovery
	if _session.host_migration.active or _session.mission_phase != &"collecting":
		return
	var completed: Array[int] = []
	for peer_id: int in recovery.revivals:
		recovery.revivals[peer_id].remaining = maxf(0.0, float(recovery.revivals[peer_id].remaining) - delta)
		if float(recovery.revivals[peer_id].remaining) <= 0.0:
			completed.append(peer_id)
	update_visuals(recovery.revivals, _session.team_money, _session.player_names)
	if not multiplayer.is_server():
		return
	for peer_id: int in completed:
		recovery.revivals.erase(peer_id)
		if _session.players.has(peer_id):
			_session.call("_respawn_player", peer_id)
	if not completed.is_empty():
		recovery._publish_revivals()
	for id: StringName in recovery.victims.keys():
		if not _session.items.has(id) or _session._item_owners[id] != 0 or _session.team_money < COST:
			continue
		var slot: int = _free_slot(recovery.revivals)
		if slot < 0:
			break
		var body: RigidBody3D = _session.items[id]
		if to_local(body.global_position).distance_to(Vector3(0, 0.4, 0)) > 1.2:
			continue
		var peer_id: int = recovery.victims[id]
		_session.team_money -= COST
		recovery.revivals[peer_id] = {"slot": slot, "remaining": REVIVAL_SECONDS}
		recovery._remove_corpse(id)
		recovery._remove_corpse.rpc(id)
		recovery._publish_revivals()
		_session.call("_publish_economy")


func _free_slot(revivals: Dictionary) -> int:
	for slot: int in TANK_COUNT:
		var occupied: bool = false
		for record: Dictionary in revivals.values():
			if int(record.slot) == slot:
				occupied = true
		if not occupied:
			return slot
	return -1


func update_visuals(revivals: Dictionary, team_money: int, player_names: Dictionary) -> void:
	for slot: int in TANK_COUNT:
		var visual: Node3D = get_node("Tank%d/ET%d" % [slot + 3, slot + 1]) as Node3D
		if not _visual_bases.has(visual):
			_visual_bases[visual] = visual.transform
		visual.hide()
		visual.transform = _visual_bases[visual]
		for peer_id: int in revivals:
			var record: Dictionary = revivals[peer_id]
			if int(record.slot) != slot:
				continue
			var progress: float = clampf(1.0 - float(record.remaining) / REVIVAL_SECONDS, 0.0, 1.0)
			var growth: float = lerpf(0.04, 1.0, smoothstep(0.0, 1.0, progress))
			var distortion: float = (1.0 - progress) * sin(progress * 40.0) * 0.35
			visual.scale *= Vector3(growth * (1.0 + distortion), growth * (1.0 - distortion), growth)
			visual.rotate_y(distortion)
			visual.show()
	var label: Label3D = get_node("Label") as Label3D
	label.text = "SHIP REVIVAL TANK - $200 / 20s\nDROP A TEAMMATE'S BODY AT THE CONSOLE"
	if team_money < COST and revivals.is_empty():
		label.text += "\nTEAM NEEDS $%d MORE - SELL SCRAP" % (COST - team_money)
	for peer_id: int in revivals:
		label.text += "\n%s - %ds" % [player_names.get(peer_id, "ET"), ceili(float(revivals[peer_id].remaining))]


