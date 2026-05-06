extends Node3D
class_name TransferGameController

@export var debug_mode: bool = false

@export_group("REFERENCES")
@export var source_living_images: Array[LivingImage] = []
@export var living_image_keys: Dictionary = {}
@export var valid_pairs: Dictionary = {}
@export var reveal_show_by_source_key: Dictionary = {}
@export var reveal_hide_by_source_key: Dictionary = {}
@export var reveal_elements_by_source_key: Dictionary = {}
@export var source_slideshow: LivingSlideShow
@export var living_camera: LivingCamera

@export_group("SETTINGS")
@export var ray_length: float = 8.0
@export var hold_distance: float = 1.8
@export var token_scale: float = 0.35
@export var max_distance_from_source: float = 4.0
@export var max_trials: int = 3

@export_group("HUD")
@export var hud_enabled: bool = true
@export var hud_offset: Vector3 = Vector3(0.0, -0.25, -0.9)
@export var hud_scale: float = 0.35
@export var hud_font_size: int = 8
@export var hud_font_depth: float = 0.002

@export_group("TEXTS")
@export var hud_instruction_text: String = "Click su un'immagine\npoi consegnala al telegrafo"
@export var hud_not_touching_text: String = "Avvicina l'immagine al telegrafo"
@export var hud_wrong_receiver_text: String = "Sbagliato!"
@export var hud_success_text: String = "Corretto!"

var _held_token: TransferGameToken
var _desktop_camera: Camera3D
var _hold_anchor: Node3D
var _hud: LivingCaptionStandaloneHud
var _remaining_trials: int = max_trials


func _ready() -> void:
	await _bind_runtime_references()
	_refresh_sources_from_slideshow()
	if debug_mode and reveal_show_by_source_key.is_empty() and reveal_hide_by_source_key.is_empty() and reveal_elements_by_source_key.is_empty():
		push_warning("TransferGameController: reveal dictionaries are empty. No reveal/show-hide actions will happen.")
	_apply_initial_reveal_elements_visibility()
	_setup_hud()
	_show_hud(hud_instruction_text, 6.0)


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

	var mouse_hit := _raycast_from_mouse()
	var center_hit := _raycast_from_center()
	if mouse_hit.is_empty() or center_hit.is_empty():
		return

	var mouse_collider: Object = mouse_hit.get("collider")
	var center_collider: Object = center_hit.get("collider")

	# Se usiamo uno slideshow come source, il grab è valido solo cliccando il pannello slideshow.
	if source_slideshow != null and is_instance_valid(source_slideshow):
		if _is_slideshow_grab_zone_hit(mouse_hit) and _is_slideshow_grab_zone_hit(center_hit):
			var current_image := source_slideshow.get_current_image()
			if current_image != null and is_instance_valid(current_image):
				_create_held_token(current_image, _get_source_key(current_image))
		return

	var mouse_source := _find_source_image_from_collider(mouse_collider)
	var center_source := _find_source_image_from_collider(center_collider)
	if mouse_source == null or center_source == null:
		return
	if mouse_source != center_source:
		return

	_create_held_token(mouse_source, _get_source_key(mouse_source))


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
		_remaining_trials -= 1
		if _remaining_trials > 0:
			var tries_suffix: String = "volta" if _remaining_trials == 1 else "volte"
			_show_hud(
				"Fallito!\nPuoi riprovarci ancora %d %s!" % [_remaining_trials, tries_suffix],
				5.0
			)
		else:
			await get_tree().create_timer(6.0).timeout
			# _trigger_portal_transition(stargate_coreography)
			_show_hud("Fallito! \n Torna al Capannone Scenografie", 6.0)
		return

	_apply_reveal_for_source_key(_held_token.source_key)
	_show_hud(hud_success_text, 1.2)
	
	_held_token.consume_on_receiver(receiver)


func _on_token_consumed(_receiver: Node) -> void:
	if debug_mode:
		print("TransferGameController: token consumed by receiver")
	_held_token = null


func _raycast_from_mouse() -> Dictionary:
	if _desktop_camera == null:
		return {}
	var mouse_pos: Vector2 = _desktop_camera.get_viewport().get_mouse_position()
	var mouse_from: Vector3 = _desktop_camera.project_ray_origin(mouse_pos)
	var mouse_to: Vector3 = mouse_from + (_desktop_camera.project_ray_normal(mouse_pos) * ray_length)
	var mouse_query := PhysicsRayQueryParameters3D.create(mouse_from, mouse_to)
	mouse_query.collide_with_areas = true
	mouse_query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(mouse_query)


func _raycast_from_center() -> Dictionary:
	if _desktop_camera == null:
		return {}
	var center_from: Vector3 = _desktop_camera.global_position
	var center_to: Vector3 = center_from + (-_desktop_camera.global_transform.basis.z * ray_length)
	var center_query := PhysicsRayQueryParameters3D.create(center_from, center_to)
	center_query.collide_with_areas = true
	center_query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(center_query)


