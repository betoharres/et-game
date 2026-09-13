extends SceneTree

var _failed : bool = false
var _damage_count : int = 0
var _last_damage : float = 0.0
var _last_direction : Vector3 = Vector3.ZERO


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var player : CharacterBody3D = (
		load("res://scenes/Player.tscn") as PackedScene
	).instantiate() as CharacterBody3D
	player.connect(&"damaged", _record_damage)
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	await process_frame

	var hud : CanvasLayer = player.get_node("PlayerHUD") as CanvasLayer
	var effect : ColorRect = hud.get_node("Interface/DamageVignette") as ColorRect
	var buffer : BackBufferCopy = hud.get_node("Interface/DamageBackBuffer") as BackBufferCopy
	var material : ShaderMaterial = effect.material as ShaderMaterial
	var audio : AudioStreamPlayer = player.get_node("HitAudio") as AudioStreamPlayer
	var death_effect : CanvasLayer = player.get_node("DeathEffect") as CanvasLayer
	var death_audio : AudioStreamPlayer = death_effect.get_node("DeathAudio") as AudioStreamPlayer
	var other_hud : CanvasLayer = (
		load("res://scenes/PlayerHUD.tscn") as PackedScene
	).instantiate() as CanvasLayer
	var other_material : ShaderMaterial = (
		other_hud.get_node("Interface/DamageVignette") as ColorRect
	).material as ShaderMaterial

	check(_damage_count == 0 and not audio.playing, "Initialization does not report or play damage")
	check(not death_effect.visible and not death_audio.playing,
		"Initialization keeps death audio and grayscale inactive")
	check(not effect.visible and not buffer.visible, "Initialization keeps the screen pass hidden")
	player.call("take_damage", 0.0)
	player.call("take_damage", -10.0)
	player.call("set_debug_god_mode_enabled", true)
	player.call("take_damage", 20.0, Vector3.LEFT)
	check(_damage_count == 0 and not audio.playing and not effect.visible,
		"Nonpositive damage and god mode produce no hit feedback")
	player.call("set_debug_god_mode_enabled", false)

	player.call("take_damage", 20.0, Vector3.LEFT)
	check(_damage_count == 1 and is_equal_approx(_last_damage, 20.0)
		and _last_direction.is_equal_approx(Vector3.LEFT), "Damage reports the applied amount and direction")
	check(audio.playing and audio.stream != null, "A real hit starts its sound")
	check(not death_effect.visible and not death_audio.playing,
		"A nonfatal hit does not activate death feedback")
	check(effect.visible and buffer.visible
		and float(material.get_shader_parameter("intensity")) > 0.0
		and float(material.get_shader_parameter("impact_strength")) > 0.0,
		"A real hit enables the screen flash and impact")
	check(material != other_material
		and is_zero_approx(float(other_material.get_shader_parameter("intensity"))),
		"Damage does not leak into another HUD instance")

	var peak : float = float(material.get_shader_parameter("intensity"))
	audio.stop()
	player.call("take_damage", 1.0)
	check(_damage_count == 2 and not audio.playing, "Rapid hits report damage without retriggering audio")
	check(float(material.get_shader_parameter("intensity")) >= peak,
		"A smaller repeated hit preserves the active screen peak")

	await create_timer(float(hud.get("damage_fade_duration")) + 0.1).timeout
	check(not effect.visible and not buffer.visible
		and is_zero_approx(float(material.get_shader_parameter("impact_strength"))),
		"The flash fades and releases both screen passes")
	player.call("set_debug_god_mode_enabled", true)
	check(is_equal_approx(float(player.call("get_health")), float(player.call("get_max_health")))
		and _damage_count == 2 and not audio.playing and not effect.visible,
		"Healing through health_changed stays silent")
	player.call("set_debug_god_mode_enabled", false)

	player.call("take_damage", 10.0)
	check(_damage_count == 3 and audio.playing and effect.visible,
		"A hit after cooldown starts fresh feedback")
	await create_timer(float(hud.get("damage_fade_duration")) + 0.1).timeout
	var remaining_health : float = float(player.call("get_health"))
	player.call("take_damage", remaining_health + 50.0, Vector3.BACK)
	check(_damage_count == 4 and is_equal_approx(_last_damage, remaining_health)
		and not bool(player.call("is_alive")), "Fatal damage reports only the remaining health")
	check(audio.playing and effect.visible and buffer.visible,
		"Fatal damage still produces sound and screen feedback")
	check(death_effect.visible and death_audio.playing
		and death_audio.stream.resource_path == "res://assets/audio/player/et-death.mp3"
		and not (death_audio.stream as AudioStreamMP3).loop,
		"Death enables grayscale and plays the requested sound once")
	check(death_effect.layer > 1 and death_effect.layer < hud.layer
		and bool(hud.get("defeat_menu").visible),
		"Death renders after world effects and beneath the existing HUD and defeat menu")
	await create_timer(float(hud.get("damage_fade_duration")) + 0.1).timeout
	audio.stop()
	death_audio.stop()
	player.call("take_damage", 10.0, Vector3.RIGHT)
	check(_damage_count == 4 and not audio.playing and not effect.visible and not buffer.visible,
		"Damage after death cannot restart feedback")
	check(death_effect.visible and not death_audio.playing,
		"Grayscale persists after the hit flash without replaying the death sound")

	other_hud.free()
	player.queue_free()
	await process_frame
	var fresh_player : CharacterBody3D = (
		load("res://scenes/Player.tscn") as PackedScene
	).instantiate() as CharacterBody3D
	root.add_child(fresh_player)
	fresh_player.set_physics_process(false)
	fresh_player.set_process_input(false)
	var fresh_effect : CanvasLayer = fresh_player.get_node("DeathEffect") as CanvasLayer
	var fresh_audio : AudioStreamPlayer = fresh_effect.get_node("DeathAudio") as AudioStreamPlayer
	check(not fresh_effect.visible and not fresh_audio.playing,
		"A new player starts with color restored and no death sound")
	fresh_player.queue_free()
	await process_frame
	if _failed:
		quit(1)
	else:
		print("PLAYER_DAMAGE_FEEDBACK_TEST|PASS")
		quit()


func _record_damage(amount : float, direction : Vector3) -> void:
	_damage_count += 1
	_last_damage = amount
	_last_direction = direction


func check(condition : bool, label : String) -> void:
	if condition:
		print("CHECK|PASS|%s" % label)
		return
	_failed = true
	push_error("CHECK|FAIL|%s" % label)
