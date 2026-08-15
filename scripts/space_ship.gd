extends StaticBody3D

@export var var_speed : float = 1.0

@export_group("UFO Lighting")
@export_color_no_alpha var beam_color : Color = Color(0.03, 0.58, 0.78)
@export_range(0.0, 40.0, 0.1) var beam_energy : float = 3.5
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
		spot.spot_range = 68.0
		spot.spot_angle = 11.5
		_spot_lights.append(spot)
		_base_spot_rotations.append(spot.rotation)

	for child : Node in find_children("*", "OmniLight3D", true, false):
		var hull_light := child as OmniLight3D
		if hull_light == null:
			continue
		hull_light.light_color = beam_color
		hull_light.light_energy = hull_light_energy
		hull_light.shadow_enabled = false
		hull_light.light_volumetric_fog_energy = 0.55
		_hull_lights.append(hull_light)

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


func set_atmosphere_quality(quality_level : int, particles_allowed : bool) -> void:
	var amount_scale := 1.0 if quality_level >= 2 else 0.55
	for dust : GPUParticles3D in _beam_dust:
		dust.amount = maxi(1, int(round(float(beam_particle_amount) * amount_scale)))
		dust.emitting = beam_particles_enabled and particles_allowed and quality_level > 0
		dust.visible = dust.emitting
	for volume : MeshInstance3D in _beam_volumes:
		volume.visible = quality_level > 0
