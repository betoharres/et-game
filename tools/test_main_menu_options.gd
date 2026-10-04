extends SceneTree

var failures : int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition : bool, message : String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Este teste exige um driver gráfico para verificar janela e VSync.")
		quit(1)
		return
	root.show()
	var menu_scene : PackedScene = load("res://scenes/Menu/main_menu.tscn") as PackedScene
	var menu : Control = menu_scene.instantiate() as Control
	root.add_child(menu)
	await create_timer(0.25).timeout
	await create_timer(0.25).timeout
	menu.call("_on_options_pressed")
	var resolution : OptionButton = menu.get("resolution_button") as OptionButton
	var vsync : CheckBox = menu.get("vsync_check_box") as CheckBox
	_check(vsync.button_pressed == (DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED), "VSync inicial não corresponde ao driver.")
	var initial_vsync : int = DisplayServer.window_get_vsync_mode()
	menu.call("update_vsync_check_box")
	_check(DisplayServer.window_get_vsync_mode() == initial_vsync, "Atualizar o checkbox alterou o VSync.")
	root.content_scale_size = Vector2i(1600, 900)
	menu.call("_on_window_mode_pressed")
	await create_timer(0.25).timeout
	resolution.item_selected.emit(0)
	await create_timer(0.25).timeout
	await create_timer(0.25).timeout
	_check(DisplayServer.window_get_size() == Vector2i(1280, 720), "Resolução não redimensionou a janela.")
	_check(root.content_scale_size == Vector2i(1280, 720), "Resolução não alterou o viewport.")
	menu.call("_on_window_mode_pressed")
	await create_timer(0.25).timeout
	await create_timer(0.25).timeout
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Não entrou em tela cheia.")
	resolution.item_selected.emit(1)
	await create_timer(0.25).timeout
	await create_timer(0.25).timeout
	_check(root.content_scale_size == Vector2i(1600, 900), "Resolução em tela cheia não alterou a renderização.")
	_check(root.get_visible_rect().size == Vector2(1600, 900), "Viewport real não usa a resolução selecionada.")
	menu.call("_on_window_mode_pressed")
	await create_timer(0.25).timeout
	await create_timer(0.25).timeout
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Não voltou ao modo janela.")
	_check(DisplayServer.window_get_size() == Vector2i(1600, 900), "Modo janela não recuperou a resolução escolhida.")
	vsync.toggled.emit(true)
	await create_timer(0.25).timeout
	_check(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED, "VSync não foi habilitado.")
	vsync.toggled.emit(false)
	await create_timer(0.25).timeout
	_check(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, "VSync não foi desligado.")
	menu.queue_free()
	await create_timer(0.25).timeout
	menu = menu_scene.instantiate() as Control
	root.add_child(menu)
	await create_timer(0.25).timeout
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Reabrir o menu sobrescreveu o modo janela.")
	resolution = menu.get("resolution_button") as OptionButton
	_check(menu.call("get_resolution", resolution.selected) == Vector2i(1600, 900), "Reabrir o menu perdeu a resolução selecionada.")
	print("Menu options: %d failure(s)." % failures)
	quit(0 if failures == 0 else 1)
