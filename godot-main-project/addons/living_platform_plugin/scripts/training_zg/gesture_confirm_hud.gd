extends Node
class_name GestureConfirmHud

signal confirmed

@export var hud_offset: Vector3 = Vector3(0.0, -0.35, -0.8)
@export var hud_scale: float = 0.35
@export var hud_x_rot_degs: float = 0.0
@export var hud_font_size: int = 8
@export var hud_font_depth: float = 0.002
@export var cycle_multiline_text: bool = true
@export var line_delay_s: float = 2.5

var _hud: LivingCaptionHud
const MIN_VISIBLE_SCALE: float = 0.01
const SHOW_TWEEN_DURATION: float = 0.35
var _hud_lines: PackedStringArray = []
var _hud_line_index: int = 0
var _hud_timer: Timer = null
var _auto_hide_timer: Timer = null
var _is_clickable: bool = true


func _ready() -> void:
	_ensure_timer()


func show_prompt(
		anchor: Node3D,
		text: String = "Corretto!",
		clickable: bool = true,
		auto_hide_after_s: float = -1.0
	) -> bool:
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
	_set_prompt_text(text)

	_is_clickable = clickable
	if _is_clickable and not _hud.clicked.is_connected(_on_hud_clicked):
		_hud.clicked.connect(_on_hud_clicked)
	elif not _is_clickable and _hud.clicked.is_connected(_on_hud_clicked):
		_hud.clicked.disconnect(_on_hud_clicked)

	_setup_auto_hide(auto_hide_after_s)

	var tween := _hud.create_tween().set_parallel(true)
	tween.tween_property(_hud, "position", hud_offset, SHOW_TWEEN_DURATION)
	tween.tween_property(_hud, "scale", Vector3(hud_scale, hud_scale, hud_scale), SHOW_TWEEN_DURATION)

	return true


func hide_hud() -> void:
	if not _hud:
		return

	if _hud_timer:
		_hud_timer.stop()
	if _auto_hide_timer:
		_auto_hide_timer.stop()
	_hud_lines = []
	_hud_line_index = 0
	_is_clickable = true

	if _hud.clicked.is_connected(_on_hud_clicked):
		_hud.clicked.disconnect(_on_hud_clicked)

	_hud.fade_out()
	_hud = null

func has_active_prompt() -> bool:
	return _hud != null


func _on_hud_clicked() -> void:
	confirmed.emit()


func _ensure_timer() -> void:
	if _hud_timer:
		return

	_hud_timer = Timer.new()
	_hud_timer.one_shot = false
	_hud_timer.autostart = false
	add_child(_hud_timer)
	_hud_timer.timeout.connect(_on_hud_timer_timeout)

	if _auto_hide_timer == null:
		_auto_hide_timer = Timer.new()
		_auto_hide_timer.one_shot = true
		_auto_hide_timer.autostart = false
		add_child(_auto_hide_timer)
		_auto_hide_timer.timeout.connect(_on_auto_hide_timer_timeout)


func _set_prompt_text(text: String) -> void:
	if not _hud:
		return

	_ensure_timer()
	_hud_lines = text.split("\n", false)
	if _hud_lines.is_empty():
		_hud_lines = PackedStringArray([text])
	_hud_line_index = 0

	_show_next_line()

	if cycle_multiline_text and _hud_lines.size() > 1 and _hud_timer:
		_hud_timer.stop()
		_hud_timer.wait_time = max(line_delay_s, 0.1)
		_hud_timer.start()
	elif _hud_timer:
		_hud_timer.stop()


func _show_next_line() -> void:
	if not _hud:
		return
	if _hud_lines.is_empty():
		_hud.set_display_text("")
		return

	if _hud_line_index >= _hud_lines.size():
		_hud_line_index = 0

	var line := _hud_lines[_hud_line_index].strip_edges()
	_hud_line_index += 1
	_hud.set_display_text(line)


func _on_hud_timer_timeout() -> void:
	if not _hud:
		return
	_show_next_line()


func _setup_auto_hide(auto_hide_after_s: float) -> void:
	_ensure_timer()
	if not _auto_hide_timer:
		return

	_auto_hide_timer.stop()
	if auto_hide_after_s > 0.0:
		_auto_hide_timer.wait_time = auto_hide_after_s
		_auto_hide_timer.start()


func _on_auto_hide_timer_timeout() -> void:
	hide_hud()
