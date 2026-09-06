extends Node3D

## Base das plantacoes reativas: milho, trigo e girassol.
##
## Cada filho `MeshInstance3D` e uma planta. Elas balancam com o vento e vergam
## para longe de quem passa -- personagens do grupo `characters` e veiculos do
## grupo `vehicles` --, voltando sozinhas ao repouso.
##
## Um talhao grande e feito de muitas instancias desta cena, e e por isso que o
## custo por instancia importa: sem os dois limites abaixo, cem talhoes cobram
## cem `_process` cheios por quadro e cem vezes a malha inteira na tela.
##
## - `active_radius`: sem ninguem por perto o talhao dorme, e o `_process` sai
##   no primeiro `if`. A vizinhanca e reconferida a cada `CHECK_INTERVAL`, com
##   a primeira conferencia sorteada para as instancias nao caírem no mesmo
##   quadro.
## - `visibility_range`: alem dessa distancia as plantas derretem em vez de
##   sumirem de uma vez. Quem faz isso e o proprio Godot, no
##   `GeometryInstance3D`, sem custo de script.

@export var interaction_radius: float = 1.5
@export var bend_strength: float = 25.0
@export var vehicle_bend_multiplier: float = 10.0
@export var return_speed: float = 5.0

@export var wind_strength: float = 1.0
@export var wind_speed: float = 1.5

## Raio em que o talhao acorda, medido do seu proprio centro.
@export var active_radius: float = 60.0
## Distancia em que as plantas somem, e a faixa em que elas derretem antes.
## Zero desliga o corte por distancia.
@export var visibility_range: float = 130.0
@export var visibility_fade: float = 20.0

## De quanto em quanto tempo o talhao reconfere se tem alguem por perto.
const CHECK_INTERVAL: float = 0.25

var _plants: Array[MeshInstance3D] = []
var _rest_rotations: Array[Vector3] = []
var _awake: bool = true
var _next_check: float = 0.0


func _ready() -> void:
	for child: Node in get_children():
		var plant: MeshInstance3D = child as MeshInstance3D
		if plant == null:
			continue
		_plants.append(plant)
		_rest_rotations.append(plant.rotation)
		if visibility_range > 0.0:
			plant.visibility_range_end = visibility_range
			plant.visibility_range_end_margin = visibility_fade
			plant.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_next_check = randf() * CHECK_INTERVAL


func _process(delta: float) -> void:
	_next_check -= delta
	if _next_check <= 0.0:
		_next_check = CHECK_INTERVAL
		_awake = _has_neighbour()
	if not _awake:
		return

	var characters: Array[Node] = get_tree().get_nodes_in_group("characters")
	var vehicles: Array[Node] = get_tree().get_nodes_in_group("vehicles")
	var time: float = Time.get_ticks_msec() / 1000.0

	for i: int in _plants.size():
		var plant: MeshInstance3D = _plants[i]
		if not is_instance_valid(plant):
			continue

		var strongest_bend: float = 0.0
		var strongest_direction: Vector3 = Vector3.ZERO

		for character: Node in characters:
			if not character is CharacterBody3D:
				continue
			var direction: Vector3 = plant.global_position - (character as Node3D).global_position
			direction.y = 0.0
			var distance: float = direction.length()
			if distance >= interaction_radius:
				continue
			var bend_amount: float = 1.0 - (distance / interaction_radius)
			bend_amount = bend_amount * bend_amount
			if bend_amount > strongest_bend:
				strongest_bend = bend_amount
				strongest_direction = direction.normalized()

		for vehicle: Node in vehicles:
			if not vehicle is VehicleBody3D:
				continue
			var direction: Vector3 = plant.global_position - (vehicle as Node3D).global_position
			direction.y = 0.0
			var distance: float = direction.length()
			if distance >= interaction_radius:
				continue
			var bend_amount: float = 1.0 - (distance * 1.5 / interaction_radius)
			bend_amount = bend_amount * bend_amount
			bend_amount *= vehicle_bend_multiplier
			if bend_amount > strongest_bend:
				strongest_bend = bend_amount
				strongest_direction = direction.normalized()

		var target_rotation: Vector3 = _rest_rotations[i]
		if strongest_bend > 0.0:
			var local_direction: Vector3 = plant.global_transform.basis.inverse() * strongest_direction
			target_rotation.x += local_direction.z * strongest_bend * deg_to_rad(bend_strength)
			target_rotation.z += -local_direction.x * strongest_bend * deg_to_rad(bend_strength)

		target_rotation.z += deg_to_rad(sin(time * wind_speed + float(i) * 1.73) * wind_strength)
		plant.rotation = plant.rotation.lerp(target_rotation, delta * return_speed)


## Tem personagem ou veiculo perto o bastante para valer a conta do quadro.
func _has_neighbour() -> bool:
	if active_radius <= 0.0:
		return true
	var here: Vector3 = global_position
	for group: String in ["characters", "vehicles"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body: Node3D = node as Node3D
			if body != null and here.distance_to(body.global_position) < active_radius:
				return true
	return false
