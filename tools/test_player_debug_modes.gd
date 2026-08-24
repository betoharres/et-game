extends SceneTree

var _failed : bool = false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed : PackedScene = load("res://scenes/Player.tscn") as PackedScene
	var player : Node = packed.instantiate()
	root.add_child(player)
	await process_frame
	player.set_physics_process(false)
	var debug_menu : Node = (
		load("res://scenes/DebugMenu.tscn") as PackedScene
	).instantiate()
	root.add_child(debug_menu)
	await process_frame
	var god_toggle : CheckButton = debug_menu.get_node(
		"Overlay/CenterContainer/MenuPanel/MarginContainer/MainPanel/GodModeToggle"
	) as CheckButton
	var flight_toggle : CheckButton = debug_menu.get_node(
		"Overlay/CenterContainer/MenuPanel/MarginContainer/MainPanel/FlightModeToggle"
	) as CheckButton

	player.set("health", 42.0)
	player.set("stamina", 3.0)
	god_toggle.button_pressed = true
	_check(bool(player.call("is_debug_god_mode_enabled")), "God mode enables")
	_check(
		is_equal_approx(
			float(player.call("get_health")),
			float(player.call("get_max_health"))
		),
		"God mode restores health"
	)
	_check(
		is_equal_approx(
			float(player.call("get_stamina")),
			float(player.call("get_max_stamina"))
		),
		"God mode restores stamina"
	)

	player.call("take_damage", 999.0, Vector3.FORWARD, 5.0)
	_check(
		is_equal_approx(
			float(player.call("get_health")),
			float(player.call("get_max_health"))
		),
		"God mode blocks lethal damage"
	)
	_check(
		is_equal_approx(
			float(player.call("_get_movement_speed")),
			float(player.get("speed")) * 5.0
		),
		"God mode multiplies movement speed by five"
	)

	flight_toggle.button_pressed = true
	var body : CharacterBody3D = player as CharacterBody3D
	_check(bool(player.call("is_debug_flight_enabled")), "Flight mode enables")
	_check(
		body.motion_mode == CharacterBody3D.MOTION_MODE_FLOATING,
		"Flight mode disables grounded motion"
	)
	_check(
		bool(player.call("is_debug_god_mode_enabled"))
		and bool(player.call("is_debug_flight_enabled")),
		"God and flight modes coexist"
	)
	var starting_height : float = body.global_position.y
	Input.action_press("jump")
	player.set_physics_process(true)
	for _frame : int in 5:
		await physics_frame
	player.set_physics_process(false)
	Input.action_release("jump")
	_check(
		body.global_position.y > starting_height + 0.01,
		"Flight mode moves upward without gravity"
	)

	player.call("set_debug_god_mode_enabled", false)
	_check(
		bool(player.call("is_debug_flight_enabled")),
		"Disabling god mode keeps flight active"
	)
	player.call("set_debug_flight_enabled", false)
	_check(
		body.motion_mode == CharacterBody3D.MOTION_MODE_GROUNDED,
		"Disabling flight restores grounded motion"
	)

	player.call("take_damage", 10.0)
	_check(
		is_equal_approx(
			float(player.call("get_health")),
			float(player.call("get_max_health")) - 10.0
		),
		"Damage returns after god mode is disabled"
	)

	print("PLAYER_DEBUG_MODES_TEST|%s" % ["FAIL" if _failed else "PASS"])
	quit(1 if _failed else 0)


func _check(condition : bool, label : String) -> void:
	print("CHECK|%s|%s" % ["PASS" if condition else "FAIL", label])
	_failed = _failed or not condition
