@tool
extends MeshInstance3D
class_name LivingSlideShow

@export var source_elements: Array[Node] = []
@export var auto_hide_source_elements: bool = true
@export var loop_slides: bool = true
@export var slide_transition_enabled: bool = true
@export_range(0.05, 2.0, 0.01) var slide_transition_duration: float = 0.45
@export_range(0.0, 1.0, 0.01) var slide_transition_fade_min_alpha: float = 0.25
@export var frame_model_path: String = "":
	set(value):
		frame_model_path = value
		if is_node_ready():
			_reload_frame_model()

@export var frame_opening_reference_size: Vector2 = Vector2(0.70710677, 0.70710677):
	set(value):
		frame_opening_reference_size = Vector2(max(value.x, 0.001), max(value.y, 0.001))
		if is_node_ready():
			_update_frame_transform()

@export_range(0.0, 0.05, 0.0001) var frame_surface_offset: float = 0.003:
	set(value):
		frame_surface_offset = max(value, 0.0)
		if is_node_ready():
			_update_frame_transform()

@export var diagonal: float = 1.0:
	set(value):
		diagonal = max(value, 0.01)
		if is_node_ready():
			_update_appearance()

@export var curvature: float = 0.0:
	set(value):
		curvature = value
		if is_node_ready():
			_update_appearance()

@export_range(-5.0, 0.0, 0.01) var controls_offset_y: float = -1.5:
	set(value):
		controls_offset_y = clamp(value, -5.0, 0.0)
		if is_node_ready():
			_update_controls_position()

@onready var _viewport: SubViewport = $"SlideShow-SubViewport"
@onready var _texture_rect: TextureRect = $"SlideShow-SubViewport/TextureRect"
@onready var _controls: Node3D = $"Controls"

var _slides: Array[LivingImage] = []
var _current_index: int = -1
var _is_transitioning: bool = false
var _incoming_texture_rect: TextureRect = null
var _frame_model: Living3DModel = null

var background: MeshInstance3D = null
var face_collision_shape: CollisionShape3D = null
var trigger_collision_shape: CollisionShape3D = null
var grab_zone_collision_shape: CollisionShape3D = null

const CURVE_SEGMENTS := 32
const BASE_PANEL_SIZE := Vector2(2.0, 2.0)
const BASE_VIEWPORT_SIZE := Vector2i(1024, 1024)
const BACKGROUND_THICKNESS_PROP := 0.01
const TRIGGER_MIN_DEPTH := 5.0


func _enter_tree() -> void:
	var host := get_parent()
	if host != null and host.has_signal("build_finished"):
		host.build_finished.connect(_on_host_build_finished)


func _exit_tree() -> void:
	var host := get_parent()
	if host != null and host.has_signal("build_finished") and host.build_finished.is_connected(_on_host_build_finished):
		host.build_finished.disconnect(_on_host_build_finished)


func _ready() -> void:
	_ensure_transition_texture_rect()
	_ensure_collision_nodes()
	_reload_frame_model()
	_update_appearance()
	if source_elements.is_empty():
		call_deferred("_try_bind_from_host_components")
	else:
		rebuild_from_sources()


func _on_host_build_finished(_success: bool) -> void:
	call_deferred("_try_bind_from_host_components")


func _try_bind_from_host_components() -> void:
	var host := get_parent()
	if host == null:
		return
	var component_ids: Variant = host.get("components")
	if typeof(component_ids) != TYPE_ARRAY or component_ids.is_empty():
		return

	var elements: Array = []
	for comp_id in component_ids:
		for sibling in host.get_children():
			if sibling == self:
				continue
			var script: Script = sibling.get_script()
			if script == null or script.get_global_name() != "LivingElement":
				continue
			if int(sibling.get("item_id")) == int(comp_id):
				elements.append(sibling)
				break

	if not elements.is_empty():
		bind_source_elements(elements)


