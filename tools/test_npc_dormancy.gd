extends SceneTree

const FARMER: PackedScene = preload("res://scenes/NPCs/Farmer.tscn")
var _failures: int = 0

class PlayerProbe:
	extends CharacterBody3D
	var contact: bool = false
	func set_vision_contact(_source: Object, value: bool) -> void:
		contact = value


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var player: PlayerProbe = PlayerProbe.new()
	player.add_to_group(&"characters")
	player.position = Vector3(1000, 0, 0)
	world.add_child(player)
	var npc: NPCActor = FARMER.instantiate() as NPCActor
	npc.patrol_points = [Vector3.ZERO, Vector3(6, 0, 0)]
	world.add_child(npc)
	var explicit_child: Node = Node.new()
	explicit_child.process_mode = Node.PROCESS_MODE_ALWAYS
	npc.add_child(explicit_child)
	npc.navigation_agent.avoidance_enabled = true
	player.contact = true
	await create_timer(0.65).timeout
	_require(npc.is_dormant and not npc.can_process(), "Far NPC stops processing")
	_require(not npc.vision.can_process() and not npc.hearing.can_process(), "Sensors stop processing")
	_require(not npc.get_node("NPCBehaviorTree").can_process(), "Behavior tree stops processing")
	_require(not explicit_child.can_process(), "Explicit child process modes cannot bypass dormancy")
	_require(not npc.navigation_agent.avoidance_enabled, "Avoidance is disabled")
	_require(not player.contact, "Dormancy clears player vision contact")
	var location: Vector3 = npc.position
	await create_timer(0.6).timeout
	_require(npc.position == location, "Sleeping NPC does not move")
	player.position = npc.position + Vector3(80, 0, 0)
	await create_timer(0.6).timeout
	_require(npc.is_dormant, "Hysteresis keeps sleeping NPC dormant at 80 m")
	paused = true
	player.position = npc.position + Vector3(50, 0, 0)
	await create_timer(0.6, true).timeout
	_require(npc.is_dormant, "Wake timer respects game pause")
	paused = false
	await create_timer(0.6).timeout
	_require(not npc.is_dormant and npc.can_process(), "Nearby player wakes NPC")
	_require(npc.navigation_agent.avoidance_enabled, "Avoidance setting restored")
	_require(explicit_child.process_mode == Node.PROCESS_MODE_ALWAYS, "Original child process mode restored")
	player.position = npc.position + Vector3(80, 0, 0)
	await create_timer(0.6).timeout
	_require(not npc.is_dormant, "Awake NPC stays awake at 80 m")
	player.position = Vector3(1000, 0, 0)
	await create_timer(0.6).timeout
	npc.activity_distance = 0.0
	await create_timer(0.6).timeout
	_require(not npc.is_dormant, "Distance zero opts out and wakes sleeping NPC")
	npc.activity_distance = 90.0
	player.queue_free()
	await create_timer(0.6).timeout
	_require(npc.is_dormant, "NPC sleeps without a player")
	var replacement: PlayerProbe = PlayerProbe.new()
	replacement.add_to_group(&"characters")
	replacement.position = npc.position + Vector3(50, 0, 0)
	world.add_child(replacement)
	await create_timer(0.6).timeout
	_require(not npc.is_dormant and npc.player == replacement, "Replacement player wakes and rebinds target")
	world.free()
	print("NPC dormancy: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
