class_name PoliceNPC
extends NPCActor

## Base do policial a pé: patrulha perto da praça e persegue o ET ao vê-lo,
## como o fazendeiro. Ponto de extensão documentado (ainda não conectado):
## `PhotoAlertSystem.police_response_requested` já é emitido nos níveis
## certos, mas hoje não carrega a posição do ET — plugar a reação da viatura/
## polícia a pé a esse sinal exige antes estender `photo_alert_system.gd` com
## essa posição, o que é trabalho futuro fora deste sistema de IA.


func _ready() -> void:
	reaction_mode = ReactionMode.CHASE
	can_socialize = false
	use_flashlight = false
	super()
