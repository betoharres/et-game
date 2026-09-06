extends "res://scripts/reactive_crop.gd"

## Milharal: um talhao de pes de milho, alto o bastante para o ET se esconder.
## Toda a reatividade mora em `reactive_crop.gd`; aqui ficam so os valores que
## diferem das outras plantacoes.


func _init() -> void:
	bend_strength = 25.0
	wind_strength = 1.0
