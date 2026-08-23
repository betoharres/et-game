class_name GroundFogLayer
extends Node3D

## Nevoa rasteira otimizada: poucas camadas de planos transparentes que seguem
## a camera e compartilham um unico ShaderMaterial (shaders/ground_fog.gdshader).
## Substitui volumetria cara perto do chao. O custo real e fill-rate, entao o
## numero de camadas, o raio e a distancia de fade vem do preset de qualidade.

const MAX_ZONES : int = 6
const ZONE_FLOATS : int = 4
const ZONE_GROUP : StringName = &"fog_zones"
## Folga entre o fim do fade e a borda geometrica dos planos.
const RADIUS_MARGIN : float = 6.0

@export_group("Layers")
## Altura de cada camada acima do chao, da mais baixa para a mais alta.
@export var layer_heights : PackedFloat32Array = PackedFloat32Array([0.25, 0.7, 1.4])
## Escala do ruido por camada; valores menores geram manchas maiores.
@export var layer_noise_scales : PackedFloat32Array = PackedFloat32Array([1.0, 0.62, 0.38])
## Opacidade relativa por camada.
@export var layer_opacities : PackedFloat32Array = PackedFloat32Array([1.0, 0.55, 0.3])

@export_group("Follow")
## Empurra o centro dos planos para a frente da camera. O raio cresce junto para
## que o fade continue terminando antes da borda, entao valores altos so ampliam
## a area rasterizada: mantenha em 0 a menos que exista um motivo especifico.
@export_range(0.0, 0.6, 0.01) var forward_bias : float = 0.0
## Intervalo entre sondagens da altura do terreno, em segundos.
@export_range(0.05, 2.0, 0.05) var ground_probe_interval : float = 0.25
@export_range(0.5, 20.0, 0.5) var ground_follow_speed : float = 4.0
@export_range(4.0, 120.0, 1.0) var ground_probe_length : float = 60.0

@export_group("Zones")
## Intervalo entre atualizacoes da lista de zonas proximas, em segundos.
@export_range(0.05, 2.0, 0.05) var zone_refresh_interval : float = 0.25
@export_range(10.0, 300.0, 5.0) var zone_max_distance : float = 120.0

@export_group("Alien")
@export_range(0.5, 20.0, 0.5) var alien_response : float = 3.0
## Quanto a nevoa acelera durante um evento alienigena.
@export_range(0.0, 4.0, 0.05) var alien_drift_boost : float = 1.6
## Quanto a nevoa fica mais densa durante um evento alienigena.
@export_range(0.0, 1.0, 0.01) var alien_opacity_boost : float = 0.16

var _layers : Array[MeshInstance3D] = []
var _material : ShaderMaterial
var _zone_data : PackedFloat32Array = PackedFloat32Array()
var _active_layers : int = 3
var _base_opacity : float = 0.42
var _base_drift_speed : float = 0.11
var _radius : float = 110.0
var _forward_offset : float = 0.0
var _max_zones : int = 4
var _density_scale : float = 1.0
var _alien_target : float = 0.0
var _alien_current : float = 0.0
var _ground_height : float = 0.0
var _ground_height_ready : bool = false
var _probe_timer : float = 0.0
var _zone_timer : float = 0.0
var _fog_enabled : bool = true


func _ready() -> void:
	_zone_data.resize(MAX_ZONES * ZONE_FLOATS)
	for child : Node in get_children():
		var layer := child as MeshInstance3D
		if layer == null:
			continue
		_layers.append(layer)
		if _material == null:
			_material = layer.get_active_material(0) as ShaderMaterial

	if _material == null:
		push_warning("GroundFogLayer sem ShaderMaterial: nevoa rasteira desativada.")
		set_process(false)
		set_physics_process(false)
		return

	_base_opacity = _shader_float("opacity", _base_opacity)
	_base_drift_speed = _shader_float("drift_speed", _base_drift_speed)
	for index : int in range(_layers.size()):
		_apply_layer_instance_parameters(index)
	_refresh_layer_visibility()


