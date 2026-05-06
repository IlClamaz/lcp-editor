@tool
extends MeshInstance3D
class_name LivingSlideShow

@export var source_elements: Array[LivingElement] = []
@export var auto_hide_source_elements: bool = true
@export var loop_slides: bool = true

var pixel_size: float = 0.01

@export var diagonal: float = 1.0:
	set(value):
		diagonal = max(value, 0.01)
		if is_node_ready():
			_update_appearance()

# --- Parametro per la Curvatura ---
@export var curvature: float = 0.0 :
	set(v):
		curvature = v
		if is_node_ready():
			_update_appearance()


@onready var _viewport: SubViewport = $"SlideShow-SubViewport"
@onready var _texture_rect: TextureRect = $"SlideShow-SubViewport/TextureRect"
@onready var _controls: Node3D = $"Controls"

var _slides: Array[LivingImage] = []
var _current_index: int = -1
const CURVE_SEGMENTS: int = 32
const BASE_PANEL_SIZE: Vector2 = Vector2(2.0, 2.0)
const BASE_VIEWPORT_SIZE: Vector2i = Vector2i(1024, 1024)
const CONTROLS_OFFSET_Y: float = -1.25
const BACKGROUND_THICKNESS_PROP: float = 0.01
const TRIGGER_MIN_DEPTH: float = 5.0

var background: MeshInstance3D = null
var face_collision_shape: CollisionShape3D = null
var trigger_collision_shape: CollisionShape3D = null
var grab_zone_collision_shape: CollisionShape3D = null


func _ready() -> void:
	_ensure_collision_nodes()
	_update_appearance()
	_collect_slides_from_sources()
	_show_initial_slide()


func next_slide() -> void:
	if _slides.is_empty():
		return
	if _current_index < _slides.size() - 1:
		_current_index += 1
	elif loop_slides:
		_current_index = 0
	_refresh_slide_texture()


func prev_slide() -> void:
	if _slides.is_empty():
		return
	if _current_index > 0:
		_current_index -= 1
	elif loop_slides:
		_current_index = _slides.size() - 1
	_refresh_slide_texture()


func go_to_slide(index: int) -> void:
	if _slides.is_empty():
		return
	if index < 0 or index >= _slides.size():
		return
	_current_index = index
	_refresh_slide_texture()


func get_current_image() -> LivingImage:
	if _current_index < 0 or _current_index >= _slides.size():
		return null
	return _slides[_current_index]


func get_current_texture() -> Texture2D:
	var image := get_current_image()
	if image == null:
		return null
	return image.current_texture


func get_current_image_path() -> String:
	var image := get_current_image()
	if image == null:
		return ""
	return image.image_path


func get_all_images() -> Array[LivingImage]:
	var out: Array[LivingImage] = []
	for image in _slides:
		if image != null and is_instance_valid(image):
			out.append(image)
	return out


func rebuild_from_sources() -> void:
	_collect_slides_from_sources()
	_show_initial_slide()


func _collect_slides_from_sources() -> void:
	_slides.clear()
	for element in source_elements:
		if element == null or not is_instance_valid(element):
			continue

		if auto_hide_source_elements:
			element.visible = false

		var image := _find_living_image_in_element(element)
		if image != null:
			_slides.append(image)


func _find_living_image_in_element(element: LivingElement) -> LivingImage:
	for child in element.get_children():
		if child is LivingImage:
			return child as LivingImage
	return null


func _show_initial_slide() -> void:
	if _slides.is_empty():
		_texture_rect.texture = null
		_current_index = -1
		return
	_current_index = 0
	_refresh_slide_texture()


func _refresh_slide_texture() -> void:
	var texture := get_current_texture()
	_texture_rect.texture = texture


func _rebuild_panel_mesh() -> void:
	var target_size := _get_effective_panel_size()
	mesh = _generate_curved_plane(target_size.x, target_size.y, curvature)
	_apply_panel_collision_size()


func _update_appearance() -> void:
	_rebuild_panel_mesh()
	_apply_viewport_size()
	_update_controls_position()


