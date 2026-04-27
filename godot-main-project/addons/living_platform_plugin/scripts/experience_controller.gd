extends Node
class_name ExperienceController

@export var exit_portal: LivingPortal
@export var video_element: LivingElement
@export var living_camera: LivingCamera

@export_group("Exit Hold")
@export var hold_duration_s: float = 10.0
@export var trigger_threshold: float = 0.75

@export_group("HUD")
@export var hud_offset: Vector3
@export var hud_scale: float = 0.35
@export var hud_font_size: int = 8
@export var hud_font_depth: float = 0.002

const PROMPT_TEXT: String = "se tieni premuto 10 secondi\nesci dall'ambiente"
const GRIP_ACTIONS: PackedStringArray = ["grip_click", "grip"]
const EXIT_KEYBOARD_KEY: Key = KEY_S

var _video_360: LivingVideo360
var _camera_anchor: Node3D
var _left_controller: XRController3D
var _right_controller: XRController3D
var _confirm_hud: GestureConfirmHud
var _hold_elapsed_s: float = 0.0
var _transition_started: bool = false


func _ready() -> void:
	call_deferred("_setup_experience")


func _setup_experience() -> void:
	if is_instance_valid(exit_portal):
		exit_portal.visible = false
	else:
		push_warning("ExperienceController: exit_portal non assegnato.")

	_video_360 = _find_video_360(video_element)
	if _video_360:
		if not _video_360.on_video_finished.is_connected(_on_video_360_finished):
			_video_360.on_video_finished.connect(_on_video_360_finished)
		_video_360.play()
	else:
		push_warning("ExperienceController: nessun LivingVideo360 trovato sotto video_element.")

	_setup_camera_anchor()
	_setup_xr_controllers()
	_setup_confirm_hud()
	set_process(true)


func _process(delta: float) -> void:
	if _transition_started:
		return
	if not _is_ready_for_exit_input():
		_reset_hold_state()
		return

	if _are_exit_buttons_pressed():
		_hold_elapsed_s += delta
		_show_hold_hud()
		if _hold_elapsed_s >= hold_duration_s:
			_trigger_exit()
	else:
		_reset_hold_state()


func _find_video_360(root: Node) -> LivingVideo360:
	if not is_instance_valid(root):
		return null

	if root is LivingVideo360:
		return root as LivingVideo360

	var matches: Array[Node] = root.find_children("*", "LivingVideo360", true, false)
	if matches.is_empty():
		return null
	return matches[0] as LivingVideo360


func _setup_camera_anchor() -> void:
	if not is_instance_valid(living_camera):
		push_warning("ExperienceController: living_camera non assegnata.")
		return

	_camera_anchor = living_camera.get_real_camera_node()
	if not _camera_anchor:
		_camera_anchor = living_camera.find_child("XRCamera3D", true, false)
	if not _camera_anchor:
		_camera_anchor = living_camera.find_child("Camera3D", true, false)

	if not _camera_anchor:
		push_warning("ExperienceController: camera anchor non trovato su LivingCamera.")


func _setup_confirm_hud() -> void:
	_confirm_hud = GestureConfirmHud.new()
	_confirm_hud.hud_offset = hud_offset
	_confirm_hud.hud_scale = hud_scale
	_confirm_hud.hud_font_size = hud_font_size
	_confirm_hud.hud_font_depth = hud_font_depth
	_confirm_hud.cycle_multiline_text = true
	add_child(_confirm_hud)


func _is_ready_for_exit_input() -> bool:
	if not is_instance_valid(exit_portal):
		return false
	if not is_instance_valid(_camera_anchor):
		_setup_camera_anchor()
	if is_instance_valid(living_camera) and living_camera.using_xr:
		if not is_instance_valid(_left_controller) and not is_instance_valid(_right_controller):
			_setup_xr_controllers()
	return is_instance_valid(_camera_anchor)


func _are_exit_buttons_pressed() -> bool:
	var xr_pressed := false
	if is_instance_valid(living_camera) and living_camera.using_xr:
		xr_pressed = _is_vr_exit_combo_pressed()

	var keyboard_pressed := Input.is_physical_key_pressed(EXIT_KEYBOARD_KEY)
	return xr_pressed or keyboard_pressed


func _setup_xr_controllers() -> void:
	if not is_instance_valid(living_camera):
		return
	_left_controller = living_camera.find_child("XRController3D_left", true, false) as XRController3D
	_right_controller = living_camera.find_child("XRController3D_right", true, false) as XRController3D


func _is_vr_exit_combo_pressed() -> bool:
	var grip_pressed := _is_action_pressed(GRIP_ACTIONS)

	if is_instance_valid(_left_controller):
		grip_pressed = grip_pressed or _is_controller_action_pressed(_left_controller, "grip_click", "grip")

	if is_instance_valid(_right_controller):
		grip_pressed = grip_pressed or _is_controller_action_pressed(_right_controller, "grip_click", "grip")

	return grip_pressed


func _is_controller_action_pressed(controller: XRController3D, click_action: StringName, analog_action: StringName) -> bool:
	if not is_instance_valid(controller):
		return false
	if controller.is_button_pressed(click_action):
		return true
	if controller.get_float(click_action) >= 0.5:
		return true
	return controller.get_float(analog_action) >= trigger_threshold


func _is_action_pressed(candidates: PackedStringArray) -> bool:
	for action_name in candidates:
		if not InputMap.has_action(action_name):
			continue
		if Input.get_action_strength(action_name) >= trigger_threshold:
			return true
	return false


func _show_hold_hud() -> void:
	if not _confirm_hud or not _camera_anchor:
		return
	if _confirm_hud.has_active_prompt():
		return
	_confirm_hud.show_prompt(_camera_anchor, PROMPT_TEXT, false, -1.0)


func _reset_hold_state() -> void:
	_hold_elapsed_s = 0.0
	if _confirm_hud and _confirm_hud.has_active_prompt():
		_confirm_hud.hide_hud()


func _trigger_exit() -> void:
	_transition_started = true
	if _confirm_hud and _confirm_hud.has_active_prompt():
		_confirm_hud.hide_hud()

	if not is_instance_valid(exit_portal):
		return

	if is_instance_valid(living_camera):
		living_camera.fade_out(Color.WHITE_SMOKE, func():
			if is_instance_valid(exit_portal):
				exit_portal.switch_to_target_environment()
		)
	else:
		exit_portal.switch_to_target_environment()


func _on_video_360_finished() -> void:
	if is_instance_valid(living_camera):
		living_camera.fade_out(Color.WHITE_SMOKE, func():
			if is_instance_valid(exit_portal):
				exit_portal.switch_to_target_environment()
		)
	else:
		exit_portal.switch_to_target_environment()
	
