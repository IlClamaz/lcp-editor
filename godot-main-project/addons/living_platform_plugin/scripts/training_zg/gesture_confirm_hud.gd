extends Node
class_name GestureConfirmHud

signal confirmed

@export var hud_offset: Vector3 = Vector3(0.0, -0.35, -0.8)
@export var hud_scale: float = 0.35
@export var hud_x_rot_degs: float = 0.0
@export var hud_font_size: int = 8
@export var hud_font_depth: float = 0.002

var _hud: LivingCaptionHud
const MIN_VISIBLE_SCALE: float = 0.01
const SHOW_TWEEN_DURATION: float = 0.35


func show_prompt(anchor: Node3D, text: String = "Corretto!") -> bool:
	if _hud:
		return false

	if not anchor:
		return false

	_hud = LivingCaptionHud.new(false)
	_hud.name = "GestureConfirmHud"
	anchor.add_child(_hud)

	var start_offset := Vector3(hud_offset.x, 0.0, hud_offset.z)
	_hud.position = start_offset
	_hud.rotation_degrees = Vector3(hud_x_rot_degs, 0.0, 0.0)
	_hud.scale = Vector3(MIN_VISIBLE_SCALE, MIN_VISIBLE_SCALE, MIN_VISIBLE_SCALE)

	_hud.set_font_size(hud_font_size)
	_hud.set_font_depth(hud_font_depth)
	_hud.set_display_text(text)

	if not _hud.clicked.is_connected(_on_hud_clicked):
		_hud.clicked.connect(_on_hud_clicked)

	var tween := _hud.create_tween().set_parallel(true)
	tween.tween_property(_hud, "position", hud_offset, SHOW_TWEEN_DURATION)
	tween.tween_property(_hud, "scale", Vector3(hud_scale, hud_scale, hud_scale), SHOW_TWEEN_DURATION)

	return true


func hide_hud() -> void:
	if not _hud:
		return

	if _hud.clicked.is_connected(_on_hud_clicked):
		_hud.clicked.disconnect(_on_hud_clicked)

	_hud.fade_out()
	_hud = null

func has_active_prompt() -> bool:
	return _hud != null


func _on_hud_clicked() -> void:
	confirmed.emit()