func bind_source_elements(elements: Array) -> void:
	source_elements.clear()
	for element in elements:
		if element is Node and is_instance_valid(element):
			source_elements.append(element)
	rebuild_from_sources()


func rebuild_from_sources() -> void:
	_slides.clear()
	for element in source_elements:
		if element == null or not is_instance_valid(element):
			continue
		if auto_hide_source_elements:
			element.visible = false
		for child in element.get_children():
			if child is LivingImage:
				_slides.append(child)
				break

	if _slides.is_empty():
		_texture_rect.texture = null
		_current_index = -1
		return
	_current_index = 0
	_apply_current_texture()


func next_slide() -> void:
	_change_slide(1)


func prev_slide() -> void:
	_change_slide(-1)


func go_to_slide(index: int) -> void:
	if _slides.is_empty() or _is_transitioning:
		return
	if index < 0 or index >= _slides.size() or index == _current_index:
		return
	_show_slide(index, index > _current_index)


func get_current_image() -> LivingImage:
	if _current_index < 0 or _current_index >= _slides.size():
		return null
	return _slides[_current_index]


func get_all_images() -> Array[LivingImage]:
	var out: Array[LivingImage] = []
	for image in _slides:
		if image != null and is_instance_valid(image):
			out.append(image)
	return out


func _change_slide(direction: int) -> void:
	if _slides.is_empty() or _is_transitioning:
		return
	var index := _current_index + direction
	if index < 0:
		if not loop_slides:
			return
		index = _slides.size() - 1
	elif index >= _slides.size():
		if not loop_slides:
			return
		index = 0
	_show_slide(index, direction > 0)


func _show_slide(target_index: int, forward: bool) -> void:
	if not slide_transition_enabled or slide_transition_duration <= 0.0:
		_current_index = target_index
		_apply_current_texture()
		return

	_ensure_transition_texture_rect()
	var incoming_texture := _slides[target_index].current_texture if _slides[target_index] != null else null
	if _incoming_texture_rect == null or incoming_texture == null:
		_current_index = target_index
		_apply_current_texture()
		return

	_is_transitioning = true
	var dir := -1.0 if forward else 1.0
	var width := maxf(_texture_rect.size.x, float(BASE_VIEWPORT_SIZE.x))
	var fade_min := clampf(slide_transition_fade_min_alpha, 0.0, 1.0)

	_texture_rect.position = Vector2.ZERO
	_texture_rect.modulate = Color.WHITE
	_incoming_texture_rect.texture = incoming_texture
	_incoming_texture_rect.position = Vector2(dir * width, 0.0)
	_incoming_texture_rect.modulate = Color(1.0, 1.0, 1.0, fade_min)
	_incoming_texture_rect.visible = true

	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(_texture_rect, "position:x", -dir * width, slide_transition_duration)
	tween.parallel().tween_property(_incoming_texture_rect, "position:x", 0.0, slide_transition_duration)
	tween.parallel().tween_property(_texture_rect, "modulate:a", fade_min, slide_transition_duration)
	tween.parallel().tween_property(_incoming_texture_rect, "modulate:a", 1.0, slide_transition_duration)
	tween.finished.connect(func():
		_current_index = target_index
		_texture_rect.texture = incoming_texture
		_texture_rect.position = Vector2.ZERO
		_texture_rect.modulate = Color.WHITE
		_incoming_texture_rect.texture = null
		_incoming_texture_rect.position = Vector2.ZERO
		_incoming_texture_rect.modulate = Color.WHITE
		_incoming_texture_rect.visible = false
		_is_transitioning = false
	, CONNECT_ONE_SHOT)


func _apply_current_texture() -> void:
	var image := get_current_image()
	_texture_rect.texture = image.current_texture if image != null else null
	if _incoming_texture_rect != null:
		_incoming_texture_rect.texture = null


