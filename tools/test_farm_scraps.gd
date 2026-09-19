extends SceneTree

const INVENTORY_SCRIPT : Script = preload("res://scripts/exploration_inventory.gd")
const SPIDER_BOT_SCRIPT : Script = preload("res://scripts/spider_bot/spider_bot.gd")
const LEGACY_SCRAP_SCRIPT : Script = preload("res://scripts/spaceship_scraps.gd")
const SCENE_NAMES : Array[String] = [
	"SoccerBall", "Hoe", "Radio", "RemoteControl", "StuffedMonkey", "Toothpaste",
	"Glasses", "Bottle", "BaseballBat", "Telephone", "Bucket", "WateringCan",
]

var failures : int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world : Node3D = Node3D.new()
	root.add_child(world)
	current_scene = world
	var player : CharacterBody3D = CharacterBody3D.new()
	world.add_child(player)
	var carry_socket : Marker3D = Marker3D.new()
	carry_socket.name = "CarrySocket"
	carry_socket.position = Vector3(0.0, 1.1, 0.65)
	player.add_child(carry_socket)
	var inventory : Node = INVENTORY_SCRIPT.new()
	player.add_child(inventory)
	# O filtro é independente da árvore e não precisa do rig de animação do bot.
	var bot : Node3D = SPIDER_BOT_SCRIPT.new()
	for scene_name : String in SCENE_NAMES:
		_test_item(scene_name, world, player, inventory, bot)
	_test_repeated_objects(world, player, inventory)
	var legacy_scrap : RigidBody3D = LEGACY_SCRAP_SCRIPT.new()
	world.add_child(legacy_scrap)
	_check(bool(bot.call("_is_valid_item", legacy_scrap)), "Bot continua aceitando os destroços anteriores")
	legacy_scrap.free()
	bot.free()
	world.free()
	print("Scraps da fazenda: %d tipos; %d falhas" % [SCENE_NAMES.size(), failures])
	quit(1 if failures > 0 else 0)


func _test_item(scene_name : String, world : Node3D, player : Node3D, inventory : Node, bot : Node3D) -> void:
	var packed : PackedScene = load("res://scenes/Farm/Scraps/%s.tscn" % scene_name) as PackedScene
	_check(packed != null, "%s: cena carrega" % scene_name)
	if packed == null:
		return
	var item : RigidBody3D = packed.instantiate() as RigidBody3D
	_check(item != null, "%s: objeto físico instanciável" % scene_name)
	if item == null:
		return
	world.add_child(item)
	_check_geometry(item, scene_name)
	_check(item.is_in_group("pickup_items") and item.is_in_group("farm_scraps"), "%s: visível aos sistemas de coleta e dinheiro" % scene_name)
	_check(not bool(bot.call("_is_valid_item", item)), "%s: bot não recolhe objeto disponível" % scene_name)
	var original_layer : int = item.collision_layer
	var original_mask : int = item.collision_mask
	if bool(item.get("two_handed")):
		_check(not bool(inventory.call("store_item", item, player)), "%s: ferramenta comprida não entra no inventário" % scene_name)
		item.call("pickup", player)
		_check(item.visible and item.get_parent() == player, "%s: permanece visível nas mãos" % scene_name)
		_check(item.position.is_equal_approx((player.get_node("CarrySocket") as Marker3D).position), "%s: usa o encaixe de transporte" % scene_name)
	else:
		_check(bool(inventory.call("store_item", item, player)), "%s: entra no inventário" % scene_name)
		_check(not item.visible and item.get_parent() == player, "%s: objeto guardado sai do cenário" % scene_name)
		_check(int(inventory.call("used_slots")) > 0, "%s: ocupa espaço no inventário" % scene_name)
		_check(not bool(inventory.call("store_item", item, player)), "%s: guardar novamente não duplica" % scene_name)
	_check(item.freeze and item.collision_layer == 0 and item.collision_mask == 0, "%s: transporte suspende a física" % scene_name)
	_check(not bool(item.call("begin_abduction")), "%s: coleta na mochila/mãos não entrega à distância" % scene_name)
	if bool(item.get("two_handed")):
		item.call("drop")
	else:
		inventory.call("select_slot", 0)
		inventory.call("drop_selected", player)
	_check(item.get_parent() == world and item.visible and not item.freeze, "%s: soltar restaura o objeto no mundo" % scene_name)
	_check(item.collision_layer == original_layer and item.collision_mask == original_mask, "%s: colisão restaurada após soltar" % scene_name)
	_check(int(inventory.call("used_slots")) == 0, "%s: soltar libera todos os slots" % scene_name)
	_check(not bool(bot.call("_is_valid_item", item)), "%s: bot também ignora o objeto devolvido ao chão" % scene_name)
	var dropped_position : Vector3 = item.global_position
	item.call("drop")
	_check(item.global_position.is_equal_approx(dropped_position), "%s: soltar duas vezes preserva o objeto" % scene_name)
	_check(bool(item.call("begin_abduction")), "%s: objeto devolvido pode ser entregue" % scene_name)
	_check(not item.is_in_group("pickup_items") and item.freeze, "%s: entrega reserva o objeto" % scene_name)
	_check(not bool(item.call("begin_abduction")), "%s: entrega não pode começar duas vezes" % scene_name)
	_check(not bool(inventory.call("store_item", item, player)), "%s: não volta ao inventário durante entrega" % scene_name)
	item.call("pickup", player)
	_check(item.get_parent() == world and not bool(item.get("carried")), "%s: não volta às mãos durante entrega" % scene_name)
	item.free()


