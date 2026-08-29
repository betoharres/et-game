extends Node3D

## Procedural 2D dungeon assembled from authored 2 x 2 x 2 metre modules.
## A randomized spanning maze guarantees that every cell is reachable; a few
## extra reciprocal links create loops. The module selected for each cell is
## driven entirely by its North/East/South/West connection mask.

const CELL_SIZE : float = 2.0
const DEFAULT_GRID_WIDTH : int = 12
const DEFAULT_GRID_DEPTH : int = 12
const EXTRA_CONNECTION_CHANCE : float = 0.12
const SCRAP_COUNT : int = 2

const X_MODULE_SCENE : PackedScene = preload(
	"res://scenes/Dungeon/Xconnecor.tscn"
)
const T_MODULE_SCENE : PackedScene = preload(
	"res://scenes/Dungeon/Tconnector.tscn"
)
const L_MODULE_SCENE : PackedScene = preload(
	"res://scenes/Dungeon/Lconnector.tscn"
)
const U_MODULE_SCENE : PackedScene = preload(
	"res://scenes/Dungeon/Uconnector.tscn"
)
const H_MODULE_SCENE : PackedScene = preload(
	"res://scenes/Dungeon/Hconnector.tscn"
)

const SCRAP_SCENES : Array[PackedScene] = [
	preload("res://scenes/Spaceship_Scraps1.tscn"),
	preload("res://scenes/spaceship_Scraps2.tscn"),
	preload("res://scenes/Spaceship_Scraps3.tscn"),
	preload("res://scenes/Spaceship_Scraps4.tscn"),
	preload("res://scenes/Spaceship_Scraps5.tscn"),
	preload("res://scenes/Spaceship_Scraps6.tscn"),
	preload("res://scenes/Spaceship_Scraps7.tscn"),
]

const DIRECTION_BITS : Array[int] = [
	DungeonModule.Direction.NORTH,
	DungeonModule.Direction.EAST,
	DungeonModule.Direction.SOUTH,
	DungeonModule.Direction.WEST,
]
const DIRECTION_OFFSETS : Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(-1, 0),
]

@export_range(2, 40, 1) var grid_width : int = DEFAULT_GRID_WIDTH
@export_range(2, 40, 1) var grid_depth : int = DEFAULT_GRID_DEPTH
## Zero creates a new layout each session; any other value is reproducible.
@export var generation_seed : int = 0

@onready var module_container : Node3D = $Modules
@onready var pickup_container : Node3D = $Pickups
@onready var exit_door : Node3D = $ExitDoor
@onready var exit_trigger : Area3D = $ExitDoor/ExitTrigger
@onready var exit_prompt : Label3D = $ExitDoor/ExitPrompt

var _generated : bool = false
var _entry_cell : Vector2i = Vector2i.ZERO
var _entry_direction : int = DungeonModule.Direction.EAST
var _farm_return_position : Vector3 = Vector3.ZERO
var _characters_at_exit : Array[CharacterBody3D] = []
var _connection_masks : Dictionary = {}
var _random : RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	exit_trigger.body_entered.connect(_on_exit_body_entered)
	exit_trigger.body_exited.connect(_on_exit_body_exited)
	exit_prompt.visible = false


func _process(_delta : float) -> void:
	_cleanup_characters()
	exit_prompt.visible = not _characters_at_exit.is_empty()

	if _characters_at_exit.is_empty():
		return

	if Input.is_action_just_pressed("interact"):
		_return_to_farm()


## Builds the dungeon once per scene lifetime. Later entrances only update the
## farm-side return position and reuse the existing module layout.
func ensure_generated(farm_return_position : Vector3) -> void:
	_farm_return_position = farm_return_position

	if _generated:
		return

	_seed_random()
	_entry_cell = Vector2i(0, grid_depth / 2)
	_connection_masks = _generate_connection_masks()

	if not _validate_connection_masks(_connection_masks):
		push_error("Dungeon generation produced an invalid connection graph.")
		return

	_instantiate_modules(_connection_masks)
	_position_exit_door()
	_spawn_scraps(_connection_masks)
	_generated = true


func get_entry_global_position() -> Vector3:
	var inward_offset : Vector3 = _direction_to_vector3(_entry_direction) * 0.5
	return to_global(_cell_to_local(_entry_cell) + inward_offset)


func get_connection_masks() -> Dictionary:
	return _connection_masks.duplicate()


func _seed_random() -> void:
	if generation_seed == 0:
		_random.randomize()
	else:
		_random.seed = generation_seed


