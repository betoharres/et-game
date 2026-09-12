extends Control

const SCAN_INTERVAL : float = 0.3
const SIGNAL_COLOR : Color = Color(0.65, 0.95, 1.0)
const NEAR_COLOR : Color = Color(1.0, 0.78, 0.4)
const MUTED_COLOR : Color = Color(0.37, 0.49, 0.55)
const STATUS : Array[String] = ["SEM SINAL", "SINAL FRACO", "SINAL DISTANTE", "SINAL MODERADO", "SINAL FORTE", "SINAL MUITO PRÓXIMO"]
const BEARINGS : Array[String] = ["À frente", "À frente / direita", "À direita", "Atrás / direita", "Atrás", "Atrás / esquerda", "À esquerda", "À frente / esquerda"]
const DIAL_CENTER : Vector2 = Vector2(60.0, 62.0)

var character : Node3D
var _detector : DebrisLocator = DebrisLocator.new()
var _equipment_id : int = 0
var _scan_time : float = 0.0
var _strength : int = 0
var _sector : int = -1
var _nearby : bool = false
var _angle : float = 0.0
var _pulse : float = 0.0
var _panel_style : StyleBoxFlat

@onready var _status : Label = $Status
@onready var _hint : Label = $Hint


func _ready() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.025, 0.04, 0.055, 0.92)
	_panel_style.border_color = Color(0.3, 0.58, 0.64, 0.55)
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(8)
	_panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.2)
	_panel_style.shadow_size = 4
	hide()


func _process(delta : float) -> void:
	if get_tree().paused:
		return
	var equipment : AlienTechnologyItem = _selected_equipment()
	if equipment == null:
		if _equipment_id != 0:
			_detector.reset()
		_equipment_id = 0
		hide()
		return
	if equipment.get_instance_id() != _equipment_id:
		_equipment_id = equipment.get_instance_id()
		_detector.reset()
		_scan_time = 0.0
		_pulse = 0.0
	show()
	_scan_time -= delta
	if _scan_time <= 0.0:
		_scan_time = SCAN_INTERVAL
		_apply_reading(_detector.sample(character))
	if _sector >= 0:
		_angle = lerp_angle(_angle, float(_sector) * DebrisLocator.SECTOR_SIZE, 1.0 - exp(-12.0 * delta))
	var period : float = lerpf(1.8, 0.5, float(_strength) / 5.0)
	_pulse = fposmod(_pulse + delta / period, 1.0)
	queue_redraw()


func _selected_equipment() -> AlienTechnologyItem:
	if not is_instance_valid(character) or not character.is_inside_tree() or not character.is_visible_in_tree():
		return null
	if character.has_method("get_health") and float(character.call("get_health")) <= 0.0:
		return null
	var inventory : Node = character.get_node_or_null("ExplorationInventory")
	if inventory == null:
		return null
	var equipment : AlienTechnologyItem = inventory.call("item_at", int(inventory.get("selected_slot"))) as AlienTechnologyItem
	if not is_instance_valid(equipment) or equipment.is_queued_for_deletion():
		return null
	if equipment.definition == null or not equipment.definition.is_locator or equipment.state != AlienTechnologyItem.State.INVENTORY:
		return null
	return equipment


func _apply_reading(reading : Dictionary) -> void:
	var previous_sector : int = _sector
	_strength = int(reading["strength"])
	_sector = int(reading["sector"])
	_nearby = bool(reading["nearby"])
	if previous_sector < 0 and _sector >= 0:
		_angle = float(_sector) * DebrisLocator.SECTOR_SIZE
	_status.text = STATUS[_strength]
	_status.modulate = NEAR_COLOR if _nearby else SIGNAL_COLOR
	if _strength == 0:
		_status.modulate = MUTED_COLOR
		_hint.text = "Nenhuma tecnologia detectada"
	elif _nearby:
		_hint.text = "Sinal saturado · Procure ao redor"
	elif _sector < 0:
		_hint.text = "Direção indefinida · Observe o entorno"
	else:
		_hint.text = "%s · Em relação ao ET" % BEARINGS[_sector]


func _draw() -> void:
	if _panel_style == null:
		return
	draw_style_box(_panel_style, Rect2(Vector2.ZERO, size))
	var color : Color = NEAR_COLOR if _nearby else SIGNAL_COLOR
	draw_arc(DIAL_CENTER, 33.0, 0.0, TAU, 64, MUTED_COLOR, 1.0, true)
	for index : int in range(8):
		var axis : Vector2 = Vector2.UP.rotated(float(index) * PI / 4.0)
		draw_line(DIAL_CENTER + axis * 36.0, DIAL_CENTER + axis * 39.0, MUTED_COLOR, 1.0, true)
	draw_circle(DIAL_CENTER, 2.5, MUTED_COLOR, true, -1.0, true)
	if _strength > 0:
		draw_arc(DIAL_CENTER, lerpf(10.0, 32.0, _pulse), 0.0, TAU, 48, Color(color, (1.0 - _pulse) * 0.3), 1.0, true)
	if _sector >= 0:
		var bearing : float = _angle - PI / 2.0
		draw_arc(DIAL_CENTER, 33.0, bearing - PI / 8.0, bearing + PI / 8.0, 16, color, 4.0, true)
		var arrow : PackedVector2Array = PackedVector2Array()
		for point : Vector2 in [Vector2(0, -25), Vector2(7, -9), Vector2(0, -12), Vector2(-7, -9)]:
			arrow.append(DIAL_CENTER + point.rotated(_angle))
		draw_colored_polygon(arrow, color)
	elif _strength > 0:
		draw_arc(DIAL_CENTER, 26.0, 0.0, TAU, 64, Color(color, 0.6 + 0.3 * sin(_pulse * TAU)), 2.0, true)
	for index : int in range(5):
		var point : Vector2 = Vector2(209.0 + float(index) * 22.0, 85.0)
		draw_circle(point, 5.0, color if index < _strength else Color(0.17, 0.24, 0.28), true, -1.0, true)
