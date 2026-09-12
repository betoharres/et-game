extends SceneTree

const FLOW = preload("res://scripts/levels/mission_flow.gd")
var failures : int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition : bool, message : String) -> void:
	print("PASS: " if condition else "FAIL: ", message)
	if not condition:
		failures += 1


func _snapshot(label : String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path : String = OS.get_environment("TEMP").path_join("et_mission_" + label + ".png")
	root.get_texture().get_image().save_png(path)
	print("Screenshot: ", path)


func _run() -> void:
	var orbit : Node3D = (load("res://scenes/Space/Orbit.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(orbit)
	current_scene = orbit
	await create_timer(0.5).timeout
	var player : CharacterBody3D = orbit.get_node("CharacterBody3D") as CharacterBody3D
	var npc : MissionGiverNPC = orbit.get_node("AlienShip/MissionGiver") as MissionGiverNPC
	var dialogue : MissionDialogueUI = orbit.get_node("MissionDialogue") as MissionDialogueUI
	npc.activated.emit()
	for index : int in range(3):
		dialogue.continue_button.pressed.emit()
	dialogue.decline_button.pressed.emit()
	_check(not bool(orbit.get("_rescue_accepted")) and npc._marker.visible, "Recusar mantém a oferta")
	npc.activated.emit()
	for index : int in range(3):
		dialogue.continue_button.pressed.emit()
	dialogue.accept_button.pressed.emit()
	_check(dialogue.visible and dialogue.accept_button.text == "Ir agora", "Aceitar abre escolha de partida")
	_check(not bool(orbit.get("_traveling")), "Aceitar não inicia viagem")
	_check(not npc._marker.visible and npc._talking, "NPC conversa sem marcador")
	await _snapshot("choice")
	dialogue.decline_button.pressed.emit()
	_check(not bool(player.get("_movement_locked")) and bool(orbit.get("_rescue_accepted")), "Depois libera jogador e mantém missão")
	_check(orbit.get("_pending_level") == null, "Depois não deixa destino armado")
	var farm : LevelDefinition = load("res://scenes/Space/Levels/level_farm.tres") as LevelDefinition
	orbit.call("_on_level_chosen", farm)
	_check(orbit.get("_pending_level") == farm, "Terminal preserva outras fases")
	var rescue : LevelDefinition = load("res://scenes/Space/Levels/level_country_town.tres") as LevelDefinition
	orbit.call("_on_level_chosen", rescue)
	_check(dialogue.visible and dialogue.accept_button.text == "Ir agora", "Terminal retoma missão aceita")
	_check(orbit.get("_pending_level") == null, "Retomar limpa transporte anterior")
	dialogue.decline_button.pressed.emit()
	npc.activated.emit()
	_check(dialogue.visible and dialogue.accept_button.text == "Ir agora", "NPC retoma sem repetir briefing")
	dialogue.accept_button.pressed.emit()
	await create_timer(1.2).timeout
	var saucer : Node3D = orbit.get("_mission_transport") as Node3D
	_check(saucer != null and not saucer is AlienShip, "Transporte é a Saucer")
	_check(saucer.to_local(player.global_position).distance_to(Vector3(0, 0.1, 0.65)) < 0.1,
		"Jogador embarca na cabine: %s" % player.global_position)
	_check(FLOW.arrived_from_orbit and FLOW.arrival_by_saucer, "Estado de chegada preparado")
	await _snapshot("cabin")
	await create_timer(2.0).timeout
	_check(saucer.to_local(player.global_position).distance_to(Vector3(0, 0.1, 0.65)) < 0.1,
		"Passageiro acompanha alinhamento e aceleração")
	_check(orbit.get_node("AlienShip").position.is_equal_approx(Vector3.ZERO), "Nave grande permanece na órbita")
	var camera : Camera3D = player.camera_pivot.camera
	var earth_direction : Vector3 = (orbit.get_node("Earth").global_position - camera.global_position).normalized()
	_check((-camera.global_basis.z).dot(earth_direction) > 0.8, "Câmera enquadra a Terra durante a aproximação")
	await _snapshot("approach")
	var timeout : float = 40.0
	while current_scene == orbit and timeout > 0.0:
		await create_timer(0.25).timeout
		timeout -= 0.25
	_check(is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/CountryTown/CountryTown.tscn", "Warp chega ao Country Town")
	if current_scene != null and current_scene.scene_file_path == "res://scenes/CountryTown/CountryTown.tscn":
		await create_timer(0.3).timeout
		_check(not FLOW.arrival_by_saucer and not FLOW.arrived_from_orbit, "Destino consome estado de viagem")
		var arrival : Node = current_scene.get_node_or_null("MissionSaucer")
		_check(arrival != null, "Mesma Saucer aparece na chegada")
		var arrived_player : CharacterBody3D = current_scene.get_node("Player") as CharacterBody3D
		_check(
			not bool(arrived_player.get("_movement_locked")),
			"ET anda livre dentro da cabine antes de acionar o console"
		)
		if arrival != null:
			# Simula o clique no console em vez de esperar o ET andar ate o
			# gatilho fisico -- mesmo padrao usado acima para o MissionGiver.
			arrival.get_node("Cabin/Console").activated.emit()
		await create_timer(7.0).timeout
		_check(not bool(arrived_player.get("_movement_locked")), "Descida devolve controle")
		await _snapshot("arrival")
	print("Mission departure failures: ", failures)
	current_scene.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