func _generate_connection_masks() -> Dictionary:
	var connections : Dictionary = {}
	var visited : Dictionary = {}
	var stack : Array[Vector2i] = []
	var first_cell : Vector2i = _entry_cell + Vector2i.RIGHT

	for x : int in range(grid_width):
		for z : int in range(grid_depth):
			connections[Vector2i(x, z)] = 0

	# Keeping the boundary entrance out of the walk until the first link makes it
	# a guaranteed U module whose only path points into the dungeon (+X).
	visited[_entry_cell] = true
	visited[first_cell] = true
	_connect_cells(_entry_cell, first_cell, connections)
	stack.append(first_cell)

	while not stack.is_empty():
		var current : Vector2i = stack.back()
		var candidates : Array[Vector2i] = _get_unvisited_neighbors(
			current,
			visited
		)

		if candidates.is_empty():
			stack.pop_back()
			continue

		var next : Vector2i = candidates[
			_random.randi_range(0, candidates.size() - 1)
		]
		_connect_cells(current, next, connections)
		visited[next] = true
		stack.append(next)

	_add_extra_connections(connections)
	return connections


func _get_unvisited_neighbors(
	cell : Vector2i,
	visited : Dictionary
) -> Array[Vector2i]:
	var neighbors : Array[Vector2i] = []

	for offset : Vector2i in DIRECTION_OFFSETS:
		var neighbor : Vector2i = cell + offset
		if _is_inside_grid(neighbor) and not visited.has(neighbor):
			neighbors.append(neighbor)

	return neighbors


func _add_extra_connections(connections : Dictionary) -> void:
	var forward_offsets : Array[Vector2i] = [Vector2i.RIGHT, Vector2i.UP]

	for x : int in range(grid_width):
		for z : int in range(grid_depth):
			var cell : Vector2i = Vector2i(x, z)
			if cell == _entry_cell:
				continue

			for offset : Vector2i in forward_offsets:
				var neighbor : Vector2i = cell + offset
				if not _is_inside_grid(neighbor) or neighbor == _entry_cell:
					continue
				if _cells_are_connected(cell, neighbor, connections):
					continue
				if _random.randf() <= EXTRA_CONNECTION_CHANCE:
					_connect_cells(cell, neighbor, connections)


func _connect_cells(
	first : Vector2i,
	second : Vector2i,
	connections : Dictionary
) -> void:
	var direction : int = _direction_from_offset(second - first)
	if direction == 0:
		push_error("Dungeon tried to connect non-adjacent cells.")
		return

	connections[first] = int(connections[first]) | direction
	connections[second] = (
		int(connections[second])
		| DungeonModule.opposite_direction(direction)
	)


func _cells_are_connected(
	first : Vector2i,
	second : Vector2i,
	connections : Dictionary
) -> bool:
	var direction : int = _direction_from_offset(second - first)
	return direction != 0 and bool(int(connections[first]) & direction)


func _instantiate_modules(connections : Dictionary) -> void:
	for cell : Vector2i in connections.keys():
		var target_mask : int = int(connections[cell])
		var module_scene : PackedScene = _get_module_scene(target_mask)
		if module_scene == null:
			push_error("No dungeon module can represent mask %d." % target_mask)
			continue

		var instance : Node = module_scene.instantiate()
		if not instance is DungeonModule:
			instance.queue_free()
			push_error("Dungeon connector scene root must inherit DungeonModule.")
			continue

		var module : DungeonModule = instance as DungeonModule
		var rotation_quarters : int = DungeonModule.find_rotation_quarters(
			module.get_base_connection_mask(),
			target_mask
		)
		if rotation_quarters < 0:
			module.queue_free()
			push_error("Module %s cannot match mask %d." % [
				module.get_module_name(),
				target_mask,
			])
			continue

		module.configure_rotation(rotation_quarters)
		module.position = _cell_to_local(cell)
		module.name = "%s_%d_%d" % [module.get_module_name(), cell.x, cell.y]
		module.set_meta("grid_cell", cell)
		module_container.add_child(module)


func _get_module_scene(mask : int) -> PackedScene:
	match _count_connections(mask):
		4:
			return X_MODULE_SCENE
		3:
			return T_MODULE_SCENE
		2:
			if _has_opposite_connections(mask):
				return H_MODULE_SCENE
			return L_MODULE_SCENE
		1:
			return U_MODULE_SCENE
		_:
			return null


func _count_connections(mask : int) -> int:
	var count : int = 0
	for direction : int in DIRECTION_BITS:
		if bool(mask & direction):
			count += 1
	return count


func _has_opposite_connections(mask : int) -> bool:
	var north_south : int = (
		DungeonModule.Direction.NORTH | DungeonModule.Direction.SOUTH
	)
	var east_west : int = (
		DungeonModule.Direction.EAST | DungeonModule.Direction.WEST
	)
	return mask == north_south or mask == east_west


func _validate_connection_masks(connections : Dictionary) -> bool:
	if connections.size() != grid_width * grid_depth:
		return false

	for cell : Vector2i in connections.keys():
		var mask : int = int(connections[cell])
		if mask == 0 or (mask & ~DungeonModule.ALL_MASK) != 0:
			return false

		for index : int in range(DIRECTION_BITS.size()):
			var direction : int = DIRECTION_BITS[index]
			if not bool(mask & direction):
				continue

			var neighbor : Vector2i = cell + DIRECTION_OFFSETS[index]
			if not connections.has(neighbor):
				return false
			var opposite : int = DungeonModule.opposite_direction(direction)
			if not bool(int(connections[neighbor]) & opposite):
				return false

	return _all_cells_reachable(connections)


