extends "res://scripts/reactive_crop.gd"

## Talhao de trigo: verga menos que o milho e balanca mais com o vento.
## A reatividade mora em `reactive_crop.gd`.


func _init() -> void:
	bend_strength = 20.0
	wind_strength = 2.0
