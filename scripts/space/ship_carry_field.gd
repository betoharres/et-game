class_name ShipCarryField
extends Area3D

## Transporta tudo que esta dentro da nave junto com ela.
##
## A nave e um Node3D girado por script. A velocidade de plataforma do
## CharacterBody3D nao resolve isso: ela so carrega quem esta com os pes no
## chao (um pulo de ~0.9 s a 1.8 u/s deixaria o ET 1.6 m para tras), nunca gira
## o facing do personagem e nunca gira a camera. Entao o transporte e feito
## aqui, a mao, aplicando em cada passageiro exatamente o mesmo transform
## rigido que a sala recebeu neste tick.
##
## Como o passageiro e as paredes recebem o MESMO transform, a posicao relativa
## entre eles nao muda: o carry nao consegue empurrar ninguem para dentro de
## uma parede. O move_and_slide() do passageiro, que roda logo depois neste
## mesmo tick, continua sendo o unico responsavel por resolver colisao.
##
## A geometria do interior e StaticBody3D de proposito. AnimatableBody3D seria
## mais amigavel ao Jolt (que separa corpos estaticos e moveis em arvores
## distintas), mas corpo cinematico IMPRIME velocidade de plataforma, que
## somaria por cima do carry e faria o ET andar em circulo ao dobro da
## velocidade. Corpo estatico nao imprime nada, entao o carry fica sendo a
## unica fonte de verdade.
##
## Requisitos de cena: filho do no que gira, CollisionShape3D cobrindo o volume
## interno, monitoring ligado e collision_mask alcancando a layer do player.

## Roda antes do _physics_process do player (prioridade 0, o default) para que
## a pose ja corrigida seja o ponto de partida do move_and_slide() E do alvo de
## camera do mesmo tick. Depois do move_and_slide o alvo publicado ficaria
## sempre um tick atrasado, e como o carry e continuo isso viraria erro de
## regime permanente, nao um transiente.
##
## Atencao: process_physics_priority, nao process_priority -- sao propriedades
## distintas, e o process_priority = 10 do CinematicCameraRig so ordena o
## _process() dele.
const CARRY_PHYSICS_PRIORITY : int = -10

## Abaixo disso o delta e ruido de float da nave parada. Aplicar so acumularia
## erro de ortonormalizacao sem mover nada.
const MINIMUM_CARRY_DISTANCE_SQUARED : float = 1e-12
const MINIMUM_CARRY_ANGLE : float = 1e-6

## O no cujo transform define o referencial. Vazio = o pai.
@export var ship : Node3D

var _passengers : Array[CharacterBody3D] = []
var _previous_transform : Transform3D = Transform3D.IDENTITY
var _has_previous_transform : bool = false


func _ready() -> void:
	if ship == null:
		ship = get_parent() as Node3D

	process_physics_priority = CARRY_PHYSICS_PRIORITY

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta : float) -> void:
	if ship == null:
		return

	_forget_freed_passengers()

	var current : Transform3D = ship.global_transform
	if not _has_previous_transform:
		# Primeiro tick: sem referencia anterior nao existe delta, e inventar um
		# a partir da identidade teleportaria todo mundo para a origem.
		_previous_transform = current
		_has_previous_transform = true
		return

	var previous : Transform3D = _previous_transform
	_previous_transform = current

	if _passengers.is_empty():
		return

	var up : Vector3 = current.basis.y.normalized()
	var carry_yaw : float = _signed_yaw_between(previous.basis, current.basis, up)

	# Testa a translacao da NAVE, nunca carry.origin: carry.origin e a imagem da
	# origem do mundo, e para uma rotacao em torno de um pivo distante ela fica
	# enorme mesmo com um yaw microscopico.
	var moved_squared : float = current.origin.distance_squared_to(previous.origin)
	if (
		moved_squared < MINIMUM_CARRY_DISTANCE_SQUARED
		and absf(carry_yaw) < MINIMUM_CARRY_ANGLE
	):
		return

	# T_agora * T_antes^-1 leva qualquer ponto preso a nave da posicao antiga
	# para a nova. affine_inverse() e nao inverse(): inverse() assume base
	# ortonormal e devolve lixo em silencio se alguem escalar a nave no editor.
	var carry : Transform3D = current * previous.affine_inverse()
	# Sao 60 multiplicacoes de matriz por segundo, indefinidamente: sem
	# reortonormalizar, a base acumula skew em poucos minutos de rotacao.
	carry.basis = carry.basis.orthonormalized()

	for passenger : CharacterBody3D in _passengers:
		_carry_passenger(passenger, carry, carry_yaw)


func _carry_passenger(
	passenger : CharacterBody3D,
	carry : Transform3D,
	carry_yaw : float
) -> void:
	# O player sabe carregar o proprio estado derivado: camera_yaw, o rig
	# top_level, o ragdoll e os angulos de mundo da manobra de virada. Quem nao
	# souber leva so o transform rigido, que ja resolve um NPC simples.
	if passenger.has_method("apply_carry"):
		passenger.call("apply_carry", carry, carry_yaw)
		return

	passenger.global_transform = (carry * passenger.global_transform).orthonormalized()
	passenger.velocity = carry.basis * passenger.velocity


## Angulo assinado entre o forward antigo e o novo, projetados no plano da
## rotacao. Preferivel a basis.get_euler().y: nao depende da ordem de Euler, nao
## quebra se a nave um dia ganhar um pitch de manobra, e ja devolve em
## (-PI, PI] -- entao o delta nunca precisa de wrapf().
func _signed_yaw_between(
	previous_basis : Basis,
	current_basis : Basis,
	up : Vector3
) -> float:
	var previous_forward : Vector3 = previous_basis.z.slide(up)
	var current_forward : Vector3 = current_basis.z.slide(up)
	if (
		previous_forward.length_squared() <= 0.0001
		or current_forward.length_squared() <= 0.0001
	):
		return 0.0

	return previous_forward.normalized().signed_angle_to(
		current_forward.normalized(),
		up
	)


func _on_body_entered(body : Node3D) -> void:
	var character : CharacterBody3D = body as CharacterBody3D
	if character == null:
		return
	if (
		not character.is_in_group("characters")
		and not character.is_in_group("ship_passengers")
	):
		return
	if not _passengers.has(character):
		_passengers.append(character)


func _on_body_exited(body : Node3D) -> void:
	var character : CharacterBody3D = body as CharacterBody3D
	if character != null:
		_passengers.erase(character)


func _forget_freed_passengers() -> void:
	for index : int in range(_passengers.size() - 1, -1, -1):
		if not is_instance_valid(_passengers[index]):
			_passengers.remove_at(index)
