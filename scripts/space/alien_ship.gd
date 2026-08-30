class_name AlienShip
extends Node3D

## A nave triangular do ET, habitavel por dentro. Substitui o Saucer nas duas
## pontas do fluxo -- parada em orbita (Orbit.tscn) e ancorada no ceu de uma
## fase (world.gd) -- expondo a mesma API que o disco expunha, para que os dois
## consumidores nao precisem saber qual nave esta em cena:
##
##   descend_requested / set_descend_trigger_enabled() / set_fall_guard_enabled()
##   / spawn_point
##
## A diferenca real e que aqui o ET fica DENTRO: o pad de descida vem do
## interior (ver scripts/spaceship_interior.gd), e a nave pode girar sem levar
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

## Bit da render layer 12, exclusiva do casco (ver project.godot).
##
## Layer 12 e nao 11: a 11 ja e da mira do aviao (FlyablePlane.tscn), que as
## duas cameras do ET excluem de proposito. Reaproveita-la faria a mira brotar
## no ar toda vez que o casco fosse religado depois do pouso.
##
## O ET_Alien_Space_Ship.glb nao tem janela modelada, e a forma dele e uma placa
## triangular chata com um unico pico no meio -- a altura interna cai de ~5
## unidades no centro para zero nas bordas. Nenhuma escala faz uma sala de
## 20x20x5 caber la dentro E deixar ver para fora: o casco sempre aparece na
## frente da janela, e o bico oco fica bem no eixo dela.
##
## A saida e o casco existir so para quem esta de FORA. Ele fica numa layer so
## dele, e a camera de quem esta a bordo simplesmente nao desenha essa layer:
## de dentro a janela mostra o espaco, e de fora a nave triangular esta inteira.
const HULL_CULL_BIT : int = 1 << 11

var _spin_active : bool = true

@onready var interior : Node3D = $Interior
@onready var spawn_point : Marker3D = $SpawnPoint
@onready var fall_guard : Area3D = $FallGuard

var _fall_guard_enabled : bool = true


func _ready() -> void:
	process_physics_priority = SPIN_PHYSICS_PRIORITY
	interior.descend_requested.connect(_on_interior_descend_requested)
	fall_guard.body_entered.connect(_on_fall_guard_body_entered)


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


## Liga/desliga o desenho do casco para uma camera. Ver HULL_CULL_BIT.
func set_hull_visible_to(camera : Camera3D, hull_visible : bool) -> void:
	if camera == null:
		return
	if hull_visible:
		camera.cull_mask |= HULL_CULL_BIT
	else:
		camera.cull_mask &= ~HULL_CULL_BIT


## Conveniencia para os dois consumidores: o rig do ET carrega duas cameras (a
## normal e a do XRAY), e esquecer a segunda faz o casco reaparecer no instante
## em que o jogador levanta os binoculos dentro da nave.
func set_hull_visible_to_player(
	player : CharacterBody3D,
	hull_visible : bool
) -> void:
	var rig : CinematicCameraRig = player.camera_pivot
	if rig == null:
		return
	set_hull_visible_to(rig.camera, hull_visible)
	set_hull_visible_to(rig.xray_camera, hull_visible)


## Arma/desarma o pad de descida do interior. Comeca desarmado: em orbita ele so
## deve responder depois que uma missao foi escolhida, e numa fase so depois que
## o deck termina de pousar.
func set_descend_trigger_enabled(enabled : bool) -> void:
	interior.set_descend_trigger_enabled(enabled)


## Desliga a rede de seguranca. Necessario quando algo mais faz o personagem
## descer de proposito pela coluna abaixo da nave (o feixe de chegada de
## world.gd): sem isso o proprio FallGuard intercepta a queda controlada e
## devolve o personagem ao spawn no meio da animacao.
func set_fall_guard_enabled(enabled : bool) -> void:
	_fall_guard_enabled = enabled


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
