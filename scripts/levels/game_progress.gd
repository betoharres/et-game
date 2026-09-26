extends RefCounted

## Session progress that must survive the orbit/world scene changes.
static var highest_repaired_level: int = 1
static var radon_seconds: float = 1200.0
static var radon_capacity_seconds: float = 4800.0


static func begin_level() -> void:
	radon_seconds = clampf(radon_seconds, 0.0, radon_capacity_seconds)


static func unlock_next_level() -> void:
	highest_repaired_level = maxi(highest_repaired_level, 2)
