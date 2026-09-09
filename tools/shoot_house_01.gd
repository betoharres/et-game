@tool
extends SceneTree

## Fotografa a House01 para inspeção visual: fachada, laterais, telhado e os
## quatro cômodos por dentro.
##
## Não é validação -- quem decide se ficou bom é quem olha. Precisa de
## rasterização real, então roda SEM `--headless`:
##
##     .\tools\godot.cmd --path . --script res://tools/shoot_house_01.gd --resolution 1280x720

const SCENE: String = "res://scenes/Buildings/HouseTest.tscn"

## Alvo, de onde olhar e o nome do arquivo.
const SHOTS: Array[Dictionary] = [
	{"at": Vector3(2.5, 1.5, 10.0), "from": Vector3(2.5, 3.0, 20.0), "name": "fachada"},
	{"at": Vector3(2.5, 2.0, 5.0), "from": Vector3(16.0, 6.0, 18.0), "name": "frente-lateral"},
	{"at": Vector3(2.5, 2.0, 5.0), "from": Vector3(-12.0, 5.0, -6.0), "name": "fundo-lateral"},
	{"at": Vector3(2.5, 2.5, 5.0), "from": Vector3(2.5, 22.0, 5.1), "name": "telhado-de-cima"},
	{"at": Vector3(3.7, 1.5, 10.0), "from": Vector3(3.7, 1.6, 14.5), "name": "porta-de-fora"},
	{"at": Vector3(2.5, 1.2, 6.0), "from": Vector3(3.5, 1.6, 9.6), "name": "sala"},
	{"at": Vector3(1.2, 0.8, 1.0), "from": Vector3(1.6, 1.6, 4.5), "name": "quarto"},
	{"at": Vector3(4.8, 0.9, 4.2), "from": Vector3(2.8, 1.6, 2.9), "name": "cozinha"},
	{"at": Vector3(3.7, 1.0, 0.8), "from": Vector3(3.7, 1.6, 2.4), "name": "banheiro"},
]
const WARMUP_FRAMES: int = 60
const SETTLE_FRAMES: int = 8

var _camera: Camera3D
var _frame: int = 0
var _shot: int = 0
var _out: String = ""


func _init() -> void:
	_out = OS.get_environment("HOUSE_SHOT_DIR")
	if _out.is_empty():
		_out = "user://house_shots"
	DirAccess.make_dir_recursive_absolute(_out)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var packed: PackedScene = load(SCENE) as PackedScene
		if packed == null:
			printerr("Nao carregou %s" % SCENE)
			quit(1)
			return true
		root.add_child(packed.instantiate())
		_camera = Camera3D.new()
		_camera.far = 400.0
		_camera.fov = 62.0
		root.add_child(_camera)
		_camera.make_current()
		_aim()
		return false
	if _frame < WARMUP_FRAMES:
		return false
	if (_frame - WARMUP_FRAMES) % SETTLE_FRAMES != 0:
		return false
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%02d-%s.png" % [_out, _shot + 1, SHOTS[_shot]["name"]]
	if image == null or image.save_png(path) != OK:
		printerr("Nao gravou %s" % path)
		quit(1)
		return true
	print("Foto: %s" % path)
	_shot += 1
	if _shot >= SHOTS.size():
		quit(0)
		return true
	_aim()
	return false


func _aim() -> void:
	var shot: Dictionary = SHOTS[_shot]
	_camera.global_position = shot["from"]
	_camera.look_at(shot["at"], Vector3.UP)