func _apply_panel_collision_size() -> void:
	if face_collision_shape == null:
		return
	var shape := face_collision_shape.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		face_collision_shape.shape = shape
	var target_size := _get_effective_panel_size()
	var background_depth := target_size.x * BACKGROUND_THICKNESS_PROP
	shape.size = Vector3(target_size.x, target_size.y, background_depth)

	if background != null:
		var box := background.mesh as BoxMesh
		if box == null:
			box = BoxMesh.new()
			background.mesh = box
		box.size = Vector3(target_size.x, target_size.y, background_depth)
		background.position = Vector3(0, 0, -1.01 * background_depth / 2.0)

	if trigger_collision_shape != null:
		var trigger_shape := trigger_collision_shape.shape as BoxShape3D
		if trigger_shape == null:
			trigger_shape = BoxShape3D.new()
			trigger_collision_shape.shape = trigger_shape
		var trigger_depth := max(target_size.y / 2.0, TRIGGER_MIN_DEPTH)
		trigger_shape.size = Vector3(target_size.x, 0.2, trigger_depth)
		trigger_collision_shape.position = Vector3(0, 0, trigger_depth / 2.0)
		trigger_collision_shape.global_position.y = 0.1

	if grab_zone_collision_shape != null:
		var grab_shape := grab_zone_collision_shape.shape as BoxShape3D
		if grab_shape == null:
			grab_shape = BoxShape3D.new()
			grab_zone_collision_shape.shape = grab_shape
		var panel_aabb := mesh.get_aabb() if mesh != null else AABB(Vector3(-target_size.x * 0.5, -target_size.y * 0.5, 0.0), Vector3(target_size.x, target_size.y, 0.001))
		var grab_depth := max(background_depth * 0.25, 0.005)
		grab_shape.size = Vector3(panel_aabb.size.x, panel_aabb.size.y, grab_depth)
		# Keep the grab zone strictly on the panel surface, not around controls.
		grab_zone_collision_shape.position = Vector3(panel_aabb.position.x + panel_aabb.size.x * 0.5, panel_aabb.position.y + panel_aabb.size.y * 0.5, panel_aabb.position.z + grab_depth * 0.5)


func _apply_viewport_size() -> void:
	if _viewport:
		_viewport.size = BASE_VIEWPORT_SIZE


func _update_controls_position() -> void:
	if _controls:
		var target_size := _get_effective_panel_size()
		_controls.position.y = CONTROLS_OFFSET_Y * (target_size.y / max(BASE_PANEL_SIZE.y, 0.001))


func _get_effective_panel_size() -> Vector2:
	var native := Vector2(BASE_VIEWPORT_SIZE)
	var native_diagonal := native.length()
	if native_diagonal > 0.0:
		var mapped_pixel_size := diagonal / native_diagonal
		return native * mapped_pixel_size
	return BASE_PANEL_SIZE


func _ensure_collision_nodes() -> void:
	if background != null and face_collision_shape != null and trigger_collision_shape != null and grab_zone_collision_shape != null:
		return

	background = MeshInstance3D.new()
	background.mesh = BoxMesh.new()

	face_collision_shape = CollisionShape3D.new()
	face_collision_shape.name = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE
	face_collision_shape.shape = BoxShape3D.new()

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
	trigger_collision_shape.shape = BoxShape3D.new()
	trigger_body.add_child(trigger_collision_shape)
	add_child(trigger_body)

	# Dedicated collider for slideshow grab: only this zone should allow token generation.
	var grab_body := StaticBody3D.new()
	grab_body.name = "GrabZone"
	grab_body.collision_layer = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
	grab_body.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
	grab_zone_collision_shape = CollisionShape3D.new()
	grab_zone_collision_shape.shape = BoxShape3D.new()
	grab_body.add_child(grab_zone_collision_shape)
	add_child(grab_body)


func _generate_curved_plane(w: float, h: float, curve_deg: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var is_flat = abs(curve_deg) <= 0.01
	var dir = -sign(curve_deg) if curve_deg != 0 else 1.0
	var angle_rad := 0.0
	var radius := 0.0

	if not is_flat:
		angle_rad = deg_to_rad(abs(curve_deg))
		radius = w / angle_rad
		angle_rad = w / radius

	var get_v = func(i: int, y: float):
		var u = float(i) / CURVE_SEGMENTS
		var x = 0.0
		var z = 0.0
		if is_flat:
			x = lerp(-w / 2.0, w / 2.0, u)
		else:
			var current_angle = lerp(-angle_rad / 2.0, angle_rad / 2.0, u)
			x = sin(current_angle) * radius
			z = (cos(current_angle) * radius - radius) * dir
		return Vector3(x, y, z)

	var y_top := h / 2.0
	var y_bot := -h / 2.0

	st.set_smooth_group(1)
	for i in range(CURVE_SEGMENTS):
		var tl = get_v.call(i, y_top)
		var tr = get_v.call(i + 1, y_top)
		var bl = get_v.call(i, y_bot)
		var br = get_v.call(i + 1, y_bot)
		var u_left := float(i) / CURVE_SEGMENTS
		var u_right := float(i + 1) / CURVE_SEGMENTS

		st.set_uv(Vector2(u_left, 1.0)); st.add_vertex(bl)
		st.set_uv(Vector2(u_right, 1.0)); st.add_vertex(br)
		st.set_uv(Vector2(u_right, 0.0)); st.add_vertex(tr)

		st.set_uv(Vector2(u_left, 1.0)); st.add_vertex(bl)
		st.set_uv(Vector2(u_right, 0.0)); st.add_vertex(tr)
		st.set_uv(Vector2(u_left, 0.0)); st.add_vertex(tl)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()
