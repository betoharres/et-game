extends "res://scripts/dungeon/dungeon_module.gd"

## H connector: opposite paths East +X and West -X; North/South closed.

const BASE_CONNECTION_MASK : int = Direction.EAST | Direction.WEST


func get_base_connection_mask() -> int:
	return BASE_CONNECTION_MASK


func get_module_name() -> String:
	return "H"