func _ensure_transition_texture_rect() -> void:
	if _incoming_texture_rect != null and is_instance_valid(_incoming_texture_rect):
		return
	_incoming_texture_rect = _texture_rect.duplicate() as TextureRect
	_incoming_texture_rect.name = "IncomingTextureRect"
	_incoming_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_incoming_texture_rect.visible = false
	_viewport.add_child(_incoming_texture_rect)


func _reload_frame_model() -> void:
	if _frame_model != null and is_instance_valid(_frame_model):
		remove_child(_frame_model)
		_frame_model.queue_free()
		_frame_model = null

	var path := frame_model_path.strip_edges()
	var ext := path.get_extension().to_lower()
	if path == "" or ext not in ["glb", "gltf"] or not ResourceLoader.exists(path):
		if path != "" and not ResourceLoader.exists(path):
			push_warning("LivingSlideShow '%s': frame model not found at '%s'." % [name, path])
		if background != null:
			background.visible = true
		return

	_frame_model = Living3DModel.new()
	_frame_model.name = "LivingSlideShowFrame"
	_frame_model.model_path = path
	add_child(_frame_model)
	move_child(_frame_model, 0)
	if Engine.is_editor_hint() and owner != null:
		_frame_model.owner = owner
	if background != null:
		background.visible = false
	call_deferred("_update_frame_transform")
	call_deferred("_disable_frame_collisions")


func _disable_frame_collisions() -> void:
	if _frame_model == null or not is_instance_valid(_frame_model):
		return
	for body in _frame_model.find_children("*", "CollisionObject3D", true, false):
		var collision_obj := body as CollisionObject3D
		collision_obj.collision_layer = 0
		collision_obj.collision_mask = 0


func _update_appearance() -> void:
	var panel_size := _get_panel_size()
	mesh = _generate_curved_plane(panel_size.x, panel_size.y, curvature)
	_update_collisions(panel_size)
	_apply_viewport_material()
	_update_controls_position()
	_update_frame_transform()


func _update_frame_transform() -> void:
	if _frame_model == null:
		return
	var panel_size := _get_panel_size()
	var ref := frame_opening_reference_size
	_frame_model.scale = Vector3(panel_size.x / ref.x, panel_size.y / ref.y, 1.0)
	var center := mesh.get_aabb().get_center() if mesh != null else Vector3.ZERO
	_frame_model.position = center + Vector3(0.0, 0.0, frame_surface_offset)


func _apply_viewport_material() -> void:
	if _viewport == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _viewport.get_texture()
	mat.resource_local_to_scene = true
	set_surface_override_material(0, mat)


func _update_collisions(panel_size: Vector2) -> void:
	if face_collision_shape == null:
		return

	var depth := panel_size.x * BACKGROUND_THICKNESS_PROP
	_set_box_shape(face_collision_shape, Vector3(panel_size.x, panel_size.y, depth))

	if background != null:
		var box := background.mesh as BoxMesh
		if box == null:
			box = BoxMesh.new()
			background.mesh = box
		box.size = Vector3(panel_size.x, panel_size.y, depth)
		background.position = Vector3(0.0, 0.0, -1.01 * depth / 2.0)

	if trigger_collision_shape != null:
		var trigger_depth := maxf(panel_size.y / 2.0, TRIGGER_MIN_DEPTH)
		_set_box_shape(trigger_collision_shape, Vector3(panel_size.x, 0.2, trigger_depth))
		trigger_collision_shape.position = Vector3(0.0, 0.0, trigger_depth / 2.0)
		trigger_collision_shape.global_position.y = 0.1

	if grab_zone_collision_shape != null:
		var panel_aabb := mesh.get_aabb() if mesh != null else AABB(
			Vector3(-panel_size.x * 0.5, -panel_size.y * 0.5, 0.0),
			Vector3(panel_size.x, panel_size.y, 0.001)
		)
		var grab_depth := maxf(panel_size.x * 0.02, 0.02)
		_set_box_shape(grab_zone_collision_shape, Vector3(panel_aabb.size.x, panel_aabb.size.y, grab_depth))
		var center := panel_aabb.get_center()
		grab_zone_collision_shape.position = center + Vector3(0.0, 0.0, frame_surface_offset + grab_depth * 0.5)


