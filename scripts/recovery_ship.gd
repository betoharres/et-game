extends Node3D

@export var zone_path : NodePath
@export var flight_speed : float = 28.0
@export var cruise_height : float = 45.0
@export var capture_height : float = 12.0
@export var lift_speed : float = 5.0
@export_range(0.0, 2.0, 0.05) var spin_speed : float = 0.28

@onready var zone : Area3D = get_node(zone_path) as Area3D
@onready var beam : MeshInstance3D = $Beam
@onready var source_ship : Node3D = $Hull

var _patrol_index : int = 0
var _cargo : RigidBody3D = null
var _elapsed : float = 0.0
var _home_position : Vector3
var _home_rotation_y : float


func _ready() -> void:
	# Reusa a nave legada como visual, mas deixa este controlador ser a autoridade
	# de deslocamento durante a coleta.
	if source_ship.has_method("begin_external_movement"):
		source_ship.call("begin_external_movement")
	_home_position = global_position
	_home_rotation_y = rotation.y
	_set_tractor_beam(false)


func _physics_process(delta : float) -> void:
	_elapsed += delta
	$Hull.position.y = sin(_elapsed * 1.6) * 0.15
	if is_instance_valid(_cargo):
		_cargo.global_position = _cargo.global_position.move_toward(global_position + Vector3.DOWN, lift_speed * delta)
		_cargo.rotate_y(delta)
		if _cargo.global_position.distance_to(global_position + Vector3.DOWN) < 0.1:
			var score : int = int(_cargo.get("score_value"))
			GlobalScore.add_score(score)
			_cargo.queue_free()
			_cargo = null
			_set_tractor_beam(false)
			zone.item_delivered.emit(score)
		return
	beam.hide()
	var items : Array[RigidBody3D] = zone.available_items()
	if not items.is_empty():
		zone.status_text = "Nave a caminho — %d item(ns) aguardando" % items.size()
		var above : Vector3 = zone.global_position + Vector3.UP * cruise_height
		_move_to(above, delta)
		if global_position.distance_to(above) < 0.1:
			# Reconsulta na chegada: o jogador pode ter recolhido ou empurrado a carga.
			items = zone.available_items()
			for item : RigidBody3D in items:
				if item.has_method("begin_abduction") and bool(item.call("begin_abduction")):
					_cargo = item
					_cargo.collision_layer = 0
					_cargo.collision_mask = 0
					_set_tractor_beam(true)
					zone.status_text = "Recolhendo itens"
					break
		return
	zone.status_text = "Largue os itens dentro do círculo"
	_set_tractor_beam(false)
	# A nave fica em um único ponto, girando como no mapa antigo. Ela só o
	# abandona enquanto atende uma coleta e retorna assim que termina.
	if global_position.distance_to(_home_position) > 0.1:
		_move_to(_home_position, delta)
		return
	rotation.y = wrapf(rotation.y + spin_speed * delta, -PI, PI)


func _set_tractor_beam(enabled : bool) -> void:
	# A space_ship.tscn já possui três braços do raio trator. Reutilizamos os
	# volumes e spots originais e apenas estendemos o volume até a área no solo.
	beam.hide()
	for index : int in range(1, 4):
		var spotlight : SpotLight3D = source_ship.get_node_or_null(
			"LightArm%d/SpotLight3D" % index
		) as SpotLight3D
		var volume : MeshInstance3D = source_ship.get_node_or_null(
			"LightArm%d/SpotLight3D/BeamVolume%d" % [index, index]
		) as MeshInstance3D
		if spotlight == null or volume == null:
			continue
	# Os três holofotes ficam visíveis mesmo em espera; o cone volumétrico só
	# aparece durante a coleta para não formar um triângulo escuro no céu.
		spotlight.visible = true
		volume.visible = enabled
		if enabled:
			var ground_height : float = maxf(
				global_position.y - zone.global_position.y,
				1.0
			)
			volume.scale.y = ground_height / (38.0 * 0.16)


func _move_to(target : Vector3, delta : float) -> void:
	var direction : Vector3 = target - global_position
	if Vector2(direction.x, direction.z).length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 2.0, 1.0))
	global_position = global_position.move_toward(target, flight_speed * delta)