func _all_cells_reachable(connections : Dictionary) -> bool:
	var visited : Dictionary = {_entry_cell: true}
	var queue : Array[Vector2i] = [_entry_cell]
	var queue_index : int = 0

	while queue_index < queue.size():
		var cell : Vector2i = queue[queue_index]
		queue_index += 1
		var mask : int = int(connections[cell])

		for index : int in range(DIRECTION_BITS.size()):
			if not bool(mask & DIRECTION_BITS[index]):
				continue
			var neighbor : Vector2i = cell + DIRECTION_OFFSETS[index]
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)

	return visited.size() == connections.size()


func _position_exit_door() -> void:
	exit_door.position = _cell_to_local(_entry_cell)
	# The entrance U opens East, so the portal arch spans the X-axis corridor.
	exit_door.rotation.y = PI * 0.5


func _spawn_scraps(connections : Dictionary) -> void:
	var scrap_cells : Array[Vector2i] = _find_farthest_dead_ends(
		connections,
		SCRAP_COUNT
	)

	for cell : Vector2i in scrap_cells:
		var scrap_scene : PackedScene = SCRAP_SCENES[
			_random.randi_range(0, SCRAP_SCENES.size() - 1)
		]
		var scrap_instance : Node = scrap_scene.instantiate()
		if not scrap_instance is RigidBody3D:
			scrap_instance.queue_free()
			push_error("Dungeon scrap scene root must be a RigidBody3D.")
			continue

		var scrap : RigidBody3D = scrap_instance as RigidBody3D
		pickup_container.add_child(scrap)
		scrap.global_position = to_global(
			_cell_to_local(cell) + Vector3.UP * 0.3
		)


func _find_farthest_dead_ends(
	connections : Dictionary,
	count : int
) -> Array[Vector2i]:
	var distances : Dictionary = _get_distances_from_entry(connections)
	var selected : Array[Vector2i] = []

	while selected.size() < count:
		var best_cell : Vector2i = Vector2i(-1, -1)
		var best_distance : int = -1

		for cell : Vector2i in connections.keys():
			if cell == _entry_cell or selected.has(cell):
				continue
			if _count_connections(int(connections[cell])) != 1:
				continue
			var distance : int = int(distances.get(cell, -1))
			if distance > best_distance:
				best_cell = cell
				best_distance = distance

		if best_distance < 0:
			break
		selected.append(best_cell)

	return selected


func _get_distances_from_entry(connections : Dictionary) -> Dictionary:
	var distances : Dictionary = {_entry_cell: 0}
	var queue : Array[Vector2i] = [_entry_cell]
	var queue_index : int = 0

	while queue_index < queue.size():
		var cell : Vector2i = queue[queue_index]
		queue_index += 1
		var mask : int = int(connections[cell])
		var distance : int = int(distances[cell])

		for index : int in range(DIRECTION_BITS.size()):
			if not bool(mask & DIRECTION_BITS[index]):
				continue
			var neighbor : Vector2i = cell + DIRECTION_OFFSETS[index]
			if distances.has(neighbor):
				continue
			distances[neighbor] = distance + 1
			queue.append(neighbor)

	return distances


func _direction_from_offset(offset : Vector2i) -> int:
	for index : int in range(DIRECTION_OFFSETS.size()):
		if DIRECTION_OFFSETS[index] == offset:
			return DIRECTION_BITS[index]
	return 0


func _direction_to_vector3(direction : int) -> Vector3:
	match direction:
		DungeonModule.Direction.NORTH:
			return Vector3(0.0, 0.0, 1.0)
		DungeonModule.Direction.EAST:
			return Vector3(1.0, 0.0, 0.0)
		DungeonModule.Direction.SOUTH:
			return Vector3(0.0, 0.0, -1.0)
		DungeonModule.Direction.WEST:
			return Vector3(-1.0, 0.0, 0.0)
		_:
			return Vector3.ZERO


func _cell_to_local(cell : Vector2i) -> Vector3:
	return Vector3(float(cell.x) * CELL_SIZE, 0.0, float(cell.y) * CELL_SIZE)


func _is_inside_grid(cell : Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.x < grid_width
		and cell.y >= 0
		and cell.y < grid_depth
	)


func _return_to_farm() -> void:
	for character : CharacterBody3D in _characters_at_exit:
		if is_instance_valid(character):
			character.global_position = _farm_return_position
			character.velocity = Vector3.ZERO

	_characters_at_exit.clear()


func _on_exit_body_entered(body : Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("characters"):
		var character : CharacterBody3D = body as CharacterBody3D
		if not _characters_at_exit.has(character):
			_characters_at_exit.append(character)


func _on_exit_body_exited(body : Node3D) -> void:
	if body is CharacterBody3D:
		_characters_at_exit.erase(body)


func _cleanup_characters() -> void:
	for index : int in range(_characters_at_exit.size() - 1, -1, -1):
		if not is_instance_valid(_characters_at_exit[index]):
			_characters_at_exit.remove_at(index)
