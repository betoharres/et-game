extends Node3D

@export_multiline var text: String = "WELCOME"
@export var randomize_text: bool = true
@export var face_camera: bool = true
@export var face_camera_yaw_offset: float = PI
@export var near_distance: float = 3.0
@export var far_distance: float = 12.0
@export var transition_duration: float = 1.2

@onready var text_viewport: SubViewport = $TextViewport
@onready var text_label: Label = $TextViewport/Text
@onready var display: Node3D = $Display
@onready var circle_mesh: MeshInstance3D = $Display/AlienCircle
@onready var text_mesh: MeshInstance3D = $Display/ReadableText

var morph_progress: float = 0.0

const SAMPLE_TEXTS: Array[String] = [
	"WELCOME",
	"DO NOT ENTER",
	"THEY TOOK MY COW",
	"POWER CORE",
	"FOLLOW THE RIVER",
	"WE ARE WATCHING",
	"HELP",
]

func _ready() -> void:
	if randomize_text:
		text = SAMPLE_TEXTS[randi() % SAMPLE_TEXTS.size()]
	text_label.text = text
	text_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	var circle_material: ShaderMaterial = circle_mesh.material_override as ShaderMaterial
	var text_material: ShaderMaterial = text_mesh.material_override as ShaderMaterial
	if circle_material:
		circle_material.set_shader_parameter("morph_progress", morph_progress)
	if text_material:
		text_material.set_shader_parameter("text_texture", text_viewport.get_texture())
		text_material.set_shader_parameter("morph_progress", morph_progress)

func _process(delta: float) -> void:
	var circle_material: ShaderMaterial = circle_mesh.material_override as ShaderMaterial
	var text_material: ShaderMaterial = text_mesh.material_override as ShaderMaterial
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		var distance_to_camera: float = camera.global_position.distance_to(display.global_position)
		var target_morph: float = clamp(inverse_lerp(far_distance, near_distance, distance_to_camera), 0.0, 1.0)
		morph_progress = move_toward(morph_progress, target_morph, delta / max(transition_duration, 0.01))
		if face_camera:
			var target: Vector3 = camera.global_position
			target.y = display.global_position.y
			display.look_at(target, Vector3.UP)
			display.rotate_y(face_camera_yaw_offset)

	if circle_material:
		circle_material.set_shader_parameter("morph_progress", morph_progress)
	if text_material:
		text_material.set_shader_parameter("morph_progress", morph_progress)

	circle_mesh.rotate_z(delta * 0.10)

func set_text(value: String) -> void:
	text = value
	if is_node_ready():
		text_label.text = text
		text_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
