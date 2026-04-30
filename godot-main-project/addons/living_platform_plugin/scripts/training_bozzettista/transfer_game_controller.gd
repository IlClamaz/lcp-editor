extends Node3D
class_name TransferGameController

@export var source_living_images: Array[LivingImage] = []
@export var living_image_keys: Dictionary = {}
@export var valid_pairs: Dictionary = {}
@export var living_camera: LivingCamera
@export var ray_length: float = 8.0
@export var hold_distance: float = 1.8
@export var token_scale: float = 0.35
@export var max_distance_from_source: float = 4.0
@export_group("HUD")
@export var hud_enabled: bool = true
@export var hud_offset: Vector3 = Vector3(0.0, -0.25, -0.9)
@export var hud_scale: float = 0.35
@export var hud_font_size: int = 8
@export var hud_font_depth: float = 0.002
@export var hud_instruction_text: String = "Click su un'immagine\npoi consegnala al telegrafo"
@export var hud_not_touching_text: String = "Avvicina l'immagine al telegrafo"
@export var hud_wrong_receiver_text: String = "Sbagliato!"
@export var hud_success_text: String = "Corretto!"
@export var debug_mode: bool = false

var _held_token: TransferGameToken
var _desktop_camera: Camera3D
var _hold_anchor: Node3D
var _hud: LivingCaptionStandaloneHud


func _ready() -> void:
	await _bind_runtime_references()
	_setup_hud()
	_show_hud(hud_instruction_text, 6.0)
	call_deferred("_remove_trigger_from_sources")


func _remove_trigger_from_sources() -> void:
	for image in _get_all_source_images():
		if image == null or not is_instance_valid(image):
			continue
		var trigger_node := image.find_child("Trigger", true, false)
		if trigger_node != null:
			trigger_node.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_grab_pressed_event(event):
		return

	if _held_token != null and is_instance_valid(_held_token):
		_try_place_held_token()
		return

	_try_grab_copy()


func _process(_delta: float) -> void:
	if _held_token == null or not is_instance_valid(_held_token):
		return
	if _hold_anchor == null or not is_instance_valid(_hold_anchor):
		_drop_token()
		return
	if _held_token.source_key == "":
		_drop_token()
		return

	var source_image := _find_source_image_by_key(_held_token.source_key)
	if source_image == null or not is_instance_valid(source_image):
		_drop_token()
		return

	var distance: float = _hold_anchor.global_position.distance_to(source_image.global_position)
	if distance > max_distance_from_source:
		if debug_mode:
			print("TransferGameController: token dropped (too far from source)")
		_drop_token()


func _is_grab_pressed_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed
	return false


func _bind_runtime_references() -> void:
	if living_camera == null:
		living_camera = get_parent().find_child("LivingCamera", true, false) as LivingCamera

	if _desktop_camera == null and living_camera != null:
		await get_tree().process_frame
		_desktop_camera = living_camera.get_real_camera_node() as Camera3D
		if _desktop_camera == null:
			_desktop_camera = living_camera.find_child("Camera3D", true, false) as Camera3D

	if _hold_anchor == null and _desktop_camera != null:
		_hold_anchor = _desktop_camera


func _try_grab_copy() -> void:
	if _desktop_camera == null:
		return
	if _hold_anchor == null:
		return

	var hit := _raycast_from_camera()
	if hit.is_empty():
		return

	var collider: Object = hit.get("collider")
	var source_image := _find_source_image_from_collider(collider)
	if source_image == null:
		return

	_create_held_token(source_image, _get_source_key(source_image))


func _create_held_token(source_image: LivingImage, source_key: String) -> void:
	_held_token = TransferGameToken.new()
	_held_token.name = "TransferGameToken"
	_held_token.hold_anchor = _hold_anchor
	_held_token.hold_distance = hold_distance
	_held_token.visual_scale = token_scale
	_held_token.source_key = source_key
	_held_token.configure_from_source(source_image)
	_held_token.consumed.connect(_on_token_consumed)
	get_tree().current_scene.add_child(_held_token)

	if debug_mode:
		print("TransferGameController: token grabbed")


func _drop_token() -> void:
	if _held_token == null:
		return
	if not is_instance_valid(_held_token):
		_held_token = null
		return

	_held_token.queue_free()
	_held_token = null

	if debug_mode:
		print("TransferGameController: token dropped")


func _try_place_held_token() -> void:
	if _held_token == null or not is_instance_valid(_held_token):
		return

	var receiver := _held_token.get_first_touching_receiver()
	if receiver == null:
		if debug_mode:
			print("TransferGameController: token not in contact with receiver")
		_show_hud(hud_not_touching_text, 1.5)
		return

	var required_receiver_key: String = str(valid_pairs.get(_held_token.source_key, ""))
	if required_receiver_key == "":
		if debug_mode:
			print("TransferGameController: missing valid pair for source_key=", _held_token.source_key)
		_show_hud("Mappa non configurata", 1.5)
		return

	if receiver.receiver_key != required_receiver_key:
		if debug_mode:
			print("TransferGameController: wrong receiver. expected=", required_receiver_key, " got=", receiver.receiver_key)
		_show_hud(hud_wrong_receiver_text, 1.5)
		return

	_show_hud(hud_success_text, 1.2)
	_held_token.consume_on_receiver(receiver)


func _on_token_consumed(_receiver: Node) -> void:
	if debug_mode:
		print("TransferGameController: token consumed by receiver")
	_held_token = null


func _raycast_from_camera() -> Dictionary:
	var from: Vector3 = _desktop_camera.global_position
	var to: Vector3 = from + (-_desktop_camera.global_transform.basis.z * ray_length)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _find_source_image_from_collider(collider: Object) -> LivingImage:
	if collider == null:
		return null

	var sources := _get_all_source_images()
	for source in sources:
		if source == null or not is_instance_valid(source):
			continue
		if collider == source:
			return source

		if not (collider is Node):
			continue

		var node := collider as Node
		while node != null:
			if node == source:
				return source
			node = node.get_parent()

	return null


func _get_all_source_images() -> Array[LivingImage]:
	var out: Array[LivingImage] = []
	for image in source_living_images:
		if image != null and is_instance_valid(image):
			out.append(image)
	return out


func _get_source_key(source_image: LivingImage) -> String:
	if source_image == null:
		return ""

	var key_by_name := living_image_keys.get(source_image.name, "")
	if str(key_by_name) != "":
		return str(key_by_name)

	return source_image.name


func _find_source_image_by_key(source_key: String) -> LivingImage:
	for source in _get_all_source_images():
		if _get_source_key(source) == source_key:
			return source
	return null


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


func _show_hud(text: String, auto_hide_after_s: float = 1.5) -> void:
	if not hud_enabled:
		return
	if _hud == null:
		return
	if _hold_anchor == null or not is_instance_valid(_hold_anchor):
		return

	if _hud.has_active_prompt():
		_hud.hide_hud()
	_hud.show_prompt(_hold_anchor, text, false, auto_hide_after_s)
