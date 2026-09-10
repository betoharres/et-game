extends SceneTree

const InventoryScript : Script = preload("res://scripts/exploration_inventory.gd")
const ScrapScript : Script = preload("res://scripts/spaceship_scraps.gd")
var failures : int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world : Node3D = Node3D.new()
	root.add_child(world)
	current_scene = world
	var player : CharacterBody3D = CharacterBody3D.new()
	world.add_child(player)
	var inventory : Node = InventoryScript.new()
	player.add_child(inventory)
	var small : RigidBody3D = _item(world, 1)
	var medium : RigidBody3D = _item(world, 2)
	var extra : RigidBody3D = _item(world, 1)
	var overflow : RigidBody3D = _item(world, 1)
	_check(inventory.store_item(small, player), "Guarda pequeno")
	_check(inventory.store_item(medium, player), "Guarda médio")
	_check(inventory.used_slots() == 3, "Pequeno + médio = 3 slots")
	_check(not small.visible and small.collision_layer == 0, "Guardado sem visual/colisão")
	_check(not small.is_available_for_abduction(), "Guardado não pode ser entregue nem roubado pelo bot")
	_check(not inventory.store_item(small, player), "Não duplica o mesmo item")
	_check(inventory.store_item(extra, player), "Completa 4 slots")
	_check(not inventory.store_item(overflow, player), "Recusa inventário cheio")
	_check(overflow.get_parent() == world and not overflow.carried, "Recusa preserva objeto no mundo")
	inventory.drop_last(player)
	_check(inventory.used_slots() == 3 and extra.get_parent() == world, "Soltar libera slot")
	_check(extra.visible and extra.collision_layer == 8 and extra.collision_mask == 1, "Soltar restaura visual/colisão")
	_check(extra.begin_abduction(), "Objeto solto pode ser entregue")
	_check(not inventory.store_item(extra, player), "Não coleta durante abdução")
	var large : RigidBody3D = _item(world, 1)
	large.two_handed = true
	_check(not inventory.store_item(large, player), "Grande nunca entra nos slots")
	large.pickup(player)
	_check(large.carried and large.visible, "Grande permanece visível nas mãos")
	large.drop()
	_check(large.is_available_for_abduction(), "Grande solto pode ser entregue")
	inventory.select_slot(2)
	_check(inventory.item_at(2) == medium, "Segundo slot de objeto medio seleciona o mesmo item")
	inventory.drop_selected(player)
	_check(inventory.used_slots() == 1, "Soltar selecionado libera ambos os slots")
	_check(inventory.item_at(0) == small and inventory.item_at(1) == null and inventory.item_at(2) == null, "Soltar preserva posicao dos outros itens")
	inventory.select_slot(0)
	inventory.cycle_slot(-1)
	_check(inventory.selected_slot == 3, "Roda anterior volta ao quarto slot")
	inventory.cycle_slot(1)
	_check(inventory.selected_slot == 0, "Roda seguinte volta ao primeiro slot")
	inventory.select_slot(3)
	inventory.drop_selected(player)
	_check(inventory.used_slots() == 1, "Soltar slot vazio preserva os itens")
	small.free()
	_check(inventory.used_slots() == 0 and inventory.item_at(0) == null, "Remocao externa libera slot")
	inventory.drop_selected(player)
	print("Inventário: %d falhas" % failures)
	quit(1 if failures else 0)


func _item(world : Node3D, cost : int) -> RigidBody3D:
	var item : RigidBody3D = ScrapScript.new()
	item.slot_cost = cost
	item.collision_layer = 8
	item.collision_mask = 1
	world.add_child(item)
	item.add_to_group("pickup_items")
	return item


func _check(condition : bool, message : String) -> void:
	if not condition:
		failures += 1
		push_error(message)
