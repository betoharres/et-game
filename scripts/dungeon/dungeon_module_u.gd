extends "res://scripts/dungeon/dungeon_module.gd"

## U connector: dead end open only to North +Z.

const BASE_CONNECTION_MASK : int = Direction.NORTH


func get_base_connection_mask() -> int:
	return BASE_CONNECTION_MASK


func get_module_name() -> String:
	return "U"
