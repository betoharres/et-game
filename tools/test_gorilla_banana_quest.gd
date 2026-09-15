extends SceneTree

class TestPlayer extends CharacterBody3D:
	var _movement_locked: bool = false
	var carried_item: RigidBody3D = null

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	current_scene = world
	var player: TestPlayer = TestPlayer.new()
	player.add_to_group("characters")
	var inventory: Node = Node.new()
	inventory.set_script(load("res://scripts/exploration_inventory.gd"))
	inventory.name = "ExplorationInventory"
	player.add_child(inventory)
	world.add_child(player)
	var quest_scene: PackedScene = load("res://scenes/Quests/GorillaBananaQuest.tscn")
	var quest: Node3D = quest_scene.instantiate()
	world.add_child(quest)
	quest.process_mode = Node.PROCESS_MODE_DISABLED
	var trade: Node = quest.get_node("Gorilla/BananaTrade")
	var banana: RigidBody3D = quest.get_node("BananaBox")
	var skeleton: Skeleton3D = quest.get_node("Gorilla/Character/Skeleton3D")
	_check(not skeleton.get_node("SM_Chr_Kaiju_01").visible, "Kaiju 01 must be hidden")
	_check(not skeleton.get_node("SM_Chr_Kaiju_02").visible, "Kaiju 02 must be hidden")
	_check(skeleton.get_node("SM_Chr_Kaiju_04").visible, "Gorilla must be visible")
	_check(banana.call("is_available_for_abduction"), "Bananas must be pickupable")
	var delivery: Node = (load("res://scripts/delivery_area.gd") as Script).new()
	_check(not delivery.call("request_automatic_delivery", banana, player), "Quest items cannot be delivered automatically")
	delivery.get("_candidate_items").append(banana)
	_check(delivery.call("_find_available_item") == null, "Quest items cannot be delivered manually")
	delivery.free()
	player.position = Vector3(20, 0, 0)
	trade.call("interact", player)
	_check(not trade.get("accepted"), "Cannot start quest outside interaction range")
	player.position = Vector3.ZERO
	player._movement_locked = true
	_check(not trade.call("reserves_interaction_for", player), "Locked player cannot interact")
	player._movement_locked = false
	trade.call("interact", player)
	_check(trade.get("accepted"), "First interaction must offer bananas quest")
	trade.call("interact", player)
	_check(not trade.get("completed"), "Cannot earn reward without bananas")
	_check(inventory.call("store_item", banana, player), "Bananas must fit in exploration inventory")
	_check(inventory.call("used_slots") == 1, "Bananas must occupy one inventory slot")
	var before: int = world.get_child_count()
	trade.call("interact", player)
	_check(trade.get("completed"), "Bananas must complete accepted quest")
	_check(world.get_child_count() == before + 1, "Exactly one reward must spawn")
	var reward: RigidBody3D = world.get_child(world.get_child_count() - 1) as RigidBody3D
	_check(reward != null and reward.is_in_group("pickup_items"), "Reward must be collectible scrap")
	_check(trade.call("reserves_interaction_for", player), "Completion must retain reservation for current keypress")
	trade.call("interact", player)
	_check(world.get_child_count() == before + 1, "Repeated interaction must not duplicate reward")
	await process_frame
	_check(not is_instance_valid(banana), "Trade must consume banana box")
	_check(inventory.call("used_slots") == 0, "Trade must clear inventory slots")
	for packed: PackedScene in trade.get("rewards"):
		var item: Node = packed.instantiate()
		_check(item is RigidBody3D and item.has_method("pickup"), "Every random reward must support pickup")
		item.free()
	world.free()
	print("Gorilla banana quest: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)
