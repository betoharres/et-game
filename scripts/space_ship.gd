extends StaticBody3D

@export_range(0.0, 1.0, 0.01) var var_speed : float = 0.18

@export_group("UFO Lighting")
@export_color_no_alpha var beam_color : Color = Color(0.16, 0.68, 0.86)
@export_range(0.0, 40.0, 0.1) var beam_energy : float = 8.0
@export_range(20.0, 120.0, 1.0) var beam_range : float = 72.0
@export_range(1.0, 45.0, 0.5) var beam_angle_degrees : float = 13.0
@export_range(0.0, 2.0, 0.05) var beam_attenuation : float = 0.45
@export_range(0.0, 10.0, 0.1) var ground_light_energy : float = 2.6
@export_range(2.0, 20.0, 0.5) var ground_light_range : float = 10.0
@export_range(0.0, 0.4, 0.01) var beam_pulse_amount : float = 0.12
@export_range(0.0, 2.0, 0.01) var beam_pulse_speed : float = 0.34
@export_range(0.0, 15.0, 0.1) var beam_sweep_degrees : float = 6.5
@export_range(0.0, 2.0, 0.01) var beam_sweep_speed : float = 0.28
@export_range(0.0, 10.0, 0.1) var hull_light_energy : float = 1.8

@export_group("Beam Particles")
@export var beam_particles_enabled : bool = true
@export_range(0, 96, 1) var beam_particle_amount : int = 30

var _spot_lights : Array[SpotLight3D] = []
var _hull_lights : Array[OmniLight3D] = []
var _ground_lights : Array[OmniLight3D] = []
var _beam_dust : Array[GPUParticles3D] = []
var _beam_volumes : Array[MeshInstance3D] = []
var _base_spot_rotations : Array[Vector3] = []
var _elapsed : float = 0.0


func _ready() -> void:
	for child : Node in find_children("*", "SpotLight3D", true, false):
		var spot := child as SpotLight3D
		if spot == null:
			continue
		spot.light_color = beam_color
		spot.light_energy = beam_energy
		spot.light_volumetric_fog_energy = 1.2
		spot.spot_range = beam_range
		spot.spot_angle = beam_angle_degrees
		spot.spot_attenuation = beam_attenuation
		_spot_lights.append(spot)
		_base_spot_rotations.append(spot.rotation)

	for child : Node in find_children("HullLight*", "OmniLight3D", true, false):
		var hull_light := child as OmniLight3D
		if hull_light == null:
			continue
		hull_light.light_color = beam_color
		hull_light.light_energy = hull_light_energy
		hull_light.shadow_enabled = false
		hull_light.light_volumetric_fog_energy = 0.55
		_hull_lights.append(hull_light)

	for child : Node in find_children(
		"BeamGroundLight*",
		"OmniLight3D",
		true,
		false
	):
		var ground_light := child as OmniLight3D
		if ground_light == null:
			continue
		ground_light.light_color = beam_color
		ground_light.light_energy = ground_light_energy
		ground_light.omni_range = ground_light_range
		ground_light.shadow_enabled = false
		_ground_lights.append(ground_light)

	for child : Node in find_children("BeamDust*", "GPUParticles3D", true, false):
		var dust := child as GPUParticles3D
		if dust == null:
			continue
		_beam_dust.append(dust)

	for child : Node in find_children("BeamVolume*", "MeshInstance3D", true, false):
		var volume := child as MeshInstance3D
		if volume != null:
			_beam_volumes.append(volume)

	set_atmosphere_quality(2, beam_particles_enabled)


func _physics_process(delta: float) -> void:
	self.rotation.y += var_speed * delta
	_update_ground_lights()


func _process(delta : float) -> void:
	_elapsed += delta
	for index : int in range(_spot_lights.size()):
		var phase := float(index) * 2.17
		var speed := beam_sweep_speed * (0.82 + float(index) * 0.13)
		var pitch := sin(_elapsed * speed + phase) * deg_to_rad(beam_sweep_degrees)
		var yaw := cos(_elapsed * speed * 0.71 + phase * 1.3) * deg_to_rad(
			beam_sweep_degrees * 0.75
		)
		_spot_lights[index].rotation = _base_spot_rotations[index] + Vector3(
			pitch,
			yaw,
			0.0
		)
		var pulse := sin(_elapsed * beam_pulse_speed + phase) * beam_pulse_amount
		_spot_lights[index].light_energy = beam_energy * (1.0 + pulse)

	for index : int in range(_hull_lights.size()):
		var phase := float(index) * 1.73
		var pulse := sin(_elapsed * beam_pulse_speed * 0.8 + phase)
		_hull_lights[index].light_energy = hull_light_energy * (
			1.0 + pulse * beam_pulse_amount * 0.7
		)

func _update_ground_lights() -> void:
	if get_world_3d() == null:
		return

	var light_count := mini(_spot_lights.size(), _ground_lights.size())
	var space_state := get_world_3d().direct_space_state
	for index : int in range(light_count):
		var spot := _spot_lights[index]
		var direction := -spot.global_transform.basis.z.normalized()
		var query := PhysicsRayQueryParameters3D.create(
			spot.global_position,
			spot.global_position + direction * beam_range
		)
		query.exclude = [get_rid()]
		query.collide_with_areas = false
		var hit := space_state.intersect_ray(query)
		var ground_light := _ground_lights[index]
		ground_light.visible = not hit.is_empty()
		if hit.is_empty():
			continue

		var hit_position : Vector3 = hit.get("position", Vector3.ZERO)
		var hit_normal : Vector3 = hit.get("normal", Vector3.UP)
		ground_light.global_position = hit_position + hit_normal * 2.0
		var pulse := sin(
			_elapsed * beam_pulse_speed + float(index) * 2.17
		) * beam_pulse_amount
		ground_light.light_energy = ground_light_energy * (1.0 + pulse * 0.5)


func set_atmosphere_quality(quality_level : int, particles_allowed : bool) -> void:
	var amount_scale := 1.0 if quality_level >= 2 else 0.55
	for dust : GPUParticles3D in _beam_dust:
		dust.amount = maxi(1, int(round(float(beam_particle_amount) * amount_scale)))
		dust.emitting = beam_particles_enabled and particles_allowed and quality_level > 0
		dust.visible = dust.emitting
	for volume : MeshInstance3D in _beam_volumes:
		volume.visible = quality_level > 0


func configure_external_beam(
	spotlight : SpotLight3D,
	ground_light : OmniLight3D,
	volume : MeshInstance3D
) -> void:
	spotlight.light_color = beam_color
	spotlight.light_energy = beam_energy
	spotlight.light_volumetric_fog_energy = 1.2
	spotlight.spot_angle = beam_angle_degrees
	spotlight.spot_attenuation = beam_attenuation

	ground_light.light_color = beam_color
	ground_light.light_energy = ground_light_energy
	ground_light.omni_range = ground_light_range
	ground_light.light_volumetric_fog_energy = 0.12
	ground_light.shadow_enabled = false

	if _beam_volumes.is_empty():
		return

	var source_material := _beam_volumes[0].get_active_material(0)
	if source_material != null:
		volume.material_override = source_material
