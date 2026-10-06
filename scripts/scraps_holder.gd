extends Node3D

@export var scrap_scenes: Array[PackedScene] = [
	preload("res://scenes/Spaceship_Scraps1.tscn"),
	preload("res://scenes/spaceship_Scraps2.tscn"),
	preload("res://scenes/Spaceship_Scraps3.tscn"),
	preload("res://scenes/Spaceship_Scraps4.tscn"),
	preload("res://scenes/Spaceship_Scraps5.tscn"),
	preload("res://scenes/Spaceship_Scraps6.tscn"),
	preload("res://scenes/Spaceship_Scraps7.tscn"),
]
@export_range(0.0, 4.0, 0.1) var cost_weight_power: float = 1.0
## Zero fills every marker; otherwise selects this many distinct locations.
@export_range(0, 1000) var spawn_count: int = 0
## Zero randomizes each run; a nonzero seed reproduces the same selection.
@export var generation_seed: int = 0

var _generated: bool = false


func _ready() -> void:
	ensure_generated()


func ensure_generated() -> void:
	if _generated:
		return
	_generated = true
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if generation_seed == 0:
		rng.randomize()
	else:
		rng.seed = generation_seed
	var scenes: Array[PackedScene] = []
	var weights: PackedFloat32Array = PackedFloat32Array()
	for scene: PackedScene in scrap_scenes:
		if scene == null:
			continue
		var sample: Node = scene.instantiate()
		if sample is RigidBody3D and sample.is_in_group(&"pickup_items"):
			var cost: float = maxf(float(sample.get("cash_value")), 1.0)
			scenes.append(scene)
			weights.append(1.0 / pow(cost, cost_weight_power))
		else:
			push_warning("ScrapsHolder requires RigidBody3D scenes in pickup_items.")
		sample.free()
	if scenes.is_empty():
		return
	var markers: Array[Marker3D] = []
	for child: Node in get_children():
		if child is Marker3D:
			markers.append(child as Marker3D)
	var count: int = markers.size() if spawn_count == 0 else mini(spawn_count, markers.size())
	for index: int in range(count):
		var marker_index: int = rng.randi_range(0, markers.size() - 1)
		var marker: Marker3D = markers[marker_index]
		markers.remove_at(marker_index)
		var scrap: RigidBody3D = scenes[rng.rand_weighted(weights)].instantiate() as RigidBody3D
		scrap.name = String(marker.name) + "Scrap"
		scrap.transform = marker.transform
		add_child(scrap)
