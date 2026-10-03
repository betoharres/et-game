extends Node3D

# Layers 14 through 19 isolate six intermediate views; the real surfaces use layer 20.
const VIEW_LAYERS: int = 0x7e000
var _pair: Node3D
var _roots: Array[Dictionary] = []
var _proxies: Array[MeshInstance3D] = []
var _viewports: Array[SubViewport] = []
var _built_limit: int = 0
var _next_layer: int = 13


func setup(pair: Node3D) -> void:
	_pair = pair
	_rebuild()


func _rebuild() -> void:
	for proxy: MeshInstance3D in _proxies:
		proxy.free()
	for viewport: SubViewport in _viewports:
		if is_instance_valid(viewport):
			viewport.free()
	_proxies.clear()
	_viewports.clear()
	_roots.clear()
	_next_layer = 13
	_built_limit = clampi(_pair.recursion_limit, 1, 3)
	_roots.append(_build_view(_pair.portal_1_camera, _pair.viewport_1, 1))
	_roots.append(_build_view(_pair.portal_2_camera, _pair.viewport_2, 1))


func _build_view(camera: Camera3D, viewport: SubViewport, depth: int) -> Dictionary:
	var view: Dictionary = {"camera": camera, "children": [], "layer": 0}
	if depth >= _built_limit:
		return view
	view["layer"] = 1 << _next_layer
	_next_layer += 1
	var portals: Array[MeshInstance3D] = [_pair.portal_1, _pair.portal_2]
	for index: int in 2:
		var entrance: MeshInstance3D = portals[index]
		var exit: MeshInstance3D = portals[1 - index]
		var child_viewport: SubViewport = SubViewport.new()
		child_viewport.world_3d = _pair.get_world_3d()
		child_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		viewport.add_child(child_viewport)
		_viewports.append(child_viewport)
		_pair._configure_viewport_aspect(child_viewport, entrance)
		child_viewport.size = Vector2i(maxi(1, child_viewport.size.x / depth), maxi(1, child_viewport.size.y / depth))
		var child_camera: Camera3D = Camera3D.new()
		child_viewport.add_child(child_camera)
		child_camera.current = true
		var proxy: MeshInstance3D = MeshInstance3D.new()
		proxy.mesh = entrance.mesh
		proxy.layers = view["layer"]
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		proxy.material_override = _pair._create_portal_material(child_viewport)
		proxy.material_override.set_shader_parameter("restrict_view", true)
		add_child(proxy)
		_proxies.append(proxy)
		var child: Dictionary = _build_view(child_camera, child_viewport, depth + 1)
		child["entrance"] = entrance
		child["exit"] = exit
		child["proxy"] = proxy
		view["children"].append(child)
	return view


func update_views() -> void:
	if _built_limit != clampi(_pair.recursion_limit, 1, 3):
		_rebuild()
	_pair.player_camera.cull_mask &= ~VIEW_LAYERS
	for view: Dictionary in _roots:
		_update_view(view)


func _update_view(view: Dictionary) -> void:
	var camera: Camera3D = view["camera"]
	camera.cull_mask = (_pair.player_camera.cull_mask & ~(_pair.PORTAL_LAYER | VIEW_LAYERS)) | int(view["layer"])
	for child: Dictionary in view["children"]:
		var entrance: MeshInstance3D = child["entrance"]
		var exit: MeshInstance3D = child["exit"]
		var proxy: MeshInstance3D = child["proxy"]
		proxy.global_transform = entrance.global_transform
		_pair._update_surface_material(proxy.material_override, entrance, camera.global_position)
		proxy.material_override.set_shader_parameter("view_position", camera.global_position)
		var virtual_position: Vector3 = _pair._portal_mapping(entrance, exit) * camera.global_position
		_pair._configure_portal_frustum(child["camera"], exit, virtual_position)
		_update_view(child)
