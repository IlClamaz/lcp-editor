extends Node3D
class_name SketcherGameCoordinator

signal training_completed
signal training_failed

@export var debug_mode: bool = false
@export var game_controllers: Array[SketcherGameController] = []
@export var stargates_to_hide_at_start: Array[LivingElement] = []
@export var stargates_to_show_at_end: Array[LivingElement] = []
@export var living_camera: LivingCamera

@export_group("HUD")
@export var hud_enabled: bool = true
@export var hud_offset: Vector3 = Vector3(0.0, -0.25, -0.9)
@export var hud_scale: float = 0.35
@export var hud_font_size: int = 8
@export var hud_font_depth: float = 0.002
@export_multiline var hud_instruction_text: String = ""
@export var hud_instruction_duration_s: float = 6.0

var _hold_anchor: Node3D
var _hud: LivingCaptionStandaloneHud
var _won_controllers: Dictionary = {}
var _training_finished: bool = false
var _initialized: bool = false


func _ready() -> void:
	_bind_controllers()
	await _bind_camera()
	_setup_hud()
	_initialized = true
	_hide_stargates(stargates_to_hide_at_start)
	_begin_session()


func _enter_tree() -> void:
	if not _initialized:
		return
	_begin_session()


func _begin_session() -> void:
	_won_controllers.clear()
	_training_finished = false
	_reset_all_controllers()
	call_deferred("_refresh_session_hud")


func _reset_all_controllers() -> void:
	for controller in game_controllers:
		if controller == null or not is_instance_valid(controller):
			continue
		controller.reset_game()


func _refresh_session_hud() -> void:
	_refresh_hold_anchor()
	_show_instruction_hud()


func _refresh_hold_anchor() -> void:
	if living_camera == null or not is_instance_valid(living_camera):
		var scene_root := get_tree().current_scene
		if scene_root != null:
			living_camera = scene_root.find_child("LivingCamera", true, false) as LivingCamera
	if living_camera == null:
		_hold_anchor = null
		return
	var camera := living_camera.get_real_camera_node() as Camera3D
	if camera == null:
		camera = living_camera.find_child("Camera3D", true, false) as Camera3D
	_hold_anchor = camera


func _bind_controllers() -> void:
	for i in game_controllers.size():
		var controller := game_controllers[i]
		if controller == null:
			continue
		controller.game_won.connect(_on_controller_won.bind(controller, i))
		controller.game_failed.connect(_on_controller_failed.bind(controller))


func _on_controller_won(controller: SketcherGameController, index: int) -> void:
	if _training_finished:
		return
	if controller == null or not is_instance_valid(controller):
		return

	_won_controllers[controller.get_instance_id()] = true

	if not _all_controllers_won():
		return

	_training_finished = true
	_show_stargates(stargates_to_show_at_end)
	LivingEventManager.notify_training_completed()
	training_completed.emit()
	_debug("tutti i minigiochi completati.")


func _on_controller_failed(_controller: SketcherGameController) -> void:
	if _training_finished:
		return
	_training_finished = true
	LivingEventManager.notify_training_failed()
	training_failed.emit()
	_debug("minigioco fallito, training terminato.")


func _all_controllers_won() -> bool:
	var expected := 0
	for controller in game_controllers:
		if controller == null or not is_instance_valid(controller):
			continue
		expected += 1
		if not _won_controllers.has(controller.get_instance_id()):
			return false
	return expected > 0


func _hide_stargates(portals: Array[LivingElement]) -> void:
	for portal in portals:
		if portal != null and is_instance_valid(portal):
			portal.hide()


func _show_stargates(portals: Array[LivingElement]) -> void:
	for portal in portals:
		if portal != null and is_instance_valid(portal):
			portal.show()


func _bind_camera() -> void:
	_refresh_hold_anchor()
	if _hold_anchor == null:
		return
	await get_tree().process_frame
	_refresh_hold_anchor()


func _setup_hud() -> void:
	if not hud_enabled:
		return
	_hud = LivingCaptionStandaloneHud.new()
	_hud.hud_offset = hud_offset
	_hud.hud_scale = hud_scale
	_hud.hud_font_size = hud_font_size
	_hud.hud_font_depth = hud_font_depth
	_hud.cycle_multiline_text = true
	add_child(_hud)


func _show_instruction_hud() -> void:
	if not hud_enabled or _hud == null or _hold_anchor == null:
		return
	_hud.show_prompt(_hold_anchor, hud_instruction_text, false, hud_instruction_duration_s)


func _debug(msg: String) -> void:
	if debug_mode:
		print("SketcherGameCoordinator: ", msg)
