@tool
class_name TireTrack3D
extends Path3D

## Marca de pneu desenhada sobre uma curva, independente da estrada. O tracado e
## a Curve3D do proprio no: o artista posiciona a mao, no editor, onde um veiculo
## teria passado -- uma entrada de fazenda, o lado interno de uma curva, a saida
## de um cruzamento. A malha e assada no editor e fica salva na cena; em jogo
## nada e gerado, so a fita pronta e desenhada.
##
## Uma instancia pode conter varias passagens paralelas (`lanes`), como as duas
## rodas de um veiculo, e varias instancias podem se sobrepor livremente: o
## material dissolve as bordas, entao trilhas cruzadas se misturam sem emenda.

## Nome do filho que recebe a malha assada.
const SURFACE_NAME: String = "Surface"
## Colunas de vertice ao longo da largura da fita.
const COLUMNS: int = 4
const UP: Vector3 = Vector3.UP

@export_group("Passagens")
## Rastros paralelos desta instancia: 2 para um veiculo, 1 para uma marca solta.
@export_range(1, 6, 1) var lanes: int = 2:
	set(value):
		lanes = value
		_schedule_bake()
## Bitola entre os rastros. 1.6 m e a da caminhonete do jogo.
@export_range(0.4, 4.0, 0.05) var lane_spacing: float = 1.6:
	set(value):
		lane_spacing = value
		_schedule_bake()
## Deslocamento lateral da instancia inteira: repete a mesma curva ao lado.
@export_range(-6.0, 6.0, 0.05) var lane_offset: float = 0.0:
	set(value):
		lane_offset = value
		_schedule_bake()

@export_group("Forma da fita")
@export_range(0.15, 1.2, 0.01) var track_width: float = 0.45:
	set(value):
		track_width = value
		_schedule_bake()
## Quanto a largura respira ao longo do caminho, em fracao da largura.
@export_range(0.0, 0.6, 0.02) var width_variation: float = 0.22:
	set(value):
		width_variation = value
		_schedule_bake()
## Amplitude do serpenteio lateral: nenhum veiculo anda em linha perfeita.
@export_range(0.0, 1.5, 0.02) var lateral_wander: float = 0.18:
	set(value):
		lateral_wander = value
		_schedule_bake()
## Comprimento de onda do serpenteio, em metros.
@export_range(2.0, 40.0, 0.5) var wander_length: float = 14.0:
	set(value):
		wander_length = value
		_schedule_bake()
## Distancia entre estacoes ao longo da curva; menor acompanha melhor o relevo.
@export_range(0.3, 4.0, 0.1) var sample_step: float = 1.2:
	set(value):
		sample_step = value
		_schedule_bake()

@export_group("Desgaste")
## Intensidade da passagem: 1 e barro fundo, 0.3 e uma marca velha quase apagada.
@export_range(0.05, 1.0, 0.05) var intensity: float = 0.85:
	set(value):
		intensity = value
		_schedule_bake()
## Variacao da intensidade ao longo do caminho e entre os rastros.
@export_range(0.0, 0.8, 0.02) var intensity_variation: float = 0.3:
	set(value):
		intensity_variation = value
		_schedule_bake()
## Metros das pontas em que a marca nasce e morre no chao.
@export_range(0.0, 12.0, 0.25) var end_fade: float = 3.0:
	set(value):
		end_fade = value
		_schedule_bake()
## Metros de caminho por repeticao da textura de banda.
@export_range(0.3, 8.0, 0.1) var tread_length: float = 1.6:
	set(value):
		tread_length = value
		_schedule_bake()
## Muda todas as variacoes de uma vez, sem mexer em nenhum outro valor.
@export var random_seed: int = 1:
	set(value):
		random_seed = value
		_schedule_bake()

@export_group("Assentamento")
## Assenta cada vertice na altura do chao; desligue para seguir a curva a mao.
@export var snap_to_ground: bool = true:
	set(value):
		snap_to_ground = value
		_schedule_bake()
