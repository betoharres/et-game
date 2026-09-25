extends RefCounted

## Session progress that must survive the orbit/world scene changes.
static var highest_repaired_level: int = 1
static var ship_oxygen_seconds: float = 4800.0
static var oxygen_capacity_seconds: float = 4800.0


static func begin_level() -> void:
	ship_oxygen_seconds = maxf(ship_oxygen_seconds, 0.0)


static func unlock_next_level() -> void:
	highest_repaired_level += 1

