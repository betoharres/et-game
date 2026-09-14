extends Node3D

@export_flags_3d_render var source_layers: int = 0

var _viewport: Viewport
var _previous_occlusion: bool = false


func _enter_tree() -> void:
	_viewport = get_viewport()
	_previous_occlusion = _viewport.use_occlusion_culling
	_update_occlusion()


func _process(_delta: float) -> void:
	_update_occlusion()


func _update_occlusion() -> void:
	var camera: Camera3D = _viewport.get_camera_3d()
	# Occluders must not hide geometry through buildings removed by a camera mask.
	var enabled: bool = is_visible_in_tree() and camera != null and (camera.cull_mask & source_layers) == source_layers
	if _viewport.use_occlusion_culling != enabled:
		_viewport.use_occlusion_culling = enabled


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.use_occlusion_culling = _previous_occlusion
