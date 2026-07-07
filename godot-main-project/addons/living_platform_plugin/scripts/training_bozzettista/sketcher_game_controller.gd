extends Node3D
class_name SketcherGameController

## Gioco bozzettista: prendi un'immagine dallo slideshow, portala al tecnigrafo.
## Input desktop: picking nativo su GrabZone / SketcherGameReceiver (puntatore visibile).
## Input VR: VRMouseRayInteractor → _input_event sugli stessi collider.

signal game_won
signal game_failed

@export var debug_mode: bool = false

@export_group("References")
@export var living_image_keys: Dictionary = {}  # LivingImage.name -> source_key (es. img_1)
@export var valid_pairs: Dictionary = {}        # source_key -> receiver_key | Array[receiver_key]
@export var reveal_elements: Array[SketcherGameRevealElement] = []
@export var success_events: Array[SketcherGameSuccessEvent] = []
@export var source_slideshow_element: LivingElement
@export var living_camera: LivingCamera

var source_slideshow: LivingSlideShow

@export_group("Gameplay")
@export var hold_distance: float = 1.8
@export var token_scale: float = 0.35
@export var max_distance_from_source: float = 4.0
@export var max_distance_to_receiver: float = 3.0
@export var max_trials: int = 3
@export var correct_placements_to_win: int = 2

@export_group("HUD")
@export var hud_enabled: bool = true
@export var hud_offset: Vector3 = Vector3(0.0, -0.25, -0.9)
@export var hud_scale: float = 0.35
@export var hud_font_size: int = 8
@export var hud_font_depth: float = 0.002
@export var hud_captured_text: String = "Image grabbed!"
@export var hud_released_text: String = "Image released!"
@export var hud_not_touching_text: String = "Bring the image closer to the machine"
@export var hud_success_text: String = "Correct!"
@export var hud_win_text: String = "Well done, you made it!"

var _held_token: SketcherGameToken
var _hold_anchor: Node3D
var _hud: LivingCaptionStandaloneHud
var _remaining_trials: int
var _correct_placements: int
var _game_won: bool
var _game_failed: bool
var _solved_source_keys: Dictionary = {}  # source_key -> true
var _reveal_engine := SketcherGameRevealEngine.new()

const _SLIDESHOW_PANEL_SCRIPT := preload(
	"res://addons/living_platform_plugin/scripts/training_bozzettista/sketcher_game_slideshow_panel.gd"
)


func _ready() -> void:
	_remaining_trials = max_trials
	_resolve_area_references()
	_resolve_source_slideshow()
	await _bind_camera()
	if source_slideshow != null:
		source_slideshow.rebuild_from_sources()
		call_deferred("_bind_slideshow_panel_inputs")
		call_deferred("_bind_receivers")
	if debug_mode and reveal_elements.is_empty() and success_events.is_empty():
		push_warning("SketcherGameController: nessuna configurazione reveal.")
	_reveal_engine.apply_initial_visibility(self, reveal_elements)
	_setup_hud()


func reset_game() -> void:
	_drop_token(false)
	_remaining_trials = max_trials
	_correct_placements = 0
	_game_won = false
	_game_failed = false
	_solved_source_keys.clear()
	_reveal_engine.apply_initial_visibility(self, reveal_elements)
	_reset_receivers()
	if _hud != null and _hud.has_active_prompt():
		_hud.hide_hud()
	if source_slideshow != null:
		source_slideshow.rebuild_from_sources()


func _reset_receivers() -> void:
	for node in find_children("*", "Area3D", true, false):
		if node is SketcherGameReceiver:
			var receiver := node as SketcherGameReceiver
			receiver.sketcher_game = self
			receiver.enable_receiving()


func _process(_delta: float) -> void:
	if _game_won:
		return
	if _held_token == null or not is_instance_valid(_held_token):
		return
	if _hold_anchor == null:
		_drop_token()
		return

	var source := _find_image_by_key(_held_token.source_key)
	if source == null:
		_drop_token()
		return
	if _hold_anchor.global_position.distance_to(source.global_position) > max_distance_from_source:
		_debug("token rilasciato: troppo lontano dalla sorgente")
		_drop_token()


# --- Input handlers (chiamati da _input_event sui collider) -----------------------

func handle_slideshow_panel_click() -> void:
	if _game_won or _game_failed:
		return
	if _held_token != null and is_instance_valid(_held_token):
		_try_slideshow_panel_swap()
	else:
		_try_slideshow_panel_grab()


