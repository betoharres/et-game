class_name NPCActor
extends CharacterBody3D

## Chassi comum a todo NPC de pé (fazendeiro, morador, policial). Cuida de
## locomoção via NavigationAgent3D, patrulha por Marker3D e do estado exibido
## pela Behavior Tree; visão e audição ficam em componentes filhos separados
## (NPCVision/NPCHearing).

enum ReactionMode { CHASE, FLEE }

@export_category("Movimento")
@export var walk_speed: float = 2.0
@export var alert_speed: float = 3.4
@export var rotation_speed: float = 2.5

@export_category("Rotina")
## Posições absolutas (mundo) que o NPC visita em sequência, na mesma
## convenção de `VehicleAIDriver.road_nodes`. Um único ponto (ou nenhum) faz o
## NPC ficar parado "trabalhando" em vez de patrulhar.
@export var patrol_points: Array[Vector3] = []
@export var patrol_wait_time_min: float = 2.0
@export var patrol_wait_time_max: float = 5.0
@export var idle_wait_time_min: float = 3.0
@export var idle_wait_time_max: float = 7.0

@export_category("Reação ao ET")
@export var reaction_mode: ReactionMode = ReactionMode.CHASE
@export var search_duration: float = 6.0
@export var investigate_wait_time: float = 3.0
@export var flee_distance: float = 18.0

@export_category("Social")
@export var can_socialize: bool = false
@export var social_group_name: StringName = &""
@export var chat_radius: float = 3.5
@export var chat_stop_distance: float = 1.4
@export var chat_duration_min: float = 2.5
@export var chat_duration_max: float = 5.0
@export var chat_cooldown: float = 12.0

@export_category("Lanterna")
@export var use_flashlight: bool = false
@export var flashlight_path: NodePath

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var vision: NPCVision = get_node_or_null("NPCVision")
@onready var hearing: NPCHearing = get_node_or_null("NPCHearing")
@onready var animation: NPCAnimation = get_node_or_null("NPCAnimation")
@onready var flashlight: Light3D = (
	get_node_or_null(flashlight_path) if not flashlight_path.is_empty() else null
)

var player: CharacterBody3D = null
var state: StringName = &"idle"
var last_chat_time: float = -1000.0

signal state_changed(new_state: StringName)


func _ready() -> void:
	add_to_group(&"npc_actors")
	if social_group_name != &"":
		add_to_group(social_group_name)

	_find_player()

	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = 0.8

	if flashlight:
		flashlight.visible = use_flashlight


func _find_player() -> void:
	var characters: Array[Node] = get_tree().get_nodes_in_group("characters")
	for character in characters:
		if character is CharacterBody3D:
			player = character
			break


func get_patrol_positions() -> Array[Vector3]:
	return patrol_points


func set_state(new_state: StringName) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)


## Avança um passo em direção a `point`. Retorna `true` quando chegou perto o
## bastante (`target_desired_distance` do NavigationAgent3D). Usa o caminho do
## NavigationAgent3D quando há malha bakeada contribuindo para o mapa; sem
## isso (caso do Country Town hoje), cai para ir direto ao ponto em linha
## reta, em vez de ficar parado esperando uma malha que não existe.
func move_toward_point(point: Vector3, speed: float) -> bool:
	var to_point: Vector3 = point - global_position
	to_point.y = 0.0
	if to_point.length() <= navigation_agent.target_desired_distance:
		stop_moving()
		return true

	var direction: Vector3 = Vector3.ZERO
	var nav_map: RID = navigation_agent.get_navigation_map()
	var has_synced_navmesh: bool = (
		nav_map.is_valid() and NavigationServer3D.map_get_iteration_id(nav_map) != 0
	)

	if has_synced_navmesh:
		if navigation_agent.target_position.distance_to(point) > 0.05:
			navigation_agent.target_position = point
		var next_position: Vector3 = navigation_agent.get_next_path_position()
		direction = next_position - global_position
		direction.y = 0.0

	if direction.length_squared() < 0.01:
		direction = to_point

	direction = direction.normalized()
	velocity = direction * speed
	move_and_slide()
	face_direction(direction)
	if animation:
		animation.set_moving(true)
	return false


func face_direction(direction: Vector3) -> void:
	if direction.length_squared() < 0.001:
		return
	var target_angle: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(
		rotation.y, target_angle, get_physics_process_delta_time() * rotation_speed
	)


func stop_moving() -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	if animation:
		animation.set_moving(false)


func is_player_alive() -> bool:
	if player == null:
		return false
	if player.has_method("is_alive"):
		return bool(player.call("is_alive"))
	return true
