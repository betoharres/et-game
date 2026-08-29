class_name ConsoleButton
extends Node3D

## Console interativo reutilizavel. Emite `activated` na acao `interact` quando
## um personagem esta perto.
##
## O aviso de que da para interagir e a propria luz do painel, que acende
## quando alguem chega perto e pulsa enquanto pode ser acionado -- nada de
## rotulo flutuante sobre o objeto.
##
## Mesmo contrato do pad de descida da nave: so responde a corpos do grupo
## `characters` e le a acao do Input Map, nunca uma tecla fixa.

signal activated

@export_color_no_alpha var accent_color : Color = Color(0.42, 0.92, 1.0)

@export_group("Panel Light")
@export_range(0.0, 8.0, 0.1) var idle_light_energy : float = 0.9
@export_range(0.0, 12.0, 0.1) var active_light_energy : float = 2.8
@export_range(0.5, 20.0, 0.5) var light_response : float = 6.0
## Quanto a luz sobe e desce sobre active_light_energy enquanto o console pode
## ser acionado. E o que separa "aceso" de "aceso e esperando voce".
@export_range(0.0, 4.0, 0.05) var active_pulse_amount : float = 0.55
@export_range(0.1, 6.0, 0.05) var active_pulse_frequency : float = 1.6

var _characters_nearby : Array[CharacterBody3D] = []
var _armed : bool = true
var _pulse_phase : float = 0.0

@onready var trigger : Area3D = $Trigger
@onready var panel_light : OmniLight3D = $PanelLight


func _ready() -> void:
	panel_light.light_color = accent_color
	panel_light.light_energy = idle_light_energy
	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)


func _process(delta : float) -> void:
	_forget_freed_characters()
	var character_near : bool = _armed and not _characters_nearby.is_empty()

	var target_energy : float = idle_light_energy
	if character_near:
		_pulse_phase += delta * active_pulse_frequency * TAU
		target_energy = active_light_energy + sin(_pulse_phase) * active_pulse_amount
	else:
		_pulse_phase = 0.0

	panel_light.light_energy = move_toward(
		panel_light.light_energy,
		maxf(target_energy, 0.0),
		light_response * delta
	)

	if character_near and Input.is_action_just_pressed("interact"):
		# Desarma na hora: enquanto a acao do console roda (uma troca de cena,
		# por exemplo) um segundo toque nao deve disparar nada.
		set_armed(false)
		activated.emit()


## Devolve o console ao estado interativo. Serve para quem cancela a acao.
func set_armed(armed : bool) -> void:
	_armed = armed


func _on_body_entered(body : Node3D) -> void:
	var character : CharacterBody3D = body as CharacterBody3D
	if character == null or not character.is_in_group("characters"):
		return
	if not _characters_nearby.has(character):
		_characters_nearby.append(character)


func _on_body_exited(body : Node3D) -> void:
	var character : CharacterBody3D = body as CharacterBody3D
	if character != null:
		_characters_nearby.erase(character)


func _forget_freed_characters() -> void:
	for index : int in range(_characters_nearby.size() - 1, -1, -1):
		if not is_instance_valid(_characters_nearby[index]):
			_characters_nearby.remove_at(index)
