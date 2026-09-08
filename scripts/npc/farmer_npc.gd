class_name FarmerNPC
extends NPCActor

## Fazendeiro da zona rural: patrulha ou trabalha parado (via `patrol_points`),
## conversa ocasionalmente com outro fazendeiro, usa lanterna (o mapa é
## permanentemente noturno) e persegue o ET ao vê-lo. Toda a lógica de
## decisão vive na `NPCBehaviorTree.tscn` compartilhada; este script só fixa
## os parâmetros padrão do papel de fazendeiro.


func _ready() -> void:
	can_socialize = true
	social_group_name = &"farmers"
	reaction_mode = ReactionMode.CHASE
	use_flashlight = true
	super()