func _process(delta : float) -> void:
	if not _fog_enabled:
		return

	_update_alien_blend(delta)
	_follow_camera()

	_zone_timer -= delta
	if _zone_timer <= 0.0:
		_zone_timer = zone_refresh_interval
		_update_zones()


func _physics_process(delta : float) -> void:
	if not _fog_enabled:
		return

	_probe_timer -= delta
	if _probe_timer > 0.0:
		return
	_probe_timer = ground_probe_interval
	_probe_ground_height()


## Aplica um preset de qualidade. Chaves usadas: layers, opacity, zones,
## far_start, far_end, height_start, height_end, soft_depth, detail e warp.
func apply_quality(config : Dictionary) -> void:
	_active_layers = clampi(int(config.get("layers", 3)), 0, _layers.size())
	_max_zones = clampi(int(config.get("zones", 4)), 0, MAX_ZONES)
	_base_opacity = float(config.get("opacity", 0.42))

	if _material != null:
		var far_start := float(config.get("far_start", 58.0))
		var far_end := float(config.get("far_end", 98.0))
		_material.set_shader_parameter("far_fade_start", far_start)
		_material.set_shader_parameter("far_fade_end", far_end)
		_material.set_shader_parameter(
			"height_fade_start",
			float(config.get("height_start", 9.0))
		)
		_material.set_shader_parameter(
			"height_fade_end",
			float(config.get("height_end", 28.0))
		)
		_material.set_shader_parameter(
			"soft_depth",
			float(config.get("soft_depth", 3.0))
		)
		_material.set_shader_parameter(
			"detail_amount",
			float(config.get("detail", 1.0))
		)
		_material.set_shader_parameter("warp_amount", float(config.get("warp", 1.15)))
		var safe_bias := clampf(forward_bias, 0.0, 0.6)
		_radius = (far_end + RADIUS_MARGIN) / (1.0 - safe_bias)
		_forward_offset = _radius * safe_bias

	_refresh_layer_visibility()
	_apply_opacity()
	_update_zones()


func set_fog_enabled(value : bool) -> void:
	_fog_enabled = value
	_refresh_layer_visibility()


func is_fog_enabled() -> bool:
	return _fog_enabled


## Multiplicador global de densidade, usado pelo slider de neblina do debug.
func set_density_scale(value : float) -> void:
	_density_scale = maxf(value, 0.0)
	_apply_opacity()


## Alvo de tonalidade e densidade alienigena; a transicao e suavizada.
func set_alien_blend(value : float) -> void:
	_alien_target = clampf(value, 0.0, 1.0)


func get_alien_blend() -> float:
	return _alien_current


func set_fog_colors(base_color : Color, alien_color : Color) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("fog_color", base_color)
	_material.set_shader_parameter("alien_color", alien_color)


func _apply_layer_instance_parameters(index : int) -> void:
	var layer := _layers[index]
	layer.set_instance_shader_parameter("layer_seed", float(index) * 1.37)
	layer.set_instance_shader_parameter(
		"layer_scale",
		_array_value(layer_noise_scales, index, 1.0)
	)
	layer.set_instance_shader_parameter(
		"layer_opacity",
		_array_value(layer_opacities, index, 1.0)
	)


func _refresh_layer_visibility() -> void:
	for index : int in range(_layers.size()):
		_layers[index].visible = _fog_enabled and index < _active_layers


func _apply_opacity() -> void:
	if _material == null:
		return
	var alien_opacity := 1.0 + _alien_current * alien_opacity_boost
	_material.set_shader_parameter(
		"opacity",
		clampf(_base_opacity * _density_scale * alien_opacity, 0.0, 1.0)
	)


