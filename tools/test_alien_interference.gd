extends SceneTree

var _failed : bool = false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var source : AlienInterferenceSource = AlienInterferenceSource.new()
	source.pulse_amount = 0.0
	source.full_strength_radius = 3.0
	source.fade_radius = 12.0
	source.intensity = 0.8
	root.add_child(source)
	await process_frame

	var near_strength : float = source.get_interference_at(Vector3.ZERO)
	var middle_strength : float = source.get_interference_at(Vector3(7.5, 0.0, 0.0))
	var far_strength : float = source.get_interference_at(Vector3(20.0, 0.0, 0.0))
	_check(is_equal_approx(near_strength, 0.8), "Source reaches full strength nearby")
	_check(
		middle_strength > 0.0 and middle_strength < near_strength,
		"Source fades smoothly with distance"
	)
	_check(is_zero_approx(far_strength), "Source stops outside fade radius")
	source.set_interference_enabled(false)
	_check(
		is_zero_approx(source.get_interference_at(Vector3.ZERO)),
		"Source can be disabled by code"
	)
	source.queue_free()

	var environment : Node = (
		load("res://scenes/NightEnvironment.tscn") as PackedScene
	).instantiate()
	root.add_child(environment)
	await process_frame
	var post_process : Node = environment.get_node("IncidentPostProcess")
	var camera : Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var spatial_source : AlienInterferenceSource = AlienInterferenceSource.new()
	spatial_source.pulse_amount = 0.0
	spatial_source.intensity = 0.7
	spatial_source.add_to_group("alien_interference_sources")
	root.add_child(spatial_source)
	await process_frame
	_check(
		float(post_process.call("_sample_spatial_interference")) > 0.6,
		"Post-process samples nearby spatial sources"
	)
	post_process.call("set_manual_interference", 0.75)
	for _frame : int in 20:
		await process_frame
	_check(
		float(post_process.call("get_interference_intensity")) > 0.5,
		"Manual interference blends into the post-process"
	)
	post_process.call("clear_manual_interference")
	post_process.call("pulse_interference", 0.9, 0.5)
	await process_frame
	_check(
		post_process.has_method("pulse_interference"),
		"Reusable pulse API is available"
	)

	for scene_path : String in [
		"res://scenes/space_ship.tscn",
		"res://scenes/ArrivalBeam.tscn",
		"res://scenes/DeliveryArea.tscn",
	]:
		var instance : Node = (load(scene_path) as PackedScene).instantiate()
		root.add_child(instance)
		var event_source : Node = instance.get_node_or_null("AlienInterferenceSource")
		_check(
			event_source != null
			and event_source.is_in_group("alien_interference_sources"),
			"Alien source configured in %s" % scene_path.get_file()
		)
		if scene_path.ends_with("ArrivalBeam.tscn"):
			instance.call("configure", Vector3(10.0, 2.0, -5.0), 20.0)
			_check(
				event_source.global_position.is_equal_approx(
					Vector3(10.0, 12.0, -5.0)
				),
				"Arrival interference follows the beam midpoint"
			)
		elif scene_path.ends_with("DeliveryArea.tscn"):
			_check(
				not bool(event_source.call("is_interference_enabled")),
				"Delivery interference waits for an active event"
			)
		instance.queue_free()

	print("ALIEN_INTERFERENCE_TEST|%s" % ["FAIL" if _failed else "PASS"])
	quit(1 if _failed else 0)


func _check(condition : bool, label : String) -> void:
	print("CHECK|%s|%s" % ["PASS" if condition else "FAIL", label])
	_failed = _failed or not condition
