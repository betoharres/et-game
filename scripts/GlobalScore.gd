extends Node

signal money_changed(balance : int)
signal upgrade_changed(upgrade_id : StringName, level : int)

const UPGRADE_IDS : Array[StringName] = [&"movement", &"stamina", &"recovery"]
const UPGRADE_COSTS : Array[int] = [60, 100, 150]

var score : int = 0
var inventory : Array[String] = []
var money : int = 0
var _upgrade_levels : Dictionary[StringName, int] = {}

func add_score(amount : int) -> void:
	score += amount
	print("Score: ", score)

func add_item(item_id : String) -> void:
	inventory.append(item_id)

func remove_item(item_id : String) -> void:
	inventory.erase(item_id)

func has_item(item_id : String) -> bool:
	return inventory.has(item_id)


func add_money(amount : int) -> void:
	if amount <= 0:
		return
	money += amount
	money_changed.emit(money)


func spend_money(amount : int) -> bool:
	if amount <= 0 or money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true


func get_upgrade_level(upgrade_id : StringName) -> int:
	return _upgrade_levels.get(upgrade_id, 0)


func get_upgrade_cost(upgrade_id : StringName) -> int:
	if not UPGRADE_IDS.has(upgrade_id):
		return -1
	var level : int = get_upgrade_level(upgrade_id)
	if level >= UPGRADE_COSTS.size():
		return -1
	return UPGRADE_COSTS[level]


func purchase_upgrade(upgrade_id : StringName) -> bool:
	var cost : int = get_upgrade_cost(upgrade_id)
	if cost <= 0 or money < cost:
		return false
	var level : int = get_upgrade_level(upgrade_id) + 1
	# Publica saldo e nível já consistentes para os dois sinais.
	money -= cost
	_upgrade_levels[upgrade_id] = level
	money_changed.emit(money)
	upgrade_changed.emit(upgrade_id, level)
	return true
