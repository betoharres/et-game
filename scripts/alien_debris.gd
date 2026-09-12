class_name AlienDebris
extends "res://scripts/alien_technology_item.gd"

## Continua disponível por padrão: quem quiser um destroço só revelado depois
## de um objetivo (ver scripts/country_town.gd) chama set_discovered(false) na
## hora de montar a cena, em vez de mudar esse valor default.
var _discovered : bool = true
var _hidden_collision_layer : int = 0
var _hidden_collision_mask : int = 0


func _ready() -> void:
	super._ready()
	add_to_group("alien_debris")


func set_discovered(discovered : bool) -> void:
	if discovered == _discovered:
		return
	_discovered = discovered
	visible = discovered
	if discovered:
		collision_layer = _hidden_collision_layer
		collision_mask = _hidden_collision_mask
	else:
		_hidden_collision_layer = collision_layer
		_hidden_collision_mask = collision_mask
		collision_layer = 0
		collision_mask = 0


func is_available_for_abduction() -> bool:
	return _discovered and super.is_available_for_abduction()
