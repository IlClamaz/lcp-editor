extends Node
class_name InputReader

## ===== Signals =====
signal move_event(dir: Vector2)
signal camera_move_event(delta: Vector2)

# Desktop movement (InputMap)
const A_MOVE_LEFT        := "ui_left"
const A_MOVE_RIGHT       := "ui_right"
const A_MOVE_UP          := "ui_up"
const A_MOVE_DOWN        := "ui_down"

# XR action map (see res://openxr_action_map.tres, action set "godot")
const XR_ACTION_SET := "godot"
@export var xr_move_action := "primary"    # left thumbstick

@export var left_controller: XRController3D

## ===== State =====
var _gameplay_enabled := true
var _prolog_command_enabled := true
var _allow_commands_in_prolog := true

# buffer for look from pad axes
var _look_axis := Vector2.ZERO

# (optional) auto-register missing actions with basic bindings
@export var auto_register_default_bindings := true

# XR
var _xr_interface: OpenXRInterface

func enable_gameplay_input() -> void:
	_gameplay_enabled = true

func disable_all_input() -> void:
	_gameplay_enabled = false
	_look_axis = Vector2.ZERO

# ===== API like in Unity =====
func enable_prolog_command() -> void:
	_prolog_command_enabled = true

func disable_prolog_command() -> void:
	_prolog_command_enabled = false

func disable_commands_in_prolog() -> void:
	_allow_commands_in_prolog = false

func enable_commands_in_prolog() -> void:
	_allow_commands_in_prolog = true

## ===== Continuous poll for Move + Look axes =====
func _process(_dt: float) -> void:
	if not _gameplay_enabled:
		return

	if _using_xr():
		# MOVE: left thumbstick
		var move := _xr_vec2(xr_move_action) # true = left
		move.y = -move.y
		emit_signal("move_event", move)
	else:
		# codice desktop come già avevi
		var move := Input.get_vector(A_MOVE_LEFT, A_MOVE_RIGHT, A_MOVE_UP, A_MOVE_DOWN)
		emit_signal("move_event", move)
		if _look_axis != Vector2.ZERO:
			emit_signal("camera_move_event", _look_axis)
			_look_axis = Vector2.ZERO


## ===== Discrete events (press/release, mouse delta) =====
func _unhandled_input(event: InputEvent) -> void:
	if not _gameplay_enabled:
		return

	# Camera (mouse)
	if event is InputEventMouseMotion:
		emit_signal("camera_move_event", event.relative)

func _using_xr() -> bool:
	if not _xr_interface:
		_xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	return _xr_interface and _xr_interface.is_initialized() and get_viewport().use_xr

func _xr_vec2(action_name: String) -> Vector2:
	var controller: XRController3D = left_controller
	if controller and controller.get_is_active():
		return controller.get_vector2(action_name)
	return Vector2.ZERO
