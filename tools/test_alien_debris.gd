extends SceneTree

const Inventory : Script = preload("res://scripts/exploration_inventory.gd")
const DEBRIS : PackedScene = preload("res://scenes/Items/AlienDebris.tscn")
const LOCATOR : PackedScene = preload("res://scenes/Items/DebrisLocator.tscn")
var failures : int = 0


class TestCharacter extends Node3D:
	var health : float = 100.0

	func get_health() -> float:
		return health


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world : Node3D = Node3D.new()
	root.add_child(world)
	current_scene = world
	var player : TestCharacter = TestCharacter.new()
	world.add_child(player)
	var inventory : Node = Inventory.new()
	inventory.name = "ExplorationInventory"
	player.add_child(inventory)
	var locator : AlienTechnologyItem = LOCATOR.instantiate() as AlienTechnologyItem
	world.add_child(locator)
	_check(DebrisLocator.scan(player)["strength"] == 0, "Localizador não detecta a si mesmo")
	_check(inventory.store_item(locator, player), "Coleta localizador")
	_check(inventory.used_slots() == 1, "Equipamento ocupa um slot")
	var near : AlienDebris = DEBRIS.instantiate() as AlienDebris
	var far : AlienDebris = DEBRIS.instantiate() as AlienDebris
	world.add_child(near)
	world.add_child(far)
	near.position = Vector3(0, 0, 15)
	far.position = Vector3(0, 0, -200)
	var reading : Dictionary = DebrisLocator.scan(player)
	_check(reading["strength"] == 4 and reading["direction"] == "↑", "Mais próximo à frente, sinal forte")
	player.rotation.y = PI / 2.0
	_check(DebrisLocator.scan(player)["direction"] == "→", "Direção acompanha orientação do personagem")
	player.rotation.y = 0.0
	_check(inventory.store_item(near, player), "Coleta destroço")
	_check(near.state == AlienTechnologyItem.State.INVENTORY and not near.visible and near.collision_layer == 0, "Sai do mundo visível e da colisão")
	reading = DebrisLocator.scan(player)
	_check(reading["strength"] == 1 and reading["direction"] == "↓", "Ignora coletado e troca automaticamente para distante")
	_check(not inventory.store_item(near, player), "Sem coleta duplicada")
	inventory.select_slot(1)
	inventory.drop_selected(player)
	_check(near.state == AlienTechnologyItem.State.WORLD and near.visible and near.collision_layer == 8, "Soltar restaura WORLD, aparência e colisão")
	_check(DebrisLocator.scan(player)["strength"] == 5, "Destroço solto volta ao detector")
	_check(near.begin_abduction(), "Entrega mantém contrato legado")
	_check(DebrisLocator.scan(player)["strength"] == 1, "Ignora destroço em abdução")
	for distance : float in [150.0, 90.0, 40.0, 15.0, 4.0]:
		far.position = Vector3(0, 0, distance)
		var expected : int = [150.0, 90.0, 40.0, 15.0, 4.0].find(distance) + 1
		_check(DebrisLocator.scan(player)["strength"] == expected, "Intensidade em %s" % distance)
	var hud : Control = preload("res://scenes/DebrisLocatorHUD.tscn").instantiate() as Control
	hud.character = player
	world.add_child(hud)
	hud.call("_process", 0.4)
	_check(not hud.visible, "Localizador guardado fica inativo quando outro slot está selecionado")
	inventory.select_slot(0)
	hud.call("_process", 0.4)
	_check(hud.visible and (hud.get_node("Signal") as Label).text == "SIGNAL:", "Selecionar equipamento ativa detector")
	_check((hud.get_node("Hint") as Label).text.contains("Procure ao redor"), "Saturação orienta busca visual")
	player.health = 0.0
	hud.call("_process", 0.01)
	_check(not hud.visible, "Morte desativa detector")
	player.health = 100.0
	hud.call("_process", 0.01)
	_check(hud.visible, "Equipamento volta a funcionar em personagem vivo")
	player.hide()
	hud.call("_process", 0.01)
	_check(not hud.visible, "Personagem oculto no veículo não mantém detector")
	player.show()
	hud.call("_process", 0.01)
	paused = true
	far.position = Vector3(0, 0, 200)
	hud.call("_process", 1.0)
	_check(hud.get("_strength") == 5, "Pausa congela leitura")
	paused = false
	hud.call("_process", 0.4)
	_check(hud.get("_strength") == 1, "Retomar atualiza leitura")
	inventory.drop_selected(player)
	hud.call("_process", 0.01)
	_check(not hud.visible and inventory.used_slots() == 0, "Soltar equipamento desliga HUD e libera slot")
	_check(inventory.store_item(locator, player), "Pode recuperar equipamento")
	far.queue_free()
	_check(DebrisLocator.scan(player)["strength"] == 0, "Sem alvo após remoção do último WORLD")
	hud.call("_process", 0.4)
	_check((hud.get_node("Status") as Label).text == "SEM SINAL", "Feedback sem sinal")
	_test_detector(world, player)
	player.queue_free()
	await process_frame
	hud.call("_process", 0.01)
	_check(not hud.visible, "Remoção do personagem limpa HUD")
	var district : Node3D = (load("res://scenes/CountryTown/Districts/AlienDebrisTest.tscn") as PackedScene).instantiate() as Node3D
	_check(district.get_child_count() == 9, "Mapa contém oito destroços e um equipamento")
	district.free()
	world.free()
	print("AlienDebris / Debris Locator: %d falhas" % failures)
	quit(1 if failures else 0)