## Folga sobre o chao: alta o bastante para nao brigar por z, baixa o bastante
## para a fita nao flutuar em rampa.
@export_range(0.005, 0.2, 0.005) var ground_offset: float = 0.03:
	set(value):
		ground_offset = value
		_schedule_bake()
## Camadas do raycast usado quando nao ha Terrain3D na cena.
@export_flags_3d_physics var ground_mask: int = 1

@export_group("Render")
@export var material: Material = preload("res://Materiais/tire_track.tres"):
	set(value):
		material = value
		_apply_render_settings()
## Distancia em que a fita some, antes de virar cintilacao no horizonte.
@export_range(20.0, 400.0, 5.0) var visible_range: float = 150.0:
	set(value):
		visible_range = value
		_apply_render_settings()

## Botao do inspetor: reassa a marca com os valores atuais.
@export_tool_button("Reassar marca") var bake_action: Callable = bake

## Altura do chao fornecida de fora, usada pelo build headless de `tools/`.
var height_provider: Callable = Callable()

var _terrain: Node = null
var _bake_queued: bool = false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	if curve != null and not curve.changed.is_connected(_schedule_bake):
		curve.changed.connect(_schedule_bake)
	_apply_render_settings()


## Reconstroi a malha da marca. Fora do editor so roda quando um build de
## `tools/` chama de proposito: em jogo a fita ja vem assada na cena.
func bake() -> void:
	var surface_node: MeshInstance3D = _surface()
	if Engine.is_editor_hint() and curve != null and not curve.changed.is_connected(_schedule_bake):
		curve.changed.connect(_schedule_bake)
	if curve == null or curve.point_count < 2:
		surface_node.mesh = null
		return
	var length: float = curve.get_baked_length()
	if length < sample_step * 2.0:
		surface_node.mesh = null
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = random_seed
	var tool_surface: SurfaceTool = SurfaceTool.new()
	tool_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stations: int = maxi(2, int(round(length / sample_step)) + 1)
	var triangles: int = 0
	for lane: int in lanes:
		var center: float = lane_offset + (float(lane) - float(lanes - 1) * 0.5) * lane_spacing
		var lane_data: Dictionary = {
			"center": center + rng.randf_range(-0.06, 0.06) * lane_spacing,
			"phase": rng.randf_range(0.0, TAU),
			"wear": clampf(intensity * (1.0 - rng.randf_range(0.0, intensity_variation)), 0.05, 1.0),
			"width": track_width * rng.randf_range(0.9, 1.1),
			"uv": rng.randf_range(0.0, 1.0),
		}
		var previous: Array = []
		for index: int in stations:
			var along: float = length * float(index) / float(stations - 1)
			var row: Array = _station(along, length, lane_data)
			if not previous.is_empty():
				triangles += _stitch(tool_surface, previous, row)
			previous = row
	if triangles == 0:
		surface_node.mesh = null
		return
	tool_surface.index()
	tool_surface.generate_normals()
	tool_surface.generate_tangents()
	surface_node.mesh = tool_surface.commit()
	_apply_render_settings()


## Uma fileira de vertices da fita, em espaco local do Path3D.
func _station(along: float, length: float, lane: Dictionary) -> Array:
	var point: Vector3 = curve.sample_baked(along)
	# Tangente por diferenca central: em quina de curva a fita gira aos poucos.
	var ahead: Vector3 = curve.sample_baked(minf(along + 0.5, length))
	var behind: Vector3 = curve.sample_baked(maxf(along - 0.5, 0.0))
	var forward: Vector3 = ahead - behind
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		forward = Vector3.FORWARD
	var lateral: Vector3 = forward.normalized().cross(UP).normalized()
	var phase: float = float(lane["phase"])
	var wave: float = sin(along * TAU / wander_length + phase) * 0.6 + sin(along * TAU / (wander_length * 0.43) + phase * 1.7) * 0.4
	var offset: float = float(lane["center"]) + wave * lateral_wander
	var width: float = float(lane["width"]) * (1.0 + wave * width_variation)
	var axis: Vector3 = point + lateral * offset
	# As pontas nascem e morrem no chao: instancias vizinhas se emendam sem costura.
	var ends: float = 1.0
	if end_fade > 0.01:
		ends = smoothstep(0.0, 1.0, clampf(minf(along, length - along) / end_fade, 0.0, 1.0))
	var wear: float = clampf(float(lane["wear"]) * (1.0 - intensity_variation * 0.5 * (0.5 + 0.5 * wave)), 0.05, 1.0)
	var v: float = along / tread_length + float(lane["uv"])
	var row: Array = []
	for column: int in COLUMNS:
		var u: float = float(column) / float(COLUMNS - 1)
		var vertex: Vector3 = axis + lateral * ((u - 0.5) * width)
		vertex.y = _settle(vertex)
		row.append({"position": vertex, "uv": Vector2(u, v), "color": Color(wear, 0.0, 0.0, ends)})
	return row