func handle_receiver_click(receiver: SketcherGameReceiver) -> void:
	if receiver == null or receiver.sketcher_game != self:
		return
	if _game_won or _game_failed or _held_token == null or not is_instance_valid(_held_token):
		return
	_try_place_on_receiver(receiver)


# --- Grab / place -----------------------------------------------------------------

func _try_slideshow_panel_grab() -> void:
	if source_slideshow == null or _hold_anchor == null:
		return
	var image := source_slideshow.get_current_image()
	if image != null:
		_spawn_token(image)


func _try_slideshow_panel_swap() -> void:
	if source_slideshow == null:
		return
	var image := source_slideshow.get_current_image()
	var held_key := _held_token.source_key
	_drop_token()
	if image != null and _source_key_for(image) != held_key:
		_spawn_token(image)


func _try_place_on_receiver(receiver: SketcherGameReceiver) -> void:
	if _held_token == null:
		return
	if receiver == null or receiver.sketcher_game != self or not is_ancestor_of(receiver):
		return
	if not receiver.is_receiving_enabled():
		_debug("receiver non valido")
		_show_hud(hud_not_touching_text, 1.5)
		return
	if not _is_player_near_receiver(receiver):
		_debug("troppo lontano dal tecnigrafo")
		_show_hud(hud_not_touching_text, 1.5)
		return

	var source_image := _find_image_by_key(_held_token.source_key)
	if source_image == null or not _is_image_mapped(source_image):
		_handle_wrong_receiver()
		return

	var source_key := _held_token.source_key
	var valid_receiver_keys := _valid_receiver_keys_for(source_key)
	if valid_receiver_keys.is_empty():
		_debug("Mappa non configurata")
		return
	if receiver.receiver_key not in valid_receiver_keys:
		_handle_wrong_receiver()
		return
	if _solved_source_keys.has(source_key):
		_debug("immagine già consegnata")
		return

	_reveal_engine.apply_success_event(self, success_events, source_key, debug_mode)
	_disable_receivers_for_keys(valid_receiver_keys)
	_solved_source_keys[source_key] = true
	_held_token.consume_on_receiver(receiver)
	_correct_placements += 1
	if _correct_placements >= correct_placements_to_win:
		_on_game_won()
	else:
		_show_hud(hud_success_text, 1.2)
	LivingSceneManager.get_current_scene().play_sound(LivingConstants.AUDIO_SUCCESS)


func _bind_slideshow_panel_inputs() -> void:
	if source_slideshow == null:
		return
	for child in source_slideshow.get_children():
		if child is StaticBody3D and child.name != LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_NODE:
			_attach_slideshow_panel_input(child as StaticBody3D)


func _attach_slideshow_panel_input(body: StaticBody3D) -> void:
	if body.get_script() != _SLIDESHOW_PANEL_SCRIPT:
		body.set_script(_SLIDESHOW_PANEL_SCRIPT)
	body.sketcher_game = self


func _bind_receivers() -> void:
	for node in find_children("*", "Area3D", true, false):
		if node is SketcherGameReceiver:
			(node as SketcherGameReceiver).sketcher_game = self


func _on_game_won() -> void:
	if _game_won:
		return
	_game_won = true
	_show_hud(hud_win_text, 6.0)
	game_won.emit()


func _handle_wrong_receiver() -> void:
	if _game_failed:
		return
	_remaining_trials -= 1
	if _remaining_trials > 0:
		var suffix := "time" if _remaining_trials == 1 else "times"
		_show_hud("Failed \nYou can try again %d %s!" % [_remaining_trials, suffix], 5.0)
	else:
		_game_failed = true
		_show_hud("Failed!\n Go back to the ArchArch Zoetrope", 6.0)
		game_failed.emit()
	LivingSceneManager.get_current_scene().play_sound(LivingConstants.AUDIO_FAILURE)

func _spawn_token(image: LivingImage) -> void:
	_held_token = SketcherGameToken.new()
	_held_token.name = "SketcherGameToken"
	_held_token.sketcher_game = self
	_held_token.hold_anchor = _hold_anchor
	_held_token.hold_distance = hold_distance
	_held_token.visual_scale = token_scale
	_held_token.source_key = _source_key_for(image)
	_held_token.configure_from_source(image)
	_held_token.consumed.connect(func(_r): _held_token = null)
	var token_parent: Node = get_area_root()
	if token_parent == null:
		token_parent = self
	token_parent.add_child(_held_token)
	_show_hud(hud_captured_text, 1.2)
	_debug("token preso")


