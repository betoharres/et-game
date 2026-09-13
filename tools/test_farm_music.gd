extends SceneTree

const MUSIC_SCRIPT : Script = preload("res://scripts/audio/farm_environment_audio.gd")

var _failed : bool = false


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var alert : Node = root.get_node("PhotoAlertSystem")
	alert.set_process(false)
	alert.reset()
	var music : Node = MUSIC_SCRIPT.new()
	music.set("music_crossfade_duration", 0.2)
	root.add_child(music)
	alert.register_photo()
	check(not music.has_node("BackgroundMusic") and not music.has_node("PursuitMusic"),
		"Wanted stars do not start music before touchdown")
	alert.reset()
	music.start_background_music()
	var background : AudioStreamPlayer = music.get_node("BackgroundMusic") as AudioStreamPlayer
	var pursuit : AudioStreamPlayer = music.get_node("PursuitMusic") as AudioStreamPlayer
	var target_gain : float = background.volume_linear
	check(background.playing and not pursuit.playing, "Touchdown starts the farm track")
	check((background.stream as AudioStreamMP3).loop and (pursuit.stream as AudioStreamMP3).loop,
		"Both music tracks loop")
	check(pursuit.stream.get_length() > 0.0, "Pursuit recording loads")
	alert.set_photographer_observing(123, true)
	check(background.playing and not pursuit.playing, "Observation alone does not change music")
	alert.unregister_photographer(123)
	alert.register_photo()
	check(background.playing and pursuit.playing, "First star starts a crossfade")
	await create_timer(0.08).timeout
	check(background.volume_linear > 0.0 and background.volume_linear < target_gain
		and pursuit.volume_linear > 0.0 and pursuit.volume_linear < target_gain,
		"Both tracks fade between their endpoint volumes")
	await create_timer(0.25).timeout
	check(not background.playing and pursuit.playing
		and is_equal_approx(pursuit.volume_linear, target_gain),
		"Crossfade finishes with only pursuit music playing")
	var playback_position : float = pursuit.get_playback_position()
	alert.register_photo()
	alert.register_photo()
	check(pursuit.playing and not background.playing
		and pursuit.get_playback_position() >= playback_position,
		"Further stars do not restart pursuit music")
	alert.reset()
	await create_timer(0.05).timeout
	alert.register_photo()
	await create_timer(0.3).timeout
	check(pursuit.playing and not background.playing
		and is_equal_approx(pursuit.volume_linear, target_gain),
		"A new pursuit during the return fade keeps the correct track")
	alert.reset()
	await create_timer(0.3).timeout
	check(background.playing and not pursuit.playing, "Zero stars restores farm music")
	music.start_background_music()
	check(music.get_node("BackgroundMusic") == background, "Repeated touchdown does not duplicate music")
	music.queue_free()
	await process_frame

	alert.register_photo()
	var wanted_arrival : Node = MUSIC_SCRIPT.new()
	root.add_child(wanted_arrival)
	wanted_arrival.start_background_music()
	check((wanted_arrival.get_node("PursuitMusic") as AudioStreamPlayer).playing
		and not (wanted_arrival.get_node("BackgroundMusic") as AudioStreamPlayer).playing,
		"An already-wanted player starts the pursuit track at touchdown")
	wanted_arrival.queue_free()
	await process_frame
	alert.reset()
	alert.set_process(true)
	if _failed:
		quit(1)
	else:
		print("FARM_MUSIC_TEST|PASS")
		quit()


func check(condition : bool, message : String) -> void:
	if condition:
		print("CHECK|PASS|%s" % message)
		return
	_failed = true
	push_error("CHECK|FAIL|%s" % message)
