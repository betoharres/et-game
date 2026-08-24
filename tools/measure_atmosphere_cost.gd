extends SceneTree

## Mede FPS e tempo de render por preset de atmosfera, rodando world.tscn.
## Use antes e depois de mexer na nevoa para conferir o custo real:
##   godot --path . --script res://tools/measure_atmosphere_cost.gd

const WARMUP_SECONDS : float = 3.0
const SAMPLE_SECONDS : float = 5.0

## A nave gira e muda quantos feixes aparecem em tela, entao a referencia sem
## nevoa e medida no inicio e no fim para revelar a deriva entre as amostras.
const CASES : Array[Dictionary] = [
	{"name": "sem_nevoa_(inicio)", "preset": 2, "alien": 0.0, "fog": false},
	{"name": "low", "preset": 0, "alien": 0.0, "fog": true},
	{"name": "medium", "preset": 1, "alien": 0.0, "fog": true},
	{"name": "high", "preset": 2, "alien": 0.0, "fog": true},
	{"name": "high_alien", "preset": 2, "alien": 1.0, "fog": true},
	{"name": "sem_nevoa_(fim)", "preset": 2, "alien": 0.0, "fog": false},
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	change_scene_to_file("res://scenes/world.tscn")
	await create_timer(9.0).timeout

	var environment : Node = get_first_node_in_group("debug_environment_lighting")
	if environment == null:
		print("FPS|FAIL|NightEnvironment nao encontrado")
		quit(1)
		return

	for case : Dictionary in CASES:
		environment.call("set_quality_preset", int(case["preset"]))
		environment.call("set_alien_fog_intensity", float(case["alien"]))
		environment.call("set_debug_fog_enabled", bool(case["fog"]))
		await create_timer(WARMUP_SECONDS).timeout

		var viewport_rid : RID = get_root().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
		var frames : int = 0
		var elapsed : float = 0.0
		var gpu_total : float = 0.0
		var cpu_total : float = 0.0
		while elapsed < SAMPLE_SECONDS:
			await process_frame
			elapsed += get_root().get_process_delta_time()
			frames += 1
			gpu_total += RenderingServer.viewport_get_measured_render_time_gpu(
				viewport_rid
			)
			cpu_total += RenderingServer.viewport_get_measured_render_time_cpu(
				viewport_rid
			)
		print("FPS|%s|fps %.1f|gpu %.2f ms|cpu %.2f ms" % [
			case["name"],
			float(frames) / elapsed,
			gpu_total / float(frames),
			cpu_total / float(frames),
		])

	quit(0)
