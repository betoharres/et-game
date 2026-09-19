class_name LivingLightTrail
extends MeshInstance3D

@export var emitting : bool = false
@export_range(0.01, 3.0, 0.01) var lifetime : float = 0.16
@export_range(0.001, 1.0, 0.001) var width : float = 0.05
@export var color : Color = Color.WHITE
@export var color_gradient : Gradient
@export var width_curve : Curve
@export_range(0.001, 1.0, 0.001) var min_section_length : float = 0.06
@export var tiling_multiplier : float = 1.0
@export var pin_uv : bool = true

var _points : PackedVector3Array = PackedVector3Array()
var _sample_times : PackedFloat64Array = PackedFloat64Array()
var _time : float = 0.0
var _travel_distance : float = 0.0
var _ribbon : ArrayMesh = ArrayMesh.new()


func _ready() -> void:
	mesh = _ribbon
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func clear() -> void:
	_points.clear()
	_sample_times.clear()
	_travel_distance = 0.0
	_ribbon.clear_surfaces()


func _process(delta : float) -> void:
	_time += delta
	while not _sample_times.is_empty() and _time - _sample_times[0] >= lifetime:
		_points.remove_at(0)
		_sample_times.remove_at(0)
	if emitting:
		if _points.is_empty():
			_points.append(global_position)
			_sample_times.append(_time)
		elif _points[-1].distance_to(global_position) >= min_section_length:
			_travel_distance += _points[-1].distance_to(global_position)
			_points.append(global_position)
			_sample_times.append(_time)
	_rebuild_ribbon()


func _rebuild_ribbon() -> void:
	_ribbon.clear_surfaces()
	if _points.is_empty():
		return
	var positions : PackedVector3Array = PackedVector3Array()
	var head_distance : float = 0.0
	if emitting and not global_position.is_equal_approx(_points[-1]):
		positions.append(Vector3.ZERO)
		head_distance = global_position.distance_to(_points[-1])
	# Samples stay in world space even when the ship carries and rotates the creature.
	for index : int in range(_points.size() - 1, -1, -1):
		positions.append(to_local(_points[index]))
	if positions.size() < 2:
		return
	var distances : PackedFloat32Array = PackedFloat32Array()
	distances.resize(positions.size())
	for index : int in range(1, positions.size()):
		distances[index] = distances[index - 1] + positions[index - 1].distance_to(positions[index])
	var length : float = distances[-1]
	if length <= 0.00001:
		return
	var vertices : PackedVector3Array = PackedVector3Array()
	var colors : PackedColorArray = PackedColorArray()
	var uvs : PackedVector2Array = PackedVector2Array()
	var custom : PackedFloat32Array = PackedFloat32Array()
	var bounds : AABB = AABB(positions[0], Vector3.ZERO)
	for index : int in range(positions.size()):
		var ratio : float = distances[index] / length
		var previous : Vector3 = positions[maxi(0, index - 1)]
		var next : Vector3 = positions[mini(positions.size() - 1, index + 1)]
		var tangent : Vector3 = (next - previous).normalized()
		if tangent.is_zero_approx():
			tangent = (positions[index] - previous).normalized()
		var half_width : float = width * 0.5
		if width_curve != null:
			half_width *= width_curve.sample(ratio)
		var vertex_color : Color = color
		if color_gradient != null:
			vertex_color *= color_gradient.sample(ratio)
		var uv_distance : float = distances[index]
		if pin_uv:
			uv_distance -= _travel_distance + head_distance
		for side : int in range(2):
			vertices.append(positions[index])
			colors.append(vertex_color)
			uvs.append(Vector2(uv_distance * tiling_multiplier, float(side)))
			# The existing shader expands each center-line pair to face the camera.
			custom.append_array(PackedFloat32Array([
				tangent.x, tangent.y, tangent.z, half_width * (-1.0 if side == 0 else 1.0),
			]))
		bounds = bounds.expand(positions[index])
	var arrays : Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	_ribbon.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	)
	custom_aabb = bounds.grow(width * 0.5 + 0.01)
