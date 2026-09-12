extends SceneTree

const AlienTechnologyItem : Script = preload("res://scripts/alien_technology_item.gd")
const AlienItemDefinition : Script = preload("res://scripts/alien_item_definition.gd")

const OUTPUT : String = "res://scenes/CountryTown/Districts/AlienDebrisTest.tscn"
const DEBRIS : PackedScene = preload("res://scenes/Items/AlienDebris.tscn")
const LOCATOR : PackedScene = preload("res://scenes/Items/DebrisLocator.tscn")
const TYPES : Array[String] = ["energy_cell", "navigation_core", "hull_fragment"]
# Poço, girassóis, celeiro/silo, estrada rural, quintal, casa, comércio e motor.
const POSITIONS : Array[Vector2] = [
	Vector2(60, 55), Vector2(38, 90), Vector2(88, 120),
	Vector2(114, 135), Vector2(464, 198), Vector2(479, 204),
	Vector2(385, 225), Vector2(521, 66),
]


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	var terrain : Terrain3D = Terrain3D.new()
	root.add_child(terrain)
	terrain.data_directory = "res://scenes/CountryTown/Terrain"
	var district : Node3D = Node3D.new()
	district.name = "AlienDebrisTest"
	for index : int in range(POSITIONS.size() + 1):
		var is_locator : bool = index == POSITIONS.size()
		var point : Vector2 = Vector2(462.8, 225) if is_locator else POSITIONS[index]
		var height : float = terrain.data.get_height(Vector3(point.x, 0, point.y))
		if not is_finite(height):
			push_error("Sem terreno para destroço em %s" % point)
			district.free()
			quit(1)
			return
		var item : AlienTechnologyItem = (LOCATOR if is_locator else DEBRIS).instantiate() as AlienTechnologyItem
		item.name = "DebrisLocator" if is_locator else "Debris%d" % (index + 1)
		if not is_locator:
			var type_id : String = "engine_wreck" if index == 7 else TYPES[index % TYPES.size()]
			item.definition = load("res://resources/alien_items/%s.tres" % type_id) as AlienItemDefinition
		district.add_child(item)
		item.owner = district
		item.position = Vector3(point.x, height + 0.65, point.y)
	var packed : PackedScene = PackedScene.new()
	var result : Error = packed.pack(district)
	if result == OK:
		result = ResourceSaver.save(packed, OUTPUT)
	district.free()
	print("Countrytown: 8 destroços e 1 localizador; resultado %d" % result)
	quit(0 if result == OK else 1)
