extends Node

var score : int = 0
var inventory : Array[String] = []

func add_score(amount : int) -> void:
	score += amount
	print("Score: ", score)

func add_item(item_id : String) -> void:
	inventory.append(item_id)

func remove_item(item_id : String) -> void:
	inventory.erase(item_id)

func has_item(item_id : String) -> bool:
	return inventory.has(item_id)
