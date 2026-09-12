extends AudioStreamPlayer

const PROCEDURAL_SFX = preload("res://scripts/audio/procedural_sfx.gd")

@export_range(-40.0, 0.0, 0.5) var hit_volume_db : float = -12.0
@export_range(0.0, 0.15, 0.01) var pitch_variation : float = 0.05
@export_range(0.0, 3.0, 0.1) var volume_variation_db : float = 0.8
@export_range(0.05, 0.5, 0.01) var minimum_interval : float = 0.12

static var _shared_stream : AudioStreamWAV = null

var _random : RandomNumberGenerator = RandomNumberGenerator.new()
var _last_hit_msec : int = -1000


func _ready() -> void:
	if _shared_stream == null:
		_shared_stream = PROCEDURAL_SFX.player_hit()
	stream = _shared_stream
	_random.randomize()
	get_parent().connect(&"damaged", _on_damaged)


func _on_damaged(_amount : float, _hit_direction : Vector3) -> void:
	var now_msec : int = Time.get_ticks_msec()
	if now_msec - _last_hit_msec < roundi(minimum_interval * 1000.0):
		return
	_last_hit_msec = now_msec
	pitch_scale = _random.randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	volume_db = hit_volume_db + _random.randf_range(-volume_variation_db, volume_variation_db)
	play()
