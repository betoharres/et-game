class_name PursuitProfile
extends Resource

@export_range(1, 3) var stars: int = 1
@export var faction_name: String = "POLÍCIA"

@export_category("Resistência e movimento")
@export_range(1.0, 1000.0) var max_health: float = 60.0
@export_range(0.1, 10.0) var walk_speed: float = 2.0
@export_range(0.1, 10.0) var chase_speed: float = 3.6
@export_range(1.0, 60.0) var sight_distance: float = 30.0

@export_category("Arma")
@export_range(1.0, 60.0) var attack_range: float = 14.0
@export_range(0.1, 100.0) var damage: float = 8.0
@export_range(0.05, 5.0) var shot_interval: float = 0.9
@export_range(1, 20) var burst_size: int = 1
@export_range(0.05, 10.0) var burst_pause: float = 0.9
@export_range(0.0, 3.0) var aim_time: float = 0.65
@export_range(0.0, 10.0) var spread_degrees: float = 2.5
@export var shot_color: Color = Color(1.0, 0.72, 0.25)
@export_range(0.5, 3.0) var shot_pitch: float = 1.2
@export var laser_shots: bool = false
@export_range(-40.0, 24.0, 0.5) var shot_volume_db: float = -14.0

@export_category("Reforços")
@export_range(1, 20) var max_active: int = 2
@export_range(1, 10) var wave_size: int = 2
@export_range(1.0, 120.0) var reinforcement_interval: float = 12.0

@export_category("Assets locais")
@export var character_scene: PackedScene
@export var character_material: Material
@export var weapon_mesh: Mesh
@export var weapon_material: Material
@export var muzzle_offset: Vector3 = Vector3(0.0, 0.06, 0.22)
@export var support_hand_offset: Vector3 = Vector3(0.04, -0.03, 0.0)
