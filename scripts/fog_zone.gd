class_name FogZone
extends Node3D

## Marcador leve que reforca a nevoa rasteira em uma area (milharal, estrada,
## campo aberto). Nao tem fisica nem processamento proprio: o GroundFogLayer
## coleta as zonas mais proximas da camera e as envia para o shader.

@export var enabled : bool = true
@export_range(2.0, 120.0, 0.5) var radius : float = 18.0
@export_range(0.0, 1.0, 0.01) var strength : float = 0.55


func get_fog_radius() -> float:
	return radius


func get_fog_strength() -> float:
	if not enabled or not is_visible_in_tree():
		return 0.0
	return strength


func set_fog_enabled(value : bool) -> void:
	enabled = value
