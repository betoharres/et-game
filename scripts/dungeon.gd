extends Node3D

## Procedural wooden cellar: rectangular rooms on a grid, connected in
## sequence by corridors, with full-height walls auto-placed on every floor
## cell edge and a closed ceiling over every walkable cell (GridMap).
## The layout is built once per session by ensure_generated(), called from
## DungeonDoor.gd; later calls only reposition the exit and never regenerate
## the GridMap. The dungeon sits far outside the farm's NavigationRegion3D
## bounds and has no NavigationRegion3D of its own, so it never affects the
## farmer's or photographer's pathfinding.
##
## Vertical layout inside one grid cell (cell_size.y is 3.0 and the GridMap
## centers cells on Y, so the layer 0 cell center sits at local y 1.5):
##
##   floor slab   centered on the cell center  -> top face at +0.15
##   wall block   sits on the floor top        -> +0.15 .. +3.15
##   ceiling slab layer 1, resting on the wall -> +3.15 .. +3.45

const GRID_SIZE : int = 40
const ROOM_COUNT : int = 6
const ROOM_MIN_SIZE : int = 3
const ROOM_MAX_SIZE : int = 6
const PLACEMENT_ATTEMPTS : int = 200
const CELL_SIZE : Vector3 = Vector3(4.0, 3.0, 4.0)
const FLOOR_THICKNESS : float = 0.3
const CEILING_THICKNESS : float = 0.3
const ROOM_HEIGHT : float = 3.0

const FLOOR_ITEM_ID : int = 0
const WALL_ITEM_ID : int = 1
const CEILING_ITEM_ID : int = 2

const CEILING_LAYER : int = 1

const FLOOR_WOOD_COLOR : Color = Color(0.30, 0.20, 0.12)
const WALL_WOOD_COLOR : Color = Color(0.37, 0.26, 0.16)
const CEILING_WOOD_COLOR : Color = Color(0.21, 0.14, 0.09)

const LAMP_COLOR : Color = Color(1.0, 0.82, 0.55)
const LAMP_ENERGY : float = 2.4
const LAMP_RANGE : float = 16.0

const SCRAP_SCENE : PackedScene = preload("res://scenes/spaceship_scraps.tscn")

const NEIGHBOR_DIRECTIONS : Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

@onready var grid_map : GridMap = $GridMap
@onready var exit_trigger : Area3D = $ExitDoor/ExitTrigger
@onready var exit_prompt : Label3D = $ExitDoor/ExitPrompt

var _generated : bool = false
var _entry_cell : Vector2i = Vector2i.ZERO
var _farm_return_position : Vector3 = Vector3.ZERO
var _characters_at_exit : Array[CharacterBody3D] = []


func _ready() -> void:
	grid_map.mesh_library = _build_mesh_library()
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


## Builds the layout the first time it is called in a session. Subsequent
## calls only refresh the return position and teleport target; the GridMap
## itself is left untouched.
func ensure_generated(farm_return_position : Vector3) -> void:
	_farm_return_position = farm_return_position

	if _generated:
		return

	_generated = true
	_generate_layout()


func get_entry_global_position() -> Vector3:
	return _floor_top_global(_entry_cell)


func _generate_layout() -> void:
	randomize()

	var rooms : Array[Rect2i] = _place_rooms()
	var floor_cells : Dictionary = {}

	for room : Rect2i in rooms:
		for x : int in range(room.position.x, room.position.x + room.size.x):
			for z : int in range(room.position.y, room.position.y + room.size.y):
				floor_cells[Vector2i(x, z)] = true

	for i : int in range(1, rooms.size()):
		_carve_corridor(
			_room_center(rooms[i - 1]),
			_room_center(rooms[i]),
			floor_cells
		)

	var wall_cells : Dictionary = _find_wall_cells(floor_cells)

	for cell : Vector2i in floor_cells.keys():
		grid_map.set_cell_item(Vector3i(cell.x, 0, cell.y), FLOOR_ITEM_ID)
		grid_map.set_cell_item(
			Vector3i(cell.x, CEILING_LAYER, cell.y),
			CEILING_ITEM_ID
		)

	for cell : Vector2i in wall_cells.keys():
		grid_map.set_cell_item(Vector3i(cell.x, 0, cell.y), WALL_ITEM_ID)

	_entry_cell = _room_center(rooms[0])
	_position_exit_door()
	_spawn_ceiling_lamps(rooms)
	_spawn_scraps(rooms)


func _place_rooms() -> Array[Rect2i]:
	var rooms : Array[Rect2i] = []

	for room_index : int in range(ROOM_COUNT):
		for attempt : int in range(PLACEMENT_ATTEMPTS):
			var width : int = randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
			var height : int = randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
			var x : int = randi_range(1, GRID_SIZE - width - 1)
			var z : int = randi_range(1, GRID_SIZE - height - 1)
			var candidate := Rect2i(x, z, width, height)
			var padded : Rect2i = candidate.grow(1)

			var overlaps : bool = false

			for existing_room : Rect2i in rooms:
				if padded.intersects(existing_room.grow(1)):
					overlaps = true
					break

			if not overlaps:
				rooms.append(candidate)
				break

	return rooms


