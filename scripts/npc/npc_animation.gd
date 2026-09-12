class_name NPCAnimation
extends Node

## Dá Idle/Walk ao NPC. Os modelos Synty do projeto não trazem clipe embutido,
## então cada clipe da biblioteca em `Temporarios/Animations/Polygon/` é aberto
## uma vez, tem sua única `Animation` compartilhada entre bibliotecas locais
## e é tocado pelo `AnimationPlayer` do NPC — mesma técnica de
## `Temporarios/Animations/Meshes/testanim_animation_controller.gd`.
##
## As trilhas dos clipes são gravadas como `Skeleton3D:osso`, então isto só
## funciona com o rig para o qual a biblioteca foi feita
## (`Temporarios/Animations/Meshes/PolygonSyntyCharacter.fbx`, 50 ossos, em
## metros, com o `Skeleton3D` direto na raiz do modelo). O `AnimationPlayer`
## precisa ter `root_node` apontando para essa raiz.

@export var idle_clip: PackedScene
@export var walk_clip: PackedScene
@export var animation_player_path: NodePath

var _animation_player: AnimationPlayer
var _is_moving: bool = false

# Os clipes são imutáveis; tempo e velocidade continuam em cada AnimationPlayer.
static var _clip_cache: Dictionary[PackedScene, Animation] = {}


func _ready() -> void:
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if _animation_player == null:
		return
	_load_animation_library()
	if _animation_player.has_animation(&"Idle"):
		_animation_player.play(&"Idle")


## Chamado por `NPCActor` sempre que o NPC começa a andar ou para.
func set_moving(moving: bool) -> void:
	if _animation_player == null or moving == _is_moving:
		return
	_is_moving = moving
	var animation_name: StringName = &"Walk" if moving else &"Idle"
	if _animation_player.has_animation(animation_name):
		_animation_player.play(animation_name)


func _load_animation_library() -> void:
	var library: AnimationLibrary = AnimationLibrary.new()
	_add_clip(library, &"Idle", idle_clip)
	_add_clip(library, &"Walk", walk_clip)
	if library.get_animation_list().is_empty():
		return
	if _animation_player.has_animation_library(&""):
		_animation_player.remove_animation_library(&"")
	_animation_player.add_animation_library(&"", library)


func _add_clip(library: AnimationLibrary, animation_name: StringName, clip: PackedScene) -> void:
	if clip == null:
		return
	if _clip_cache.has(clip):
		library.add_animation(animation_name, _clip_cache[clip])
		return

	var source_root: Node = clip.instantiate()
	var source_player: AnimationPlayer = (
		source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	)
	if source_player == null or source_player.get_animation_list().is_empty():
		source_root.free()
		return

	var animation: Animation = (
		source_player.get_animation(source_player.get_animation_list()[0]).duplicate(true) as Animation
	)
	animation.loop_mode = Animation.LOOP_LINEAR
	_clip_cache[clip] = animation
	library.add_animation(animation_name, animation)
	source_root.free()
