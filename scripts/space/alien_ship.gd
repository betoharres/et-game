class_name AlienShip
extends Node3D

## o pad de descida vem do interior (ver scripts/spaceship_interior.gd), e a nave pode girar sem levar
## o jogador junto para o lado errado, porque o ShipCarryField filho transporta
## quem esta a bordo.

signal descend_requested

## Velocidade de rotacao em yaw, em rad/s. 0.18 e uma volta a cada ~35 s: lento
## o bastante para a vista pela janela ler como "a nave esta pairando e virando
## devagar" em vez de carrossel. Zero desliga o giro -- e o caso do deck de
## chegada de uma fase, que so desce em linha reta.
@export_range(0.0, 1.0, 0.01) var spin_speed : float = 0.0

## Direcao local para onde a janela panoramica aponta. Usada por
## stop_spin_facing() para alinhar a vista antes de uma cutscene.
@export var window_forward : Vector3 = Vector3.FORWARD

## Roda antes do ShipCarryField (-10), que roda antes do player (0): o transform
## da nave precisa estar atualizado antes de qualquer um medir o delta dele.
const SPIN_PHYSICS_PRIORITY : int = -20

const BEAM_LIGHT_ENERGY : float = 5.2
const BEAM_GROUND_LIGHT_ENERGY : float = 1.6
const BEAM_GROUND_LIGHT_RANGE : float = 8.5
const ALIEN_FOG_BEAM_BOOST : float = 0.6
const ENGINE_IDLE_VOLUME_DB : float = -24.0
const ENGINE_APPROACH_VOLUME_DB : float = -5.0

var _spin_active : bool = true
var _debug_lighting_enabled : bool = true
var _debug_lighting_intensity : float = 1.0
var _alien_fog_intensity : float = 0.0
var _atmosphere_quality_level : int = 2
var _base_beam_energies : Array[float] = []
var _player_inside : bool = false
var _approach_audio_started : bool = false

@onready var interior : Node3D = $Interior
@onready var spawn_point : Marker3D = $SpawnPoint
@onready var fall_guard : Area3D = $FallGuard
@onready var transport_beam : MeshInstance3D = $Props/TransportBeam
@onready var interior_ambience : AudioStreamPlayer = $ShipAudio/InteriorAmbience
@onready var movement_hum : AudioStreamPlayer = $ShipAudio/MovementHum
@onready var heavy_engine : AudioStreamPlayer = $ShipAudio/HeavyEngine
@onready var security_alert : AudioStreamPlayer = $ShipAudio/SecurityAlert
@onready var beam_lights : Array[SpotLight3D] = [
	$BeamLights/BeamFront,
	$BeamLights/BeamRight,
	$BeamLights/BeamLeft,
]
@onready var beam_volumes : Array[MeshInstance3D] = [
	$BeamLights/BeamFrontVolume,
	$BeamLights/BeamRightVolume,
	$BeamLights/BeamLeftVolume,
]

var _fall_guard_enabled : bool = true


func _ready() -> void:
	process_physics_priority = SPIN_PHYSICS_PRIORITY
	interior.descend_requested.connect(_on_interior_descend_requested)
	fall_guard.body_entered.connect(_on_fall_guard_body_entered)
	transport_beam.visible = false
	for beam_light : SpotLight3D in beam_lights:
		_base_beam_energies.append(beam_light.light_energy)
	_set_mp3_loop_enabled(interior_ambience.stream, true)
	_update_interior_audio()
	_apply_debug_lighting()


func _physics_process(delta : float) -> void:
	if not _spin_active or is_zero_approx(spin_speed):
		return
	# No _physics_process, nunca no _process: a colisao do interior e lida pelo
	# servidor de fisica neste mesmo tick, e o ShipCarryField mede o delta daqui.
	rotation.y += spin_speed * delta