func _room_center(room : Rect2i) -> Vector2i:
	return Vector2i(
		room.position.x + room.size.x / 2,
		room.position.y + room.size.y / 2
	)


func _carve_corridor(
	from : Vector2i,
	to : Vector2i,
	floor_cells : Dictionary
) -> void:
	var x : int = from.x
	var z : int = from.y

	while x != to.x:
		floor_cells[Vector2i(x, z)] = true
		x += 1 if to.x > x else -1

	while z != to.y:
		floor_cells[Vector2i(x, z)] = true
		z += 1 if to.y > z else -1

	floor_cells[Vector2i(x, z)] = true


func _find_wall_cells(floor_cells : Dictionary) -> Dictionary:
	var wall_cells : Dictionary = {}

	for cell : Vector2i in floor_cells.keys():
		for direction : Vector2i in NEIGHBOR_DIRECTIONS:
			var neighbor : Vector2i = cell + direction
			if not floor_cells.has(neighbor):
				wall_cells[neighbor] = true

	return wall_cells


func _position_exit_door() -> void:
	var exit_door : Node3D = $ExitDoor
	exit_door.global_position = _floor_top_global(_entry_cell)


func _spawn_scraps(rooms : Array[Rect2i]) -> void:
	if rooms.size() < 2:
		return

	var scrap_room_indices : Array[int] = [rooms.size() - 1]

	if rooms.size() >= 4:
		scrap_room_indices.append(rooms.size() / 2)

	for room_index : int in scrap_room_indices:
		var scrap : RigidBody3D = SCRAP_SCENE.instantiate()
		add_child(scrap)
		scrap.global_position = (
			_floor_top_global(_room_center(rooms[room_index]))
			+ Vector3.UP * 0.3
		)


func _floor_top_global(cell : Vector2i) -> Vector3:
	var local_center : Vector3 = grid_map.map_to_local(
		Vector3i(cell.x, 0, cell.y)
	)
	return grid_map.to_global(local_center + Vector3.UP * (FLOOR_THICKNESS * 0.5))


func _build_mesh_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	var floor_top : float = FLOOR_THICKNESS * 0.5

	# Floor slab, centered on the cell so its top face lands at +floor_top.
	_add_box_item(
		library,
		FLOOR_ITEM_ID,
		Vector3(CELL_SIZE.x, FLOOR_THICKNESS, CELL_SIZE.z),
		0.0,
		FLOOR_WOOD_COLOR
	)

	# Wall block standing on the floor top, tall enough to reach the ceiling.
	_add_box_item(
		library,
		WALL_ITEM_ID,
		Vector3(CELL_SIZE.x, ROOM_HEIGHT, CELL_SIZE.z),
		floor_top + ROOM_HEIGHT * 0.5,
		WALL_WOOD_COLOR
	)

	# Ceiling slab, placed one layer up and resting on top of the walls.
	_add_box_item(
		library,
		CEILING_ITEM_ID,
		Vector3(CELL_SIZE.x, CEILING_THICKNESS, CELL_SIZE.z),
		floor_top + ROOM_HEIGHT + CEILING_THICKNESS * 0.5 - CELL_SIZE.y,
		CEILING_WOOD_COLOR
	)

	return library


## Registers one box item whose mesh and collision are shifted by
## vertical_offset from the center of the grid cell that holds it.
func _add_box_item(
	library : MeshLibrary,
	item_id : int,
	size : Vector3,
	vertical_offset : float,
	wood_color : Color
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _make_wood_material(wood_color)

	var shape := BoxShape3D.new()
	shape.size = size

	var offset := Transform3D(Basis.IDENTITY, Vector3.UP * vertical_offset)

	library.create_item(item_id)
	library.set_item_mesh(item_id, mesh)
	library.set_item_mesh_transform(item_id, offset)
	library.set_item_shapes(item_id, [shape, offset])


func _make_wood_material(wood_color : Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = wood_color
	material.roughness = 0.92
	material.metallic = 0.0
	return material


func _spawn_ceiling_lamps(rooms : Array[Rect2i]) -> void:
	for room : Rect2i in rooms:
		var lamp := OmniLight3D.new()
		lamp.light_color = LAMP_COLOR
		lamp.light_energy = LAMP_ENERGY
		lamp.omni_range = LAMP_RANGE
		lamp.shadow_enabled = true
		add_child(lamp)
		lamp.global_position = (
			_floor_top_global(_room_center(room))
			+ Vector3.UP * (ROOM_HEIGHT - 0.45)
		)


func _return_to_farm() -> void:
	for character : CharacterBody3D in _characters_at_exit:
		if is_instance_valid(character):
			character.global_position = _farm_return_position
			character.velocity = Vector3.ZERO

	_characters_at_exit.clear()


func _on_exit_body_entered(body : Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("characters"):
		var character := body as CharacterBody3D
		if not _characters_at_exit.has(character):
			_characters_at_exit.append(character)


func _on_exit_body_exited(body : Node3D) -> void:
	if body is CharacterBody3D:
		_characters_at_exit.erase(body)


func _cleanup_characters() -> void:
	for index : int in range(_characters_at_exit.size() - 1, -1, -1):
		if not is_instance_valid(_characters_at_exit[index]):
			_characters_at_exit.remove_at(index)
