@tool
class_name TaperedShell
extends Node3D

## Deforma o revestimento interno para acompanhar o casco piramidal da nave.
## O piso permanece com a largura total e cada secao acima dele encolhe
## radialmente ate `top_radius_ratio` no teto.

@export var height: float = 2.45
@export_range(0.01, 1.0, 0.001) var top_radius_ratio: float = 0.09

var _deformed: bool = false


## Fator radial da secao na altura `height_above_deck`.
##
## A reta NAO e travada fora de [0, height] de proposito. As pecas do casco se
## sobrepoem mergulhando um pouco abaixo do piso e passando um pouco do teto,
## para que nenhum encontro fique num encosto exato -- e um encosto exato abre
## fresta, foi assim que a Terra aparecia na base da parede de fundo. Travar a
## reta faria a face interna dessas pecas virar uma corda que corta para fora
## do cone, reabrindo o vao justamente onde a sobreposicao deveria fechar.
func radial_scale(height_above_deck: float) -> float:
	return maxf(1.0 + (top_radius_ratio - 1.0) * height_above_deck / height, 0.001)


func _ready() -> void:
	_deform_meshes()
	_deform_collisions()


func _deform_meshes() -> void:
	if _deformed or height <= 0.0:
		return

	for child: Node in get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if mesh_instance.has_meta("tapered_shell_source_mesh"):
			continue

		var source: Mesh = mesh_instance.mesh

		var deformed: ArrayMesh = ArrayMesh.new()
		for surface_index: int in range(source.get_surface_count()):
			var arrays: Array = source.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for vertex_index: int in range(vertices.size()):
				var vertex: Vector3 = vertices[vertex_index]
				var shell_point: Vector3 = mesh_instance.transform * vertex
				var section_scale: float = radial_scale(shell_point.y)
				var radial_gradient: float = (top_radius_ratio - 1.0) / height
				if normals.size() == vertices.size():
					var normal: Vector3 = mesh_instance.basis * normals[vertex_index]
					var transformed_normal: Vector3 = Vector3(
						normal.x / section_scale,
						normal.y - radial_gradient * (
							shell_point.x * normal.x + shell_point.z * normal.z
						) / section_scale,
						normal.z / section_scale
					).normalized()
					normals[vertex_index] = (
						mesh_instance.basis.inverse() * transformed_normal
					).normalized()
				shell_point.x *= section_scale
				shell_point.z *= section_scale
				vertex = mesh_instance.transform.affine_inverse() * shell_point
				vertices[vertex_index] = vertex

			arrays[Mesh.ARRAY_VERTEX] = vertices
			if normals.size() == vertices.size():
				arrays[Mesh.ARRAY_NORMAL] = normals
			deformed.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES,
				arrays
			)
			var material: Material = source.surface_get_material(surface_index)
			if material != null:
				deformed.surface_set_material(deformed.get_surface_count() - 1, material)

		mesh_instance.set_meta("tapered_shell_source_mesh", source)
		mesh_instance.mesh = deformed

	_deformed = true


func _deform_collisions() -> void:
	var body: StaticBody3D = get_node_or_null("Body") as StaticBody3D
	if body == null:
		return

	for child: Node in body.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision == null or collision.shape == null:
			continue
		if collision.has_meta("tapered_shell_source_shape"):
			continue

		var box: BoxShape3D = collision.shape as BoxShape3D
		if box == null:
			if collision.name == "RoofShape":
				_deform_roof_shape(collision)
			continue

		var points: PackedVector3Array = PackedVector3Array()
		var half_size: Vector3 = box.size * 0.5
		for x: float in [-half_size.x, half_size.x]:
			for y: float in [-half_size.y, half_size.y]:
				for z: float in [-half_size.z, half_size.z]:
					var shell_point: Vector3 = collision.transform * Vector3(x, y, z)
					var section_scale: float = radial_scale(shell_point.y)
					shell_point.x *= section_scale
					shell_point.z *= section_scale
					# ConvexPolygonShape3D espera pontos no espaco local do
					# CollisionShape3D. Manter `shell_point` aqui aplicaria o
					# transform da parede uma segunda vez no servidor de fisica.
					points.append(collision.transform.affine_inverse() * shell_point)

		var tapered_shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
		tapered_shape.points = points
		collision.set_meta("tapered_shell_source_shape", box)
		collision.shape = tapered_shape


func _deform_roof_shape(collision: CollisionShape3D) -> void:
	var convex: ConvexPolygonShape3D = collision.shape as ConvexPolygonShape3D
	if convex == null:
		return

	var points: PackedVector3Array = PackedVector3Array()
	for point: Vector3 in convex.points:
		var shell_point: Vector3 = collision.transform * point
		var section_scale: float = radial_scale(shell_point.y)
		shell_point.x *= section_scale
		shell_point.z *= section_scale
		points.append(collision.transform.affine_inverse() * shell_point)

	var tapered_shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	tapered_shape.points = points
	collision.set_meta("tapered_shell_source_shape", convex)
	collision.shape = tapered_shape