func _update_alien_blend(delta : float) -> void:
	if is_equal_approx(_alien_current, _alien_target):
		return

	var weight := 1.0 - exp(-alien_response * delta)
	_alien_current = lerpf(_alien_current, _alien_target, weight)
	if absf(_alien_current - _alien_target) < 0.002:
		_alien_current = _alien_target

	_material.set_shader_parameter("alien_blend", _alien_current)
	_material.set_shader_parameter(
		"drift_speed",
		_base_drift_speed * (1.0 + _alien_current * alien_drift_boost)
	)
	_apply_opacity()


func _follow_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var camera_position := camera.global_position
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.001:
		forward = forward.normalized()
	else:
		forward = Vector3.FORWARD

	if not _ground_height_ready:
		_ground_height = camera_position.y
		_ground_height_ready = true

	var center := camera_position + forward * _forward_offset
	global_position = Vector3(center.x, _ground_height, center.z)

	for index : int in range(_active_layers):
		_layers[index].position = Vector3(
			0.0,
			_array_value(layer_heights, index, 1.0),
			0.0
		)
		_layers[index].scale = Vector3(_radius, 1.0, _radius)


func _probe_ground_height() -> void:
	var camera := get_viewport().get_camera_3d()
	var world := get_world_3d()
	if camera == null or world == null:
		return

	var origin := camera.global_position + Vector3.UP * 4.0
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + Vector3.DOWN * ground_probe_length
	)
	query.collide_with_areas = false
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var hit_position : Vector3 = hit.get("position", Vector3.ZERO)
	if not _ground_height_ready:
		_ground_height = hit_position.y
		_ground_height_ready = true
		return

	var weight := clampf(ground_follow_speed * ground_probe_interval, 0.0, 1.0)
	_ground_height = lerpf(_ground_height, hit_position.y, weight)


func _update_zones() -> void:
	if _material == null:
		return

	for index : int in range(_zone_data.size()):
		_zone_data[index] = 0.0

	var used := 0
	if _max_zones > 0:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			used = _collect_zones(camera.global_position)

	_material.set_shader_parameter("fog_zone_count", used)
	_material.set_shader_parameter("fog_zone_data", _zone_data)


func _collect_zones(camera_position : Vector3) -> int:
	var candidates : Array[Dictionary] = []
	for node : Node in get_tree().get_nodes_in_group(ZONE_GROUP):
		var zone := node as Node3D
		if zone == null or not zone.has_method(&"get_fog_strength"):
			continue
		var strength := float(zone.call(&"get_fog_strength"))
		if strength <= 0.0:
			continue
		var zone_position := zone.global_position
		var radius := float(zone.call(&"get_fog_radius"))
		var distance := Vector2(
			zone_position.x - camera_position.x,
			zone_position.z - camera_position.z
		).length()
		if distance - radius > zone_max_distance:
			continue
		candidates.append({
			"position": zone_position,
			"radius": radius,
			"strength": strength,
			"distance": distance,
		})

	candidates.sort_custom(_compare_zone_distance)

	var used := mini(candidates.size(), _max_zones)
	for index : int in range(used):
		var zone : Dictionary = candidates[index]
		var offset := index * ZONE_FLOATS
		var zone_position : Vector3 = zone["position"]
		_zone_data[offset] = zone_position.x
		_zone_data[offset + 1] = zone_position.z
		_zone_data[offset + 2] = float(zone["radius"])
		_zone_data[offset + 3] = float(zone["strength"])
	return used


func _compare_zone_distance(first : Dictionary, second : Dictionary) -> bool:
	return float(first["distance"]) < float(second["distance"])


func _shader_float(parameter : StringName, fallback : float) -> float:
	var stored : Variant = _material.get_shader_parameter(parameter)
	if stored == null:
		return fallback
	return float(stored)


func _array_value(values : PackedFloat32Array, index : int, fallback : float) -> float:
	if index < 0 or index >= values.size():
		return fallback
	return values[index]
