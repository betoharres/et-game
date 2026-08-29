class_name DungeonModule
extends Node3D

## Shared connectivity contract for every 2 x 2 x 2 metre dungeon module.
## The mask is expressed in world-grid directions before the module transform:
## North +Z, South -Z, East +X and West -X.

enum Direction {
	NORTH = 1 << 0,
	EAST = 1 << 1,
	SOUTH = 1 << 2,
	WEST = 1 << 3,
}

const ALL_MASK : int = (
	Direction.NORTH
	| Direction.EAST
	| Direction.SOUTH
	| Direction.WEST
)
const QUARTER_TURN_RADIANS : float = PI * 0.5

@export_flags("North +Z", "East +X", "South -Z", "West -X")
var connection_mask : int = 0
@export var module_name : String = ""

var rotation_quarters : int = 0


func _ready() -> void:
	if connection_mask == 0:
		connection_mask = get_base_connection_mask()
	if module_name.is_empty():
		module_name = get_module_name()
	_validate_mask()


## Returns the openings authored in the unrotated module scene.
func get_base_connection_mask() -> int:
	return ALL_MASK


func get_module_name() -> String:
	return "X"


## Rotates both the scene and its logical openings around +Y in 90 degree steps.
func configure_rotation(quarter_turns : int) -> void:
	rotation_quarters = posmod(quarter_turns, 4)
	connection_mask = rotated_mask(
		get_base_connection_mask(),
		rotation_quarters
	)
	rotation.y = float(rotation_quarters) * QUARTER_TURN_RADIANS
	module_name = get_module_name()
	_validate_mask()


func has_direction(direction : int) -> bool:
	return bool(connection_mask & direction)


func get_mask() -> int:
	return connection_mask


func _validate_mask() -> void:
	if connection_mask == 0:
		push_error("%s has no dungeon connections." % name)
	if (connection_mask & ~ALL_MASK) != 0:
		connection_mask &= ALL_MASK
		push_error("%s contained invalid dungeon connection bits." % name)


static func rotated_mask(mask : int, quarter_turns : int) -> int:
	var rotated : int = mask & ALL_MASK
	var normalized_turns : int = posmod(quarter_turns, 4)

	for _turn_index : int in range(normalized_turns):
		var next_mask : int = 0
		if bool(rotated & Direction.NORTH):
			next_mask |= Direction.EAST
		if bool(rotated & Direction.EAST):
			next_mask |= Direction.SOUTH
		if bool(rotated & Direction.SOUTH):
			next_mask |= Direction.WEST
		if bool(rotated & Direction.WEST):
			next_mask |= Direction.NORTH
		rotated = next_mask

	return rotated


static func opposite_direction(direction : int) -> int:
	match direction:
		Direction.NORTH:
			return Direction.SOUTH
		Direction.EAST:
			return Direction.WEST
		Direction.SOUTH:
			return Direction.NORTH
		Direction.WEST:
			return Direction.EAST
		_:
			return 0


static func find_rotation_quarters(base_mask : int, target_mask : int) -> int:
	for quarter_turns : int in range(4):
		if rotated_mask(base_mask, quarter_turns) == target_mask:
			return quarter_turns
	return -1