func _find_source_image_from_collider(collider: Object) -> LivingImage:
	if collider == null:
		return null

	var sources := _get_all_source_images()
	for source in sources:
		if source == null or not is_instance_valid(source):
			continue
		# Non permettere grab da source non visibili (es. repository nascosto dietro slideshow).
		if not source.is_visible_in_tree():
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


func _is_slideshow_collider(collider: Object) -> bool:
	if source_slideshow == null or not is_instance_valid(source_slideshow):
		return false
	if collider == null:
		return false

	if collider == source_slideshow:
		return true
	if not (collider is Node):
		return false

	var node := collider as Node
	while node != null:
		if node == source_slideshow:
			return true
		node = node.get_parent()
	return false


func _is_slideshow_grab_zone_hit(hit: Dictionary) -> bool:
	if source_slideshow == null or not is_instance_valid(source_slideshow):
		return false
	if hit.is_empty():
		return false

	var collider: Object = hit.get("collider")
	if not _is_slideshow_collider(collider):
		return false
	if not (collider is Node):
		return false

	var node := collider as Node
	while node != null:
		var lowered := String(node.name).to_lower()
		if lowered == "prevbutton" or lowered == "nextbutton" or lowered == "controls":
			return false
		if lowered == LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_NODE.to_lower():
			return false
		if lowered == "grabzone" or lowered == "panelhitbody":
			return true
		if node == source_slideshow:
			return false
		node = node.get_parent()

	return false




func _get_all_source_images() -> Array[LivingImage]:
	var from_slideshow := _get_source_images_from_slideshow()
	if not from_slideshow.is_empty():
		return from_slideshow

	var out: Array[LivingImage] = []
	for image in source_living_images:
		if image != null and is_instance_valid(image):
			out.append(image)
	return out


func _refresh_sources_from_slideshow() -> void:
	if source_slideshow == null or not is_instance_valid(source_slideshow):
		return
	source_slideshow.rebuild_from_sources()


func _get_source_images_from_slideshow() -> Array[LivingImage]:
	var out: Array[LivingImage] = []
	if source_slideshow == null or not is_instance_valid(source_slideshow):
		return out

	for image in source_slideshow.get_all_images():
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


func _apply_initial_reveal_elements_visibility() -> void:
	# Nuovo comportamento:
	# - tutto ciò che può essere mostrato al successo parte nascosto
	# - tutto ciò che può essere nascosto al successo parte visibile
	for source_key in reveal_show_by_source_key.keys():
		_set_targets_visibility(reveal_show_by_source_key[source_key], false)
	for source_key in reveal_hide_by_source_key.keys():
		_set_targets_visibility(reveal_hide_by_source_key[source_key], true)

	# Retrocompatibilità: vecchio campo (single target da mostrare)
	for source_key in reveal_elements_by_source_key.keys():
		var element := _resolve_reveal_element(reveal_elements_by_source_key[source_key])
		if element != null:
			element.visible = false


func _apply_reveal_for_source_key(source_key: String) -> void:
	# Nuovo: mostra un array di target
	if reveal_show_by_source_key.has(source_key):
		_set_targets_visibility(reveal_show_by_source_key[source_key], true)

	# Nuovo: nasconde un array di target
	if reveal_hide_by_source_key.has(source_key):
		_set_targets_visibility(reveal_hide_by_source_key[source_key], false)

	# Retrocompatibilità: vecchio campo (single target da mostrare)
	var raw_value = reveal_elements_by_source_key.get(source_key, null)
	var element := _resolve_reveal_element(raw_value)
	if element != null:
		element.visible = true


func _set_targets_visibility(raw_targets: Variant, is_visible: bool) -> void:
	for target in _normalize_targets_array(raw_targets):
		target.visible = is_visible


func _normalize_targets_array(raw_targets: Variant) -> Array[LivingElement]:
	var out: Array[LivingElement] = []
	if raw_targets is Array:
		for raw_target in raw_targets:
			var element := _resolve_reveal_element(raw_target)
			if element != null:
				out.append(element)
	else:
		# Supporta anche valore singolo per comodità.
		var single := _resolve_reveal_element(raw_targets)
		if single != null:
			out.append(single)
	return out


func _resolve_reveal_element(raw_value: Variant) -> LivingElement:
	if raw_value is LivingElement:
		var direct := raw_value as LivingElement
		if is_instance_valid(direct):
			return direct
		return null

	if raw_value is NodePath:
		var path := raw_value as NodePath
		if path.is_empty():
			return null
		var node := get_node_or_null(path)
		if node is LivingElement and is_instance_valid(node):
			return node as LivingElement

	return null