## Para o giro e vira a janela para um alvo, devolvendo o Tween para quem quiser
## esperar. Sem isto uma cutscene que acontece "pela janela" pode rodar com a
## janela virada para o lado oposto.
func stop_spin_facing(target_global_position : Vector3, duration : float) -> Tween:
	_spin_active = false

	var up : Vector3 = Vector3.UP
	var current_direction : Vector3 = (global_basis * window_forward).slide(up)
	var target_direction : Vector3 = (
		target_global_position - global_position
	).slide(up)

	var tween : Tween = create_tween()
	# A rotacao da nave tem que avancar no mesmo passo da fisica que o
	# ShipCarryField le, senao o carry mede deltas incoerentes com a colisao.
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if (
		current_direction.length_squared() <= 0.0001
		or target_direction.length_squared() <= 0.0001
	):
		return tween

	# signed_angle_to ja devolve em (-PI, PI], entao o giro sai sempre pelo
	# caminho curto sem precisar de wrap manual.
	var delta_yaw : float = current_direction.normalized().signed_angle_to(
		target_direction.normalized(),
		up
	)
	tween.tween_property(self, "rotation:y", rotation.y + delta_yaw, duration)
	return tween


## Ajusta a camera para o espaco fechado sem esconder partes do modelo. Como o
## exterior e o interior agora compartilham o mesmo mesh, culling por layer
## removeria tambem o interior que o jogador precisa enxergar.
func set_player_inside(player : CharacterBody3D, inside : bool) -> void:
	_player_inside = inside
	_update_interior_audio()
	var rig : CinematicCameraRig = player.camera_pivot
	if rig == null:
		return
	rig.set_interior_camera_mode(inside)


## Alerta curto usado quando o terminal confirma uma missao. Fica na nave
## reutilizavel para continuar sendo uma propriedade do interior, nao da UI.
func play_security_alert() -> void:
	if not _player_inside:
		return
	security_alert.stop()
	security_alert.play()


## Dispara o hum de partida e traz a camada pesada do motor para frente durante
## o deslocamento. Ambos sao one-shots; a troca de cena encerra suas caudas.
func begin_approach_audio(ramp_duration : float) -> void:
	if not _player_inside or _approach_audio_started:
		return
	_approach_audio_started = true
	movement_hum.stop()
	movement_hum.play()
	heavy_engine.play()
	var tween : Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(
		heavy_engine,
		"volume_db",
		ENGINE_APPROACH_VOLUME_DB,
		maxf(ramp_duration, 0.1)
	)


func end_approach_audio(fade_duration : float) -> void:
	if not heavy_engine.playing:
		return
	var tween : Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		heavy_engine,
		"volume_db",
		ENGINE_IDLE_VOLUME_DB,
		maxf(fade_duration, 0.1)
	)
	tween.tween_callback(heavy_engine.stop)


## Arma/desarma o pad de descida do interior. Comeca desarmado: em orbita ele so
## deve responder depois que uma missao foi escolhida, e numa fase so depois que
## o deck termina de pousar.
func set_descend_trigger_enabled(enabled : bool) -> void:
	transport_beam.visible = enabled
	interior.set_descend_trigger_enabled(enabled)


## Arms the same central beam as a walk-in teleporter. Orbit uses this mode
## after a mission is confirmed; entering its volume emits descend_requested
## without requiring a second interaction key press.
func set_transport_beam_enabled(enabled : bool) -> void:
	transport_beam.visible = enabled
	interior.set_descend_trigger_enabled(enabled, true)


## Desliga a rede de seguranca. Necessario quando algo mais faz o personagem
## descer de proposito pela coluna abaixo da nave (o feixe de chegada de
## world.gd): sem isso o proprio FallGuard intercepta a queda controlada e
## devolve o personagem ao spawn no meio da animacao.
func set_fall_guard_enabled(enabled : bool) -> void:
	_fall_guard_enabled = enabled