func _set_box_shape(node: CollisionShape3D, size: Vector3) -> void:
	var shape := node.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		node.shape = shape
	shape.size = size


func _update_controls_position() -> void:
	if _controls == null:
		return
	var panel_size := _get_panel_size()
	_controls.position.y = controls_offset_y * (panel_size.y / maxf(BASE_PANEL_SIZE.y, 0.001))


func _get_panel_size() -> Vector2:
	var native := Vector2(BASE_VIEWPORT_SIZE)
	var native_diagonal := native.length()
	if native_diagonal <= 0.0:
		return BASE_PANEL_SIZE
	return native * (diagonal / native_diagonal)


func _ensure_collision_nodes() -> void:
	if background != null:
		return

	background = MeshInstance3D.new()
	background.mesh = BoxMesh.new()
	face_collision_shape = CollisionShape3D.new()
	face_collision_shape.name = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE

	var face_body := StaticBody3D.new()
	face_body.collision_layer = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
	face_body.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
	face_body.add_child(background)
	face_body.add_child(face_collision_shape)
	add_child(face_body)

	var trigger_body := StaticBody3D.new()
	trigger_body.name = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_NODE
	trigger_body.collision_layer = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
	trigger_body.collision_mask = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
	trigger_collision_shape = CollisionShape3D.new()
	trigger_body.add_child(trigger_collision_shape)
	add_child(trigger_body)

	var grab_body := StaticBody3D.new()
	grab_body.name = "GrabZone"
	grab_body.collision_layer = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
	grab_body.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
	grab_zone_collision_shape = CollisionShape3D.new()
	grab_body.add_child(grab_zone_collision_shape)
	add_child(grab_body)


func _generate_curved_plane(w: float, h: float, curve_deg: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var is_flat := absf(curve_deg) <= 0.01
	var dir := -signf(curve_deg) if curve_deg != 0.0 else 1.0
	var angle_rad := 0.0
	var radius := 0.0
	if not is_flat:
		angle_rad = deg_to_rad(absf(curve_deg))
		radius = w / angle_rad
		angle_rad = w / radius

	var get_v := func(i: int, y: float) -> Vector3:
		var u := float(i) / float(CURVE_SEGMENTS)
		if is_flat:
			return Vector3(lerpf(-w / 2.0, w / 2.0, u), y, 0.0)
		var current_angle := lerpf(-angle_rad / 2.0, angle_rad / 2.0, u)
		return Vector3(
			sin(current_angle) * radius,
			y,
			(cos(current_angle) * radius - radius) * dir
		)

	var y_top := h / 2.0
	var y_bot := -h / 2.0
	st.set_smooth_group(1)
	for i in CURVE_SEGMENTS:
		var u_left := float(i) / float(CURVE_SEGMENTS)
		var u_right := float(i + 1) / float(CURVE_SEGMENTS)
		var tl := get_v.call(i, y_top)
		var tr := get_v.call(i + 1, y_top)
		var bl := get_v.call(i, y_bot)
		var br := get_v.call(i + 1, y_bot)

		st.set_uv(Vector2(u_left, 1.0)); st.add_vertex(bl)
		st.set_uv(Vector2(u_right, 1.0)); st.add_vertex(br)
		st.set_uv(Vector2(u_right, 0.0)); st.add_vertex(tr)
		st.set_uv(Vector2(u_left, 1.0)); st.add_vertex(bl)
		st.set_uv(Vector2(u_right, 0.0)); st.add_vertex(tr)
		st.set_uv(Vector2(u_left, 0.0)); st.add_vertex(tl)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()
