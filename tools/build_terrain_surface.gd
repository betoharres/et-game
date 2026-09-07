extends SceneTree

## Offline material data only: no heightmaps, collisions or vegetation are changed.
## Inputs are the existing local textures and Country Town's authored layout.
const Layout: GDScript = preload("res://tools/build_country_town_layout.gd")
const OUTPUT: String = "res://Texturas/terrain_surface/"
const MASK_ORIGIN: Vector2 = Vector2(-64.0, -64.0)
const MASK_EXTENT: Vector2 = Vector2(768.0, 576.0)
const MASK_SIZE: Vector2i = Vector2i(1024, 768)
const PIXEL_SIZE: float = 0.75
const YARDS: Array[String] = ["Farmhouse", "Barn", "MinePortal", "LivestockPen", "OldShed", "Windmill", "GeneralStore", "Church", "DeliveryPoint"]

var _mask: Image


func _initialize() -> void:
	if DirAccess.make_dir_recursive_absolute(OUTPUT) != OK:
		push_error("Cannot create terrain surface output directory")
		quit(1)
		return
	for texture_name: String in ["ground", "grass", "rockyCliff"]:
		if not _build_normal(texture_name):
			quit(1)
			return
	_mask = Image.create(MASK_SIZE.x, MASK_SIZE.y, false, Image.FORMAT_RGB8)
	_mask.fill(Color.BLACK)
	var segments: Array[Dictionary] = Layout.road_segments()
	for i: int in segments.size():
		var segment: Dictionary = segments[i]
		# A via de terra nao tem piso proprio: o desgaste que o terreno pinta e a
		# estrada. Borda bem esfumada, para o pasto entrar nela sem emenda.
		var dirt: bool = str(Layout.ROAD_RUNS[i][0]).begins_with("dirt")
		_stamp_segment(segment["start"], segment["end"], 4.0 if dirt else 5.0, 6.5 if dirt else 4.0, 0)
	for path: Dictionary in Layout.SECONDARY_PATHS:
		var points: Array = path["points"]
		var radius: float = float(path["width"]) * (0.5 if path["urban"] else 0.42)
		var feather: float = 3.0 if path["urban"] else 4.5
		for i: int in points.size() - 1:
			_stamp_segment(points[i], points[i + 1], radius, feather, 0)
	for field: Dictionary in Layout.CROP_FIELDS:
		_stamp_rect(field["rect"], 2.5, 1)
	for clearing: Rect2 in Layout.SETTLEMENT_CLEARINGS:
		_stamp_rect(clearing, 4.0, 0)
	var scene: PackedScene = load("res://scenes/CountryTown/Layout/PointsOfInterest.tscn") as PackedScene
	if scene == null:
		push_error("Missing Country Town POIs")
		quit(1)
		return
	var pois: Node = scene.instantiate()
	for child: Node in pois.get_children():
		if child is Marker3D and str(child.name) in YARDS:
			var marker: Marker3D = child as Marker3D
			var point: Vector2 = Vector2(marker.position.x, marker.position.z)
			_stamp_rect(Rect2(point - Vector2(7.0, 6.0), Vector2(14.0, 12.0)), 6.0, 0)
	pois.free()
	for i: int in Layout.RIVER_PATH.size() - 1:
		_stamp_segment(Layout.RIVER_PATH[i], Layout.RIVER_PATH[i + 1], Layout.river_width(i) * 0.35, 7.0, 2)
	if not _save_image(_mask, "country_land_use"):
		quit(1)
		return
	print("Terrain surface: 3 normal/roughness maps and Country Town land-use mask saved. Geometry unchanged.")
	quit()


func _stamp_rect(rect: Rect2, feather: float, channel: int) -> void:
	var bounds: Rect2i = _pixel_bounds(rect.grow(feather))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var point: Vector2 = _world_pixel(x, y)
			var outside: Vector2 = (point - rect.get_center()).abs() - rect.size * 0.5
			var distance: float = Vector2(maxf(outside.x, 0.0), maxf(outside.y, 0.0)).length()
			_write_weight(x, y, channel, 1.0 - smoothstep(0.0, feather, distance))


func _stamp_segment(a: Vector2, b: Vector2, radius: float, feather: float, channel: int) -> void:
	var bounds: Rect2i = _pixel_bounds(Rect2(a, Vector2.ZERO).expand(b).grow(radius + feather))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var point: Vector2 = _world_pixel(x, y)
			var distance: float = point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b))
			_write_weight(x, y, channel, 1.0 - smoothstep(radius, radius + feather, distance))


func _pixel_bounds(rect: Rect2) -> Rect2i:
	var begin: Vector2 = ((rect.position - MASK_ORIGIN) / PIXEL_SIZE).floor()
	var end: Vector2 = ((rect.end - MASK_ORIGIN) / PIXEL_SIZE).ceil()
	return Rect2i(Vector2i(begin), Vector2i(end - begin)).intersection(Rect2i(Vector2i.ZERO, MASK_SIZE))


func _world_pixel(x: int, y: int) -> Vector2:
	return MASK_ORIGIN + (Vector2(x, y) + Vector2(0.5, 0.5)) * PIXEL_SIZE


func _write_weight(x: int, y: int, channel: int, weight: float) -> void:
	var color: Color = _mask.get_pixel(x, y)
	color[channel] = maxf(color[channel], weight)
	_mask.set_pixel(x, y, color)


func _build_normal(texture_name: String) -> bool:
	var source: Image = Image.load_from_file("res://Texturas/%s.png" % texture_name)
	if source == null:
		push_error("Missing terrain texture: " + texture_name)
		return false
	var width: int = source.get_width()
	var height: int = source.get_height()
	var packed: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	# Low amplitude: these albedos contain painted shadows, not measured height.
	# Wrapped central differences preserve the tiling boundary; alpha is roughness.
	var strength: float = 0.45 if texture_name == "grass" else 0.8
	for y: int in height:
		for x: int in width:
			var dx: float = _luma(source, (x + 1) % width, y) - _luma(source, posmod(x - 1, width), y)
			var dy: float = _luma(source, x, (y + 1) % height) - _luma(source, x, posmod(y - 1, height))
			var normal: Vector3 = Vector3(-dx * strength, dy * strength, 1.0).normalized()
			var roughness: float = clampf(0.91 + (_luma(source, x, y) - 0.5) * 0.08, 0.82, 0.96)
			packed.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, roughness))
	return _save_image(packed, texture_name + "_normal_roughness")


func _luma(source: Image, x: int, y: int) -> float:
	var color: Color = source.get_pixel(x, y)
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _save_image(image: Image, asset_name: String) -> bool:
	image.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	var result: Error = ResourceSaver.save(texture, OUTPUT + asset_name + ".res", ResourceSaver.FLAG_COMPRESS)
	if result != OK:
		push_error("Failed to save terrain surface: " + asset_name)
	return result == OK