## Compatibilidade com a nave que existia no Barn: o menu de depuracao e os
## eventos alienigenas usam este mesmo contrato em qualquer cena que tenha a
## nave, agora sempre a instancia reutilizavel AlienShip.tscn.
func set_debug_lighting_enabled(enabled : bool) -> void:
	_debug_lighting_enabled = enabled
	_apply_debug_lighting()


func is_debug_lighting_enabled() -> bool:
	return _debug_lighting_enabled


func set_debug_lighting_intensity(intensity : float) -> void:
	_debug_lighting_intensity = clampf(intensity, 0.0, 2.0)
	_apply_debug_lighting()


func get_debug_lighting_intensity() -> float:
	return _debug_lighting_intensity


func set_atmosphere_quality(quality_level : int, _particles_allowed : bool) -> void:
	_atmosphere_quality_level = quality_level
	for beam_light : SpotLight3D in beam_lights:
		beam_light.shadow_enabled = _atmosphere_quality_level > 0
	_apply_debug_lighting()


func set_alien_fog_intensity(intensity : float) -> void:
	_alien_fog_intensity = clampf(intensity, 0.0, 1.0)
	_apply_debug_lighting()


func begin_external_movement() -> void:
	# A nave reutilizavel nao patrulha por conta propria; a entrega pode mover o
	# proprio no sem disputar posicao com outro controlador.
	pass


func end_external_movement() -> void:
	pass


func configure_external_beam(
	spotlight : SpotLight3D,
	ground_light : OmniLight3D,
	volume : MeshInstance3D
) -> void:
	spotlight.light_color = beam_lights[0].light_color
	spotlight.light_energy = BEAM_LIGHT_ENERGY
	spotlight.shadow_enabled = _atmosphere_quality_level > 0
	spotlight.spot_angle = beam_lights[0].spot_angle
	spotlight.spot_attenuation = beam_lights[0].spot_attenuation
	ground_light.light_color = beam_lights[0].light_color
	ground_light.light_energy = BEAM_GROUND_LIGHT_ENERGY
	ground_light.omni_range = BEAM_GROUND_LIGHT_RANGE
	ground_light.shadow_enabled = false
	var source_material : Material = beam_volumes[0].get_active_material(0)
	if source_material != null:
		volume.material_override = source_material


func _apply_debug_lighting() -> void:
	var alien_scale : float = 1.0 + _alien_fog_intensity * ALIEN_FOG_BEAM_BOOST
	for index : int in range(beam_lights.size()):
		var beam_light : SpotLight3D = beam_lights[index]
		beam_light.visible = _debug_lighting_enabled
		beam_light.light_energy = (
			_base_beam_energies[index]
			* _debug_lighting_intensity
			* alien_scale
		)
	for beam_volume : MeshInstance3D in beam_volumes:
		beam_volume.visible = (
			_debug_lighting_enabled and _atmosphere_quality_level > 0
		)


func _set_mp3_loop_enabled(stream : AudioStream, enabled : bool) -> void:
	var mp3_stream : AudioStreamMP3 = stream as AudioStreamMP3
	if mp3_stream != null:
		mp3_stream.loop = enabled


func _update_interior_audio() -> void:
	if _player_inside:
		if not interior_ambience.playing:
			interior_ambience.play()
		return

	interior_ambience.stop()
	movement_hum.stop()
	heavy_engine.stop()
	heavy_engine.volume_db = ENGINE_IDLE_VOLUME_DB
	security_alert.stop()
	_approach_audio_started = false


func _on_interior_descend_requested() -> void:
	descend_requested.emit()


## Rede de seguranca embaixo da nave, para o caso de o ET escapar pela janela ou
## por um vao da geometria. Em orbita a alternativa e cair no vazio para sempre.
func _on_fall_guard_body_entered(body : Node3D) -> void:
	if not _fall_guard_enabled:
		return
	var character : CharacterBody3D = body as CharacterBody3D
	if character == null or not character.is_in_group("characters"):
		return
	character.velocity = Vector3.ZERO
	character.global_position = spawn_point.global_position