func _drop_token(show_feedback: bool = true) -> void:
	if _held_token != null and is_instance_valid(_held_token):
		_held_token.queue_free()
		if show_feedback:
			_show_hud(hud_released_text, 1.2)
	_held_token = null


# --- Area / riferimenti locali ----------------------------------------------------

func get_area_root() -> LivingArea:
	var node: Node = self
	while node != null:
		if node is LivingArea:
			return node as LivingArea
		node = node.get_parent()
	return null


func _resolve_area_references() -> void:
	var area := get_area_root()
	if area == null:
		return

	if source_slideshow_element == null:
		source_slideshow_element = _find_slideshow_element_in_area(area)

	if living_camera == null or not is_instance_valid(living_camera):
		var scene_root := get_tree().current_scene
		if scene_root != null:
			living_camera = scene_root.find_child("LivingCamera", true, false) as LivingCamera


func _find_slideshow_element_in_area(area: LivingArea) -> LivingElement:
	for child in area.get_children():
		if child is SketcherGameController:
			continue
		if not child is LivingElement:
			continue
		for grandchild in child.get_children():
			if grandchild is LivingSlideShow:
				return child as LivingElement
	return null


# --- Sorgenti immagine ------------------------------------------------------------

func _resolve_source_slideshow() -> void:
	source_slideshow = null
	if source_slideshow_element == null:
		return
	for child in source_slideshow_element.get_children():
		if child is LivingSlideShow:
			source_slideshow = child as LivingSlideShow
			return
	if debug_mode:
		push_warning(
			"SketcherGameController: nessun LivingSlideShow sotto '%s'."
			% source_slideshow_element.name
		)


func _slideshow_images() -> Array[LivingImage]:
	var out: Array[LivingImage] = []
	if source_slideshow == null:
		return out
	for image in source_slideshow.get_all_images():
		if image != null and is_instance_valid(image):
			out.append(image)
	return out


func _is_image_mapped(image: LivingImage) -> bool:
	if image == null:
		return false
	var mapped: Variant = living_image_keys.get(image.name, "")
	return str(mapped) != ""


func _source_key_for(image: LivingImage) -> String:
	var mapped: Variant = living_image_keys.get(image.name, "")
	return str(mapped) if str(mapped) != "" else image.name


func _find_image_by_key(key: String) -> LivingImage:
	for image in _slideshow_images():
		if _source_key_for(image) == key:
			return image
	return null


func _is_player_near_receiver(receiver: SketcherGameReceiver) -> bool:
	if _hold_anchor == null or receiver == null:
		return false
	return _hold_anchor.global_position.distance_to(receiver.global_position) <= max_distance_to_receiver


func _valid_receiver_keys_for(source_key: String) -> Array[String]:
	var raw: Variant = valid_pairs.get(source_key)
	var out: Array[String] = []
	if raw is Array:
		for item in raw:
			var key := str(item).strip_edges()
			if key != "" and key not in out:
				out.append(key)
		return out

	var single := str(raw).strip_edges()
	if single != "":
		out.append(single)
	return out


func _disable_receivers_for_keys(keys: Array[String]) -> void:
	for node in find_children("*", "Area3D", true, false):
		if node is SketcherGameReceiver:
			var receiver := node as SketcherGameReceiver
			if receiver.receiver_key in keys:
				receiver.disable_receiving()


# --- Camera / HUD -----------------------------------------------------------------

func _bind_camera() -> void:
	if living_camera == null or not is_instance_valid(living_camera):
		var scene_root := get_tree().current_scene
		if scene_root != null:
			living_camera = scene_root.find_child("LivingCamera", true, false) as LivingCamera
	if living_camera == null:
		return
	await get_tree().process_frame
	var camera := living_camera.get_real_camera_node() as Camera3D
	if camera == null:
		camera = living_camera.find_child("Camera3D", true, false) as Camera3D
	_hold_anchor = camera


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


func _show_hud(text: String, auto_hide_s: float = 1.5) -> void:
	if not hud_enabled or _hud == null or _hold_anchor == null:
		return
	if _hud.has_active_prompt():
		_hud.hide_hud()
	_hud.show_prompt(_hold_anchor, text, false, auto_hide_s)


func _debug(msg: String) -> void:
	if debug_mode:
		print("SketcherGameController: ", msg)
