@tool
extends SceneTree

## Bakes the drivable road graph the police patrol wanders (the `road_nodes`
## export on the AIDriver node inside scenes/Vehicles/PoliceCarDriveable.tscn).
##
## The AI can't read build_country_town_layout.gd at runtime - that is a
## SceneTree tool script, not a runtime class - so the tile centres are baked
## into the scene as a literal. Re-run this whenever ROAD_RUNS changes, or the
## patrol keeps driving the old street grid.
##
## Prints an ASCII map of the network, its degree histogram, and the literal to
## paste over the existing `road_nodes = Array[Vector3]([...])` line.

const Layout : GDScript = preload("res://tools/build_country_town_layout.gd")

## Only the paved town streets: the dirt farm roads are cut at the river
## crossings, so including them would route the patrol at a bridge gap.
const PIECE_PREFIX : String = "asphalt"


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var cells : Dictionary = {}

	for road_run : Array in Layout.ROAD_RUNS:
		if not String(road_run[0]).begins_with(PIECE_PREFIX):
			continue
		var along_i : bool = road_run[1] == "i"
		var fixed : int = road_run[2]
		for step : int in range(int(road_run[3]), int(road_run[4]) + 1):
			cells[Vector2i(step, fixed) if along_i else Vector2i(fixed, step)] = true

	var keys : Array = cells.keys()
	keys.sort_custom(func(a : Vector2i, b : Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y)
	)

	var degrees : Dictionary = {}
	for cell : Vector2i in keys:
		var degree : int = _neighbours(cell, cells).size()
		degrees[degree] = int(degrees.get(degree, 0)) + 1

	print("Asphalt tiles: %d" % keys.size())
	print("Degree histogram (1 = dead end, 3+ = junction): %s" % degrees)
	_print_map(cells)

	var height : float = Layout.GROUND_HEIGHT + Layout.ROAD_PIECE_LIFT
	var parts : PackedStringArray = PackedStringArray()
	for cell : Vector2i in keys:
		var flat : Vector2 = Layout.grid_position(cell.x, cell.y)
		parts.append("Vector3(%.4f, %.2f, %.4f)" % [flat.x, height, flat.y])

	print("")
	print("Paste over the road_nodes line on the AIDriver node:")
	print("road_nodes = Array[Vector3]([%s])" % ", ".join(parts))
	quit(0)


func _neighbours(cell : Vector2i, cells : Dictionary) -> Array[Vector2i]:
	var found : Array[Vector2i] = []
	for offset : Vector2i in [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]:
		if cells.has(cell + offset):
			found.append(cell + offset)
	return found


## '#' marks a tile the patrol can drive. Handy for spotting that the network
## is a tree with a single loop, which is why the patrol has to turn around at
## the five dead ends instead of always circulating.
func _print_map(cells : Dictionary) -> void:
	var min_cell : Vector2i = Vector2i(999, 999)
	var max_cell : Vector2i = Vector2i(-999, -999)
	for cell : Vector2i in cells.keys():
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))

	print("Map (i %d..%d, j %d..%d):" % [min_cell.x, max_cell.x, min_cell.y, max_cell.y])
	for j : int in range(min_cell.y, max_cell.y + 1):
		var line : String = ""
		for i : int in range(min_cell.x, max_cell.x + 1):
			line += "#" if cells.has(Vector2i(i, j)) else " "
		print("j=%3d |%s|" % [j, line])