func _test_detector(world : Node3D, player : Node3D) -> void:
	var target : AlienDebris = DEBRIS.instantiate() as AlienDebris
	world.add_child(target)
	target.freeze = true
	var detector : DebrisLocator = DebrisLocator.new()
	for sector : int in range(8):
		var angle : float = float(sector) * PI / 4.0
		target.position = Vector3(-sin(angle), 0, cos(angle)) * 40.0
		_check(DebrisLocator.scan(player)["sector"] == sector, "Direção relativa no setor %d" % sector)
	player.rotation.z = PI / 2.0
	target.position = player.to_global(Vector3(-40, 0, 0))
	_check(DebrisLocator.scan(player)["sector"] == 2, "Direção respeita up local em outra superfície")
	player.rotation = Vector3.ZERO
	for angle : float in [20.0, 24.0, 30.0]:
		target.position = Vector3(-sin(deg_to_rad(angle)), 0, cos(deg_to_rad(angle))) * 40.0
		_check(detector.sample(player)["sector"] == (1 if angle == 30.0 else 0), "Estabilidade angular em %s graus" % angle)
	for angle : float in [179.0, -179.0]:
		target.position = Vector3(-sin(deg_to_rad(angle)), 0, cos(deg_to_rad(angle))) * 40.0
		_check(detector.sample(player)["sector"] == 4, "Continuidade angular atrás em %s graus" % angle)
	detector.reset()
	var distances : Array[float] = [61.0, 59.0, 54.0, 61.0, 65.0]
	var strengths : Array[int] = [2, 2, 3, 3, 2]
	for index : int in range(distances.size()):
		target.position = Vector3(0, 0, distances[index])
		_check(detector.sample(player)["strength"] == strengths[index], "Estabilidade de intensidade em %s" % distances[index])
	var closer : AlienDebris = DEBRIS.instantiate() as AlienDebris
	world.add_child(closer)
	closer.position = Vector3(0, 0, -15)
	var reading : Dictionary = detector.sample(player)
	_check(reading["sector"] == 4 and reading["strength"] == 4, "Novo destroço mais próximo assume sinal imediatamente")
	closer.pickup(player)
	_check(closer.state == AlienTechnologyItem.State.CARRIED and detector.sample(player)["sector"] == 0, "Ignora destroço carregado nas mãos")
	closer.queue_free()
	target.position = Vector3(0, 50, 0)
	reading = detector.sample(player)
	_check(reading["sector"] == -1 and not reading["nearby"], "Alvo acima não produz rumo horizontal falso")
	target.position = Vector3.ZERO
	reading = detector.sample(player)
	_check(reading["strength"] == 5 and reading["direction"] == "" and reading["nearby"], "Sobreposição satura sem fornecer rumo exato")
	_check(not reading.has("distance") and not reading.has("position") and not reading.has("target"), "HUD recebe apenas informação aproximada")
	target.position = Vector3(0, 0, 8.2)
	_check(detector.sample(player)["nearby"], "Saturação estável na borda da área de busca")
	target.position = Vector3(0, 0, 9)
	_check(not detector.sample(player)["nearby"], "Direção retorna ao sair da área de busca")
	target.queue_free()
	_check(detector.sample(player)["strength"] == 0, "Remoção limpa leitura persistente")
	_check(DebrisLocator.scan(null)["strength"] == 0, "Personagem ausente não causa erro")
	var detached : Node3D = Node3D.new()
	_check(detector.sample(detached)["strength"] == 0, "Personagem fora da árvore não causa erro")
	detached.free()


func _check(condition : bool, message : String) -> void:
	if not condition:
		failures += 1
		push_error(message)
