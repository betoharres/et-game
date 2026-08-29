extends "res://scripts/dungeon/dungeon_module.gd"

## X connector: paths open to North +Z, East +X, South -Z and West -X.

const BASE_CONNECTION_MASK : int = ALL_MASK


func get_base_connection_mask() -> int:
	return BASE_CONNECTION_MASK


func get_module_name() -> String:
	return "X"