## Costura duas fileiras vizinhas em quads.
func _stitch(surface: SurfaceTool, back: Array, front: Array) -> int:
	var triangles: int = 0
	for column: int in COLUMNS - 1:
		_triangle(surface, back[column], back[column + 1], front[column + 1])
		_triangle(surface, back[column], front[column + 1], front[column])
		triangles += 2
	return triangles


func _triangle(surface: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	for vertex: Dictionary in [a, b, c]:
		surface.set_color(vertex["color"])
		surface.set_uv(vertex["uv"])
		surface.add_vertex(vertex["position"])


## Assenta um ponto local na altura do chao, com a folga que evita z-fighting.
func _settle(local_point: Vector3) -> float:
	if not snap_to_ground:
		return local_point.y + ground_offset
	var placement: Transform3D = global_transform if is_inside_tree() else transform
	var world_point: Vector3 = placement * local_point
	var ground: float = _ground_height(world_point)
	if is_nan(ground):
		return local_point.y + ground_offset
	var settled: Vector3 = world_point
	settled.y = ground + ground_offset
	return (placement.affine_inverse() * settled).y


## Altura do chao em um ponto de mundo, ou NAN quando nao ha chao conhecido.
func _ground_height(world_point: Vector3) -> float:
	if height_provider.is_valid():
		return height_provider.call(world_point)
	var terrain: Node = _find_terrain()
	if terrain != null:
		var height: float = terrain.data.get_height(world_point)
		if not is_nan(height):
			return height
	if not is_inside_tree():
		return NAN
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return NAN
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		world_point + UP * 50.0, world_point - UP * 50.0, ground_mask)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y


## O Terrain3D do mapa, procurado uma vez na cena em que a marca esta.
func _find_terrain() -> Node:
	if is_instance_valid(_terrain):
		return _terrain
	_terrain = null
	if not is_inside_tree():
		return null
	var root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if root == null:
		root = owner if owner != null else get_parent()
	_terrain = _search_terrain(root)
	return _terrain


func _search_terrain(node: Node) -> Node:
	if node == null:
		return null
	if node.is_class("Terrain3D"):
		return node
	for child: Node in node.get_children():
		var found: Node = _search_terrain(child)
		if found != null:
			return found
	return null


## O filho que carrega a malha; criado na hora se a marca virou um Path3D solto.
func _surface() -> MeshInstance3D:
	var node: MeshInstance3D = get_node_or_null(SURFACE_NAME) as MeshInstance3D
	if node == null:
		node = MeshInstance3D.new()
		node.name = SURFACE_NAME
		add_child(node)
		node.owner = owner if owner != null else self
	return node


func _apply_render_settings() -> void:
	var node: MeshInstance3D = get_node_or_null(SURFACE_NAME) as MeshInstance3D
	if node == null:
		return
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = visible_range
	node.visibility_range_end_margin = maxf(visible_range * 0.2, 10.0)
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Um bake por rajada de edicao, em vez de um por propriedade alterada.
func _schedule_bake() -> void:
	if not Engine.is_editor_hint() or not is_node_ready() or _bake_queued:
		return
	_bake_queued = true
	_run_queued_bake.call_deferred()


func _run_queued_bake() -> void:
	_bake_queued = false
	bake()
