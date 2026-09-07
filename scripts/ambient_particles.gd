extends GPUParticles3D
## Emissores decorativos dormem longe da c?mera, inclusive dentro do frustum.
@export_range(20.0, 150.0, 1.0) var active_distance: float = 65.0
@export_range(2.0, 30.0, 1.0) var distance_hysteresis: float = 12.0
var _active: bool = false
var _running_speed: float = 1.0

func _ready() -> void:
	_running_speed = speed_scale
	emitting = false
	visible = false
	speed_scale = 0.0
	var timer: Timer = Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_update_activity)
	add_child(timer)
	timer.start()
	_update_activity()

func _update_activity() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var radius: float = active_distance + (distance_hysteresis if _active else 0.0)
	var nearby: bool = camera != null and camera.global_position.distance_squared_to(global_position) < radius * radius
	if nearby == _active:
		return
	_active = nearby
	visible = nearby
	emitting = nearby
	speed_scale = _running_speed if nearby else 0.0
	if nearby:
		restart()
