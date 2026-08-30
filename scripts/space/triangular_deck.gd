@tool
class_name TriangularDeck
extends MeshInstance3D

## Laje em prisma triangular equilatero -- o piso e o teto do interior da nave.
##
## Existe porque CylinderMesh NAO serve: pedir radial_segments = 3 nao produz um
## prisma triangular, o Godot eleva o valor para 4 em silencio e a laje sai
## losango. Como o losango fica girado 45 graus em relacao as paredes, os vidros
## atravessam o piso -- e nada no editor avisa que a propriedade foi ignorada.
##
## Os vertices ficam nos angulos 180/60/300, ou seja um vertice apontando para
## -Z e a aresta plana em +Z. Isso e o que casa com a planta do casco, cuja
## silhueta e um triangulo equilatero com o bico em -Z, e com as tres paredes,
## posicionadas a `circumradius / 2` com as normais externas em 0/120/240.

## Circunraio do triangulo. O inraio (distancia do centro a cada parede) e
## metade disto, porque num equilatero inraio = circunraio / 2.
@export var circumradius : float = 9.4 :
	set(value):
		circumradius = value
		_rebuild()

## Espessura da laje. Cresce para BAIXO a partir de y = 0, para o topo do piso
## coincidir com a origem do no.
@export var thickness : float = 0.05 :
	set(value):
		thickness = value
		_rebuild()

const VERTEX_ANGLES : Array[float] = [180.0, 60.0, 300.0]


func _ready() -> void:
	_rebuild()


func get_corners() -> PackedVector3Array:
	var corners : PackedVector3Array = PackedVector3Array()
	for angle : float in VERTEX_ANGLES:
		var radians : float = deg_to_rad(angle)
		corners.append(Vector3(
			sin(radians) * circumradius,
			0.0,
			cos(radians) * circumradius
		))
	return corners


func _rebuild() -> void:
	if circumradius <= 0.0 or thickness <= 0.0:
		return

	var top : PackedVector3Array = get_corners()
	var bottom : PackedVector3Array = PackedVector3Array()
	for corner : Vector3 in top:
		bottom.append(corner - Vector3(0.0, thickness, 0.0))

	var surface : SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Topo, visto de cima.
	_add_triangle(surface, top[0], top[2], top[1])
	# Base, vista de baixo.
	_add_triangle(surface, bottom[0], bottom[1], bottom[2])
	# Os tres cantos laterais, para a laje nao ficar oca de perfil.
	for index : int in range(3):
		var next : int = (index + 1) % 3
		_add_triangle(surface, top[index], bottom[index], bottom[next])
		_add_triangle(surface, top[index], bottom[next], top[next])

	surface.generate_normals()
	surface.generate_tangents()
	mesh = surface.commit()


func _add_triangle(
	surface : SurfaceTool,
	a : Vector3,
	b : Vector3,
	c : Vector3
) -> void:
	# UV planar em XZ: a textura do casco e um atlas sem direcao propria, entao
	# projetar de cima e o bastante e evita esticar nas laterais.
	for point : Vector3 in [a, b, c]:
		surface.set_uv(Vector2(point.x, point.z) * 0.25)
		surface.add_vertex(point)
