class_name HouseVariant
extends Node3D

## Variação de uma casa modular instanciada no bairro. A planta é a mesma da
## `House01`; o que muda de lote para lote é a tranca da entrada, a luz que
## escapa pelas janelas, as cortinas e quais móveis ficam no lugar.
##
## Mora na raiz da instância, e não em cada nó ajustado, porque só a raiz de uma
## instância guarda sobrescrita quando a cena é empacotada por ferramenta —
## fora do editor o resto volta ao original. Por isso as escolhas viram
## `variant_seed` e são aplicadas uma vez, ao entrar na árvore — antes do
## `_ready` das portas e das luzes, que leem a configuração de baixo para cima.

## Semente das escolhas: mesma semente, mesma casa.
@export var variant_seed: int = 0
## A porta de entrada começa trancada; só morador com chave abre.
@export var entry_locked: bool = false
## Caminho da porta de entrada dentro da casa.
@export var entry_door: NodePath = ^"Estrutura/BatentePorta/PortaEntrada"
## Móveis que podem faltar em parte das casas, sem deixar cômodo vazio.
@export var spare_furniture: Array[StringName] = [
	&"Estante", &"Abajur", &"Planta", &"MesaCentro", &"CadeiraLeste", &"TapeteSala",
]
## Uma casa cheia de luz com sombra dinâmica é o bairro inteiro pagando por
## cinco lâmpadas; a casa da praça, montada à mão, mantém as dela.
@export var interior_shadows: bool = false
@export_range(10.0, 80.0, 1.0) var light_fade_distance: float = 26.0


var _applied: bool = false


func _enter_tree() -> void:
	if _applied:
		return
	_applied = true
	var door: HouseDoor = get_node_or_null(entry_door) as HouseDoor
	if door != null:
		door.starts_locked = entry_locked
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = variant_seed
	for node: Node in find_children("*", "OmniLight3D", true, false):
		var light: OmniLight3D = node as OmniLight3D
		light.shadow_enabled = light.shadow_enabled and interior_shadows
		light.light_energy *= rng.randf_range(0.75, 1.15)
		light.distance_fade_enabled = true
		light.distance_fade_begin = light_fade_distance
		light.distance_fade_length = 8.0
	for node: Node in find_children("Cortina*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = rng.randf() > 0.3
	var furniture: Node3D = get_node_or_null(^"Moveis") as Node3D
	if furniture == null:
		return
	for spare: StringName in spare_furniture:
		var item: Node3D = furniture.get_node_or_null(NodePath(spare)) as Node3D
		if item != null and rng.randf() < 0.3:
			item.visible = false
