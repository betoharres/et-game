extends CanvasLayer

## Persistent transition overlay (autoload). Survives scene changes because
## autoload nodes live outside the freed/replaced current_scene, so a wipe
## never has a seam at the moment the new scene is swapped in.
##
## Two transitions live here:
##
## - warp_to(): the original tractor-beam iris, still used for menu/interior
##   swaps where a calm, readable transition is what we want.
## - abduction_warp_to(): used when the player launches into a fase. It is
##   deliberately shapeless and short, and it hands over while the destination
##   scene is already animating, so the arrival never reads as a slide change.

const MAX_RADIUS : float = 1.5
const CLOSE_DURATION : float = 0.6
const HOLD_DURATION : float = 0.12
const OPEN_DURATION : float = 0.85
const WIPE_COLOR : Color = Color(0.55, 0.92, 1.0)

const ABDUCTION_CHARGE_DURATION : float = 0.45
const ABDUCTION_HOLD_DURATION : float = 0.06
const ABDUCTION_BURN_DURATION : float = 0.55

var _overlay : ColorRect
var _material : ShaderMaterial
var _flash_overlay : ColorRect
var _flash_material : ShaderMaterial
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

	_flash_material = ShaderMaterial.new()
	_flash_material.shader = load("res://shaders/abduction_flash.gdshader")
	_flash_material.set_shader_parameter("beam_color", WIPE_COLOR)
	_flash_material.set_shader_parameter("progress", 0.0)
	_flash_material.set_shader_parameter("dissipate", 0.0)

	_flash_overlay = ColorRect.new()
	_flash_overlay.material = _flash_material
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_overlay.visible = false
	add_child(_flash_overlay)


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


## Whiteout hand-off for launching into a fase. The destination scene is swapped
## in at peak brightness and starts its own animation immediately, so the burn-
## off reveals something already in motion instead of a static frame.
func abduction_warp_to(scene_path : String) -> void:
	if _busy:
		return
	_busy = true

	_flash_material.set_shader_parameter("progress", 0.0)
	_flash_material.set_shader_parameter("dissipate", 0.0)
	_flash_overlay.visible = true

	var charge_tween : Tween = create_tween()
	charge_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	charge_tween.tween_property(
		_flash_material, "shader_parameter/progress", 1.0, ABDUCTION_CHARGE_DURATION
	)
	await charge_tween.finished

	await get_tree().create_timer(ABDUCTION_HOLD_DURATION).timeout

	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame

	_flash_material.set_shader_parameter("dissipate", 1.0)
	var burn_tween : Tween = create_tween()
	burn_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	burn_tween.tween_property(
		_flash_material, "shader_parameter/progress", 0.0, ABDUCTION_BURN_DURATION
	)
	await burn_tween.finished

	_flash_overlay.visible = false
	_busy = false
