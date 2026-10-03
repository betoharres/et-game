extends "res://scripts/multiplayer/portal_session.gd"

var simulate_faults: bool = false
var _fault_packet: int = 0


func _relay_snapshot(peer_id: int, state: Dictionary) -> void:
	if not simulate_faults:
		super._relay_snapshot(peer_id, state)
		return
	_fault_packet += 1
	if _fault_packet % 3 == 0:
		return
	_delayed_snapshot(peer_id, state.duplicate(true))


func _delayed_snapshot(peer_id: int, state: Dictionary) -> void:
	await get_tree().create_timer(0.12 if _fault_packet % 2 == 0 else 0.04).timeout
	if not multiplayer.multiplayer_peer is ENetMultiplayerPeer or not players.has(peer_id):
		return
	super._relay_snapshot(peer_id, state)
