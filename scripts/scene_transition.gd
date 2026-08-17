extends CanvasLayer

## Persistent transition overlay (autoload). Survives scene changes because
## autoload nodes live outside the freed/replaced current_scene, so the
## wipe never has a seam at the moment the new scene is swapped in.
##
## Uses shaders/tractor_beam_wipe.gdshader: a circle of "wipe_color" that
## closes over the screen (like a tractor beam collapsing to a point),
## then reopens after the scene swap to reveal what's underneath.

const MAX_RADIUS : float = 1.5
const CLOSE_DURATION : float = 0.6
const HOLD_DURATION : float = 0.12
const OPEN_DURATION : float = 0.85
const WIPE_COLOR : Color = Color(0.55, 0.92, 1.0)

var _overlay : ColorRect
var _material : ShaderMaterial
var _busy : bool = false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/tractor_beam_wipe.gdshader")
	_material.set_shader_parameter("wipe_color", WIPE_COLOR)
	_material.set_shader_parameter("radius", MAX_RADIUS)

	_overlay = ColorRect.new()
	_overlay.material = _material
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)


func warp_to(scene_path : String) -> void:
	if _busy:
		return
	_busy = true

	var close_tween : Tween = create_tween()
	close_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	close_tween.tween_property(_material, "shader_parameter/radius", 0.0, CLOSE_DURATION)
	await close_tween.finished

	await get_tree().create_timer(HOLD_DURATION).timeout

	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame

	var open_tween : Tween = create_tween()
	open_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	open_tween.tween_property(_material, "shader_parameter/radius", MAX_RADIUS, OPEN_DURATION)
	await open_tween.finished

	_busy = false
