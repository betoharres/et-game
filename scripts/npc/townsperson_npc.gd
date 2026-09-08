class_name TownspersonNPC
extends NPCActor

## Base do morador da zona urbana: caminha entre casa e comércio e foge ao
## ver o ET. "Procurar ajuda" fica documentado como extensão futura — hoje
## não há um destino de ajuda definido no jogo para apontar sem inventar um.


func _ready() -> void:
	reaction_mode = ReactionMode.FLEE
	can_socialize = false
	use_flashlight = false
	super()
