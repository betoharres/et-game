extends "res://scripts/dungeon/dungeon_module.gd"

## L connector: adjacent paths North +Z and East +X; other sides closed.

const BASE_CONNECTION_MASK : int = Direction.NORTH | Direction.EAST


func get_base_connection_mask() -> int:
	return BASE_CONNECTION_MASK


func get_module_name() -> String:
	return "L"
