extends "res://scripts/dungeon/dungeon_module.gd"

## T connector: North +Z, East +X and South -Z open; West -X closed.

const BASE_CONNECTION_MASK : int = (
	Direction.NORTH | Direction.EAST | Direction.SOUTH
)


func get_base_connection_mask() -> int:
	return BASE_CONNECTION_MASK


func get_module_name() -> String:
	return "T"