func _check_geometry(item : RigidBody3D, label : String) -> void:
	var combined : AABB = AABB()
	var has_mesh : bool = false
	for child : Node in item.find_children("*", "MeshInstance3D", true, false):
		var visual : MeshInstance3D = child as MeshInstance3D
		_check(visual.mesh != null, "%s: malha presente em %s" % [label, visual.name])
		if visual.mesh == null:
			continue
		var local_transform : Transform3D = item.global_transform.affine_inverse() * visual.global_transform
		var bounds : AABB = local_transform * visual.get_aabb()
		combined = combined.merge(bounds) if has_mesh else bounds
		has_mesh = true
		for surface : int in range(visual.mesh.get_surface_count()):
			_check(visual.get_active_material(surface) != null, "%s: material da superfície %d de %s" % [label, surface, visual.name])
	_check(has_mesh and combined.size.is_finite(), "%s: geometria visível válida" % label)
	var longest_axis : float = maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
	_check(longest_axis >= 0.12 and longest_axis <= 1.25, "%s: cabe nas mãos de um humano (%s m)" % [label, combined.size])
	_check(combined.position.y >= -0.02 and combined.position.y <= 0.03, "%s: base da malha apoia perto da origem (%s)" % [label, combined.position])
	var has_collision : bool = false
	for child : Node in item.find_children("*", "CollisionShape3D", true, false):
		var collider : CollisionShape3D = child as CollisionShape3D
		if collider.shape != null and not collider.disabled:
			has_collision = true
	_check(has_collision and item.collision_layer != 0 and item.collision_mask != 0, "%s: pode pousar em superfícies e ser detectado" % label)


func _test_repeated_objects(world : Node3D, player : Node3D, inventory : Node) -> void:
	var packed : PackedScene = load("res://scenes/Farm/Scraps/SoccerBall.tscn") as PackedScene
	var first : RigidBody3D = packed.instantiate() as RigidBody3D
	var second : RigidBody3D = packed.instantiate() as RigidBody3D
	world.add_child(first)
	world.add_child(second)
	_check(bool(inventory.call("store_item", first, player)), "Primeira bola cabe no inventário")
	_check(bool(inventory.call("store_item", second, player)), "Segundo exemplar do mesmo tipo é coletável independentemente")
	_check(int(inventory.call("used_slots")) == 4, "Dois objetos volumosos preenchem os quatro slots iniciais")
	inventory.call("select_slot", 1)
	inventory.call("drop_selected", player)
	_check(first.get_parent() == world and second.get_parent() == player, "Soltar um exemplar não solta o outro")
	_check(int(inventory.call("used_slots")) == 2, "Soltar libera os dois slots do objeto selecionado")
	first.free()
	second.free()
	_check(int(inventory.call("used_slots")) == 0, "Remover objeto guardado limpa suas referências")


func _check(condition : bool, message : String) -> void:
	if not condition:
		failures += 1
		push_error(message)
