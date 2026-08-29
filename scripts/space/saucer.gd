class_name Saucer
extends Node3D

## A nave do ET: um disco de 4 m com pad central, guarda-corpos e o anel de
## luzes (ver saucer_lights.gd). E uma cena so, usada sem escala nas duas
## pontas do fluxo -- Orbit.tscn (em orbita) e ancorada no ceu de uma
## fase --, por isso nao assume WorldEnvironment nem Player proprios, so o
## chao em si.
##
## O pad central tambem serve de gatilho de descida (ver
## set_descend_trigger_enabled()): a Orbit.tscn nunca liga esse gatilho, so
## o deck de chegada em world.gd, entao pisar no pad ali nao faz nada.
##
## O aviso de que o pad esta pronto e a propria luz dele pulsando sob os pes do
## ET -- nada de rotulo flutuante sobre o objeto.

signal descend_requested

## Quanto a luz do pad sobe e desce enquanto a descida pode ser acionada.
const PAD_PULSE_AMOUNT : float = 1.5
const PAD_PULSE_FREQUENCY : float = 1.9
const PAD_LIGHT_RESPONSE : float = 7.0

var _fall_guard_enabled : bool = true
var _descend_trigger_enabled : bool = false
var _characters_on_pad : Array[CharacterBody3D] = []
var _pad_idle_energy : float = 2.2
var _pad_pulse_phase : float = 0.0

@onready var spawn_point : Marker3D = $SpawnPoint
@onready var fall_guard : Area3D = $FallGuard
@onready var pad_trigger : Area3D = $Hull/Pad/PadTrigger
@onready var pad_light : OmniLight3D = $HullLights/PadLight


func _ready() -> void:
	_pad_idle_energy = pad_light.light_energy
	fall_guard.body_entered.connect(_on_fall_guard_body_entered)
	pad_trigger.body_entered.connect(_on_pad_body_entered)
	pad_trigger.body_exited.connect(_on_pad_body_exited)


func _process(delta : float) -> void:
	_forget_freed_pad_characters()
	var character_on_pad : bool = (
		_descend_trigger_enabled and not _characters_on_pad.is_empty()
	)

	var target_energy : float = _pad_idle_energy
	if character_on_pad:
		_pad_pulse_phase += delta * PAD_PULSE_FREQUENCY * TAU
		target_energy += PAD_PULSE_AMOUNT + sin(_pad_pulse_phase) * PAD_PULSE_AMOUNT
	else:
		_pad_pulse_phase = 0.0

	pad_light.light_energy = move_toward(
		pad_light.light_energy,
		maxf(target_energy, 0.0),
		PAD_LIGHT_RESPONSE * delta
	)

	if character_on_pad and Input.is_action_just_pressed("interact"):
		# Desarma na hora, como o ConsoleButton: enquanto a descida roda, um
		# segundo toque no pad nao deve disparar nada de novo.
		set_descend_trigger_enabled(false)
		descend_requested.emit()


## Liga/desliga o gatilho de descida no pad. Comeca desligado: so passa a
## responder depois que o deck termina de pousar (ver world.gd).
func set_descend_trigger_enabled(enabled : bool) -> void:
	_descend_trigger_enabled = enabled


func _on_pad_body_entered(body : Node3D) -> void:
	var character : CharacterBody3D = body as CharacterBody3D
	if character == null or not character.is_in_group("characters"):
		return
	if not _characters_on_pad.has(character):
		_characters_on_pad.append(character)


func _on_pad_body_exited(body : Node3D) -> void:
	var character : CharacterBody3D = body as CharacterBody3D
	if character != null:
		_characters_on_pad.erase(character)


func _forget_freed_pad_characters() -> void:
	for index : int in range(_characters_on_pad.size() - 1, -1, -1):
		if not is_instance_valid(_characters_on_pad[index]):
			_characters_on_pad.remove_at(index)


## Desliga a rede de seguranca. Necessario quando algo mais faz o personagem
## descer de proposito pela coluna abaixo do deck (o feixe de chegada de
## world.gd, por exemplo): sem isso, o proprio FallGuard intercepta a queda
## controlada e devolve o personagem ao spawn no meio da animacao.
func set_fall_guard_enabled(enabled : bool) -> void:
	_fall_guard_enabled = enabled


## Rede de seguranca embaixo do deck: as grades seguram o ET andando, mas um
## pulo na quina ainda passa por cima delas.
func _on_fall_guard_body_entered(body : Node3D) -> void:
	if not _fall_guard_enabled:
		return
	var character : CharacterBody3D = body as CharacterBody3D
	if character == null or not character.is_in_group("characters"):
		return
	character.velocity = Vector3.ZERO
	character.global_position = spawn_point.global_position
