extends Node3D

# Giramos o céu inteiro ao invés da nave, para não dar problemas na física

@export var sun : DirectionalLight3D
@export_range(0.0, 0.5, 0.001) var rotation_speed : float = 0.006
@export_range(0.0, 0.5, 0.001) var sky_rotation_speed : float = 0.06

@onready var surface : MeshInstance3D = $Earth/Surface
@onready var atmosphere : MeshInstance3D = $Earth/Atmosphere


func _ready() -> void:
	_apply_sun_direction()


func _process(delta : float) -> void:
	surface.rotate_y(rotation_speed * delta)
	self.rotate_y(sky_rotation_speed * delta)


func _apply_sun_direction() -> void:
	if sun == null:
		return
	# A luz viaja no -Z do nó, então +Z aponta de volta para o sol.
	var to_sun : Vector3 = sun.global_transform.basis.z.normalized()
	_set_shader_parameter(surface, to_sun)
	_set_shader_parameter(atmosphere, to_sun)


func _set_shader_parameter(mesh_instance : MeshInstance3D, to_sun : Vector3) -> void:
	var material : ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("sun_direction", to_sun)
