@tool
extends LivingVisitableObject
class_name LivingTargetObject

# Scene-owned visit target for Area / Environment (not an Omeka item).
# item_id stays 0; bound_item_id mirrors the parent Area/Environment id.
# Draws a colored floor border around the LivingTarget medium.

@export_group("TARGET")
## Omeka id of the Area/Environment this node targets. Used when item_id == 0.
@export var bound_item_id: int = 0

@export_group("APPEARANCE")
## Show or hide the floor border.
@export var border_visible: bool = true:
	set(value):
		border_visible = value
		_apply_border_visibility()

## Color of the border frame and floor label.
@export var border_color: Color = Color.WHITE:
	set(value):
		border_color = value
		_apply_border_color()
		if is_node_ready():
			update_border()

## Horizontal border thickness
@export var border_thickness_h: float = 0.2:
	set(value):
		border_thickness_h = value
		if is_node_ready():
			update_border()

## Vertical border thickness
@export var border_thickness_v: float = 0.05:
	set(value):
		border_thickness_v = value
		if is_node_ready():
			update_border()

## Corner radius of the floor border, in metres. 0 is a sharp rectangle;
## large values clamp to a full ellipse inscribed in the AABB.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:m") var border_corner_radius: float = 3:
	set(value):
		border_corner_radius = maxf(value, 0.0)
		if is_node_ready():
			update_border()

## The y position of the border. Useful if the visible floor is above or below the y=0 plane.
@export var border_y: float = 0.0:
	set(value):
		border_y = value
		if is_node_ready():
			update_border()

## Floor label. Empty uses the object name.
@export var border_text: String = "":
	set(value):
		border_text = value
		if is_node_ready():
			update_border()

## Show or hide the floor label.
@export var border_text_visible: bool = true:
	set(value):
		border_text_visible = value
		if _area_name_mesh != null:
			_area_name_mesh.visible = value

## The font size used for the name of the target on the floor.
## World size follows only this value (not object scale).
@export var border_name_font_size: float = 14.0:
	set(value):
		border_name_font_size = value
		if is_node_ready():
			update_border()

## How worn / hand-drawn the chalk looks (0 = flat paint, 1 = dusty, broken strokes).
@export_range(0.0, 1.0, 0.01) var chalk_wear: float = 0.7:
	set(value):
		chalk_wear = clampf(value, 0.0, 1.0)
		_apply_border_color()

## Overall chalk opacity multiplier (shader `chalk_alpha`).
@export_range(0.0, 1.0, 0.01) var chalk_alpha: float = 0.8:
	set(value):
		chalk_alpha = clampf(value, 0.0, 1.0)
		_apply_border_color()


## Transform to shift the border according to the AABB center.
var _border_transform: Node3D = null
## Rounded-rect (or ellipse) floor frame.
var _border_mesh: MeshInstance3D = null
## MeshInstance3D with a TextMesh displaying the target name, laid flat on the floor near the south edge.
var _area_name_mesh: MeshInstance3D = null
var _border_material: ShaderMaterial = null

## Default border width (X) when the AABB is not available.
const DEFAULT_BORDER_W = 3.0
## Default border depth (Z) when the AABB is not available.
const DEFAULT_BORDER_D = 3.0
const BORDER_NODE_NAME := "TargetBorder"
const BORDER_FONT: Font = preload("res://addons/living_platform_plugin/scripts/ui/living_caption/Glaser Stencil D Regular.ttf")
const CHALK_SHADER: Shader = preload("res://addons/living_platform_plugin/scripts/core/LivingObjects/target_chalk.gdshader")
## Label inset from the inner south border, as a fraction of glyph height.
const _LABEL_EDGE_INSET_FRAC := 0.35
const _LABEL_EDGE_INSET_MIN := 0.1
const _LABEL_EDGE_INSET_MAX := 0.2


## True when this target is scene-owned (no Omeka item).
func is_scene_target() -> bool:
	return item_id <= 0


## Id used for visit path / events: bound parent for scene targets, else item_id.
func get_effective_item_id() -> int:
	if is_scene_target() and bound_item_id > 0:
		return bound_item_id
	return item_id


## Factory for Area/Environment targets. Not registered in Omeka.
static func create_for_parent(bound_id: int, parent_label: String = "") -> LivingTargetObject:
	var target := LivingTargetObject.new()
	target.item_id = 0
	target.bound_item_id = bound_id
	target.participatory_item_type = LivingConstants.PARTICIPATORY_TYPE_TARGET
	target.name = _make_target_node_name(parent_label)
	target.set_meta(LivingConstants.META_IS_BORN, true)
	target.visible = true
	target.auto_fetch_metadata = false
	target.auto_instantiate_children = false
	target.auto_download_medium = false
	target.auto_instantiate_medium = true
	target.auto_recurse_children = false
	target.build_state = LivingItem.BuildState.READY
	return target


static func _make_target_node_name(parent_label: String) -> String:
	var label := parent_label.strip_edges()
	if label == "":
		label = "Untitled"
	return LivingConstants.TARGET_NODE_NAME_PREFIX + label


## Ensures a scene-owned LivingTargetObject under an Area or Environment.
## Idempotent: reuses an existing target child and syncs bound_item_id.
static func ensure_under(host: LivingItem) -> void:
	if host == null:
		return
	if not (host is LivingArea or host is LivingEnvironment):
		return
	if host.item_id <= 0:
		return
	if not host.is_inside_tree():
		return

	var target := _find_under(host)
	var parent_label := host.title.strip_edges()
	if parent_label == "":
		parent_label = host.name
	if target == null:
		target = create_for_parent(host.item_id, parent_label)
		host.add_child(target)
		if Engine.is_editor_hint():
			var tree := host.get_tree()
			var root = tree.edited_scene_root if tree != null else null
			target.owner = root if root != null else host.owner
	else:
		target.bound_item_id = host.item_id
		target.item_id = 0
		target.participatory_item_type = LivingConstants.PARTICIPATORY_TYPE_TARGET

	target._sync_from_parent()
	target._copy_text_fields_from_parent()
	target.build_state = LivingItem.BuildState.READY
	var medium := target.get_living_target_child()
	var needs_medium := medium == null
	if medium != null and medium.get_node_or_null("ProceduralShell") != null:
		# Migrate old cube geometry to the XZ plane.
		needs_medium = true
	if needs_medium:
		target._instantiate_target_medium()
		if target.is_node_ready():
			target.update_border.call_deferred()


static func _find_under(host: LivingItem) -> LivingTargetObject:
	for child in host.get_children():
		if child is LivingTargetObject and (child as LivingTargetObject).is_scene_target():
			return child as LivingTargetObject
		# Migrate older naming / leftover scene targets.
		if child is LivingTargetObject and (child as LivingTargetObject).item_id <= 0:
			return child as LivingTargetObject
	return null


func _ready() -> void:
	super._ready()
	if is_scene_target():
		_sync_from_parent()
		# Never participate in Omeka rebuild wait loops (stay READY, not IDLE).
		build_state = BuildState.READY
	_copy_text_fields_from_parent()
	set_notify_transform(true)
	_initialize_border_visualization()
	update_border.call_deferred()


## Scene targets are not Omeka items — skip the LivingItem build pipeline.
func fetch_omeka_info() -> void:
	if not is_scene_target():
		super.fetch_omeka_info()
		return
	_sync_from_parent()
	_copy_text_fields_from_parent()
	if auto_instantiate_medium and get_living_target_child() == null:
		_instantiate_target_medium()
		if is_node_ready():
			update_border.call_deferred()
	build_state = BuildState.READY
	build_finished.emit(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		update_border()


func _apply_prefetched_meta(meta: Dictionary) -> void:
	# Scene targets must never ingest Omeka meta.
	if is_scene_target():
		return
	super._apply_prefetched_meta(meta)
	_copy_text_fields_from_parent()
	if is_node_ready():
		update_border.call_deferred()


func _sync_from_parent() -> void:
	var parent_item := _get_text_source_parent()
	if parent_item == null:
		return
	if parent_item.item_id > 0:
		bound_item_id = parent_item.item_id
	participatory_item_type = LivingConstants.PARTICIPATORY_TYPE_TARGET
	if title.strip_edges() == "":
		title = parent_item.title
	var label := parent_item.title.strip_edges()
	if label == "":
		label = parent_item.name
	name = _make_target_node_name(label)
	if border_text.strip_edges() == "":
		border_text = label


func _copy_text_fields_from_parent() -> void:
	var parent_item := _get_text_source_parent()
	if parent_item == null:
		return
	short_description = parent_item.short_description
	long_description = parent_item.long_description
	catalog_description = parent_item.catalog_description


func _get_text_source_parent() -> LivingItem:
	var n := get_parent()
	while n != null:
		if n is LivingArea or n is LivingEnvironment:
			return n as LivingItem
		n = n.get_parent()
	return null


func instantiate_medium() -> void:
	if is_scene_target():
		_instantiate_target_medium()
		await get_tree().process_frame
		await get_tree().process_frame
		update_border()
		return
	super.instantiate_medium()
	await get_tree().process_frame
	await get_tree().process_frame
	update_border()


func _instantiate_target_medium() -> void:
	participatory_item_type = LivingConstants.PARTICIPATORY_TYPE_TARGET
	for child in get_children():
		if child is LivingTarget:
			child.owner = null
			remove_child(child)
			child.queue_free()

	var medium := LivingTarget.new()
	medium.name = "LivingTarget"
	add_child(medium)
	if Engine.is_editor_hint():
		var tree := get_tree()
		var root = tree.edited_scene_root if tree != null else null
		medium.owner = root if root != null else owner


func _get_visit_medium_node() -> Node3D:
	return get_living_target_child()


func _get_visit_aabb_exclude_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _border_transform != null:
		out.append(_border_transform)
	return out


func get_living_target_child() -> LivingTarget:
	for child in get_children():
		if child is LivingTarget:
			return child as LivingTarget
	return null


#
# BORDER VISUALIZATION (rounded-rect frame fitted to LivingTarget AABB)
#


func _resolved_border_text() -> String:
	var custom := border_text.strip_edges()
	if custom.is_empty():
		return self.name
	return custom


func _ensure_border_material() -> ShaderMaterial:
	if _border_material == null:
		_border_material = ShaderMaterial.new()
		_border_material.shader = CHALK_SHADER
	_apply_border_color()
	return _border_material


func _apply_border_color() -> void:
	if _border_material == null:
		return
	_border_material.set_shader_parameter("chalk_color", border_color)
	_border_material.set_shader_parameter("wear", chalk_wear)
	_border_material.set_shader_parameter("chalk_alpha", chalk_alpha)


func _apply_border_visibility() -> void:
	if _border_mesh != null:
		_border_mesh.visible = border_visible


func _initialize_border_visualization() -> void:
	if _border_transform != null:
		_border_transform.free()
		_border_transform = null
	_border_mesh = null
	_area_name_mesh = null

	var mat := _ensure_border_material()

	_border_transform = Node3D.new()
	_border_transform.name = BORDER_NODE_NAME

	_border_mesh = MeshInstance3D.new()
	_border_mesh.name = "%s-Frame" % BORDER_NODE_NAME
	_border_mesh.material_override = mat
	_border_transform.add_child(_border_mesh)
	_apply_border_visibility()

	var text_mesh := TextMesh.new()
	text_mesh.font = BORDER_FONT
	text_mesh.text = _resolved_border_text()
	text_mesh.font_size = self.border_name_font_size
	_area_name_mesh = MeshInstance3D.new()
	_area_name_mesh.name = "TargetLabel"
	_area_name_mesh.mesh = text_mesh
	_area_name_mesh.material_override = mat
	_area_name_mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_area_name_mesh.visible = border_text_visible
	_border_transform.add_child(_area_name_mesh)

	add_child(_border_transform)


func update_border() -> void:
	if _border_transform == null or _area_name_mesh == null:
		return

	(_area_name_mesh.mesh as TextMesh).font = BORDER_FONT
	(_area_name_mesh.mesh as TextMesh).text = _resolved_border_text()
	(_area_name_mesh.mesh as TextMesh).font_size = self.border_name_font_size
	_area_name_mesh.visible = border_text_visible
	_apply_border_color()

	var exclude: Array[Node3D] = []
	if _border_transform != null:
		exclude.append(_border_transform)
	for node in find_children(LivingVisitPoint.NODE_NAME, "Node3D", true, false):
		if node is Node3D:
			exclude.append(node as Node3D)

	var my_aabb := LivingUtils.get_node_aabb(self, exclude)

	if my_aabb.get_volume() > 0.0:
		# Outer frame edge sits exactly on the AABB (no padding).
		var box_w = my_aabb.size.x
		var box_d = my_aabb.size.z
		_resize_border(box_w, box_d)
		var border_center = my_aabb.get_center()
		_border_transform.position = Vector3(border_center.x, self.border_y, border_center.z)
	else:
		_resize_border(DEFAULT_BORDER_W, DEFAULT_BORDER_D)
		_border_transform.position = Vector3(0, self.border_y, 0)


func _resize_border(width: float, depth: float) -> void:
	if _border_mesh == null:
		return

	# Thickness / radius are authored in world metres; divide by object scale so
	# the inherited parent scale does not stretch the frame.
	var sx := maxf(absf(scale.x), 0.0001)
	var sy := maxf(absf(scale.y), 0.0001)
	var sz := maxf(absf(scale.z), 0.0001)
	var bw_x := border_thickness_h / sx
	var bw_z := border_thickness_h / sz
	var bh := border_thickness_v / sy
	var hw := width / 2.0
	var hd := depth / 2.0
	var rx := minf(border_corner_radius / sx, hw)
	var rz := minf(border_corner_radius / sz, hd)

	_border_mesh.mesh = _build_rounded_rect_frame_mesh(hw, hd, rx, rz, bw_x, bw_z, bh)

	var tm := _area_name_mesh.mesh as TextMesh
	tm.depth = bh
	# Cancel object scale before measuring, so font_size alone drives glyph size.
	_compensate_label_scale()
	# Pin the south (+Z) edge of the label just inside the inner south border.
	var mesh_aabb := tm.get_aabb()
	var ls := _area_name_mesh.scale
	# Node scale then -90° X: (x, y, z) → (x·sx, z·sy, -y·sy) with sy = ls.y
	var y0 := mesh_aabb.position.y * ls.y
	var y1 := (mesh_aabb.position.y + mesh_aabb.size.y) * ls.y
	var z_south := maxf(-y0, -y1)
	# Small inset from the frame: fraction of glyph height, clamped.
	var glyph_h := absf(y1 - y0)
	var edge_inset := clampf(glyph_h * _LABEL_EDGE_INSET_FRAC, _LABEL_EDGE_INSET_MIN, _LABEL_EDGE_INSET_MAX)
	_area_name_mesh.position = Vector3(0.0, bh / 2.0, hd - bw_z - z_south - edge_inset)


func _build_rounded_rect_frame_mesh(
	hw: float,
	hd: float,
	rx: float,
	rz: float,
	bw_x: float,
	bw_z: float,
	bh: float
) -> ArrayMesh:
	var segs := 12 if (rx > 0.0001 or rz > 0.0001) else 1
	var hw_i := maxf(hw - bw_x, 0.0001)
	var hd_i := maxf(hd - bw_z, 0.0001)
	var rx_i := minf(maxf(rx - bw_x, 0.0), hw_i)
	var rz_i := minf(maxf(rz - bw_z, 0.0), hd_i)
	var outer := _sample_rounded_rect(hw, hd, rx, rz, segs)
	var inner := _sample_rounded_rect(hw_i, hd_i, rx_i, rz_i, segs)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := outer.size()
	for i in n:
		var j := (i + 1) % n
		var o0 := outer[i]
		var o1 := outer[j]
		var i0 := inner[i]
		var i1 := inner[j]
		var o0b := Vector3(o0.x, 0.0, o0.z)
		var o0t := Vector3(o0.x, bh, o0.z)
		var o1b := Vector3(o1.x, 0.0, o1.z)
		var o1t := Vector3(o1.x, bh, o1.z)
		var i0b := Vector3(i0.x, 0.0, i0.z)
		var i0t := Vector3(i0.x, bh, i0.z)
		var i1b := Vector3(i1.x, 0.0, i1.z)
		var i1t := Vector3(i1.x, bh, i1.z)
		_add_mesh_quad(st, o0b, o0t, o1t, o1b)
		_add_mesh_quad(st, o0t, i0t, i1t, o1t)
		_add_mesh_quad(st, i0t, i0b, i1b, i1t)
		_add_mesh_quad(st, o0b, o1b, i1b, i0b)

	return st.commit()


func _sample_rounded_rect(hw: float, hd: float, rx: float, rz: float, segs: int) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	var centers := PackedVector2Array([
		Vector2(hw - rx, -hd + rz),
		Vector2(hw - rx, hd - rz),
		Vector2(-hw + rx, hd - rz),
		Vector2(-hw + rx, -hd + rz),
	])
	var a0s := PackedFloat32Array([-PI * 0.5, 0.0, PI * 0.5, PI])
	var a1s := PackedFloat32Array([0.0, PI * 0.5, PI, PI * 1.5])
	for c in 4:
		var center := centers[c]
		for i in segs:
			var t := float(i) / float(segs)
			var a := lerpf(a0s[c], a1s[c], t)
			pts.append(Vector3(center.x + rx * cos(a), 0.0, center.y + rz * sin(a)))
	return pts


func _add_mesh_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.00000001:
		return
	n = n.normalized()
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_normal(n)
	st.add_vertex(d)


## Keep label world size independent of LivingTargetObject scale.
## Only border_name_font_size (× TextMesh.pixel_size) sets visible size.
## TextMesh is rotated -90° on X, so local Y → world Z and local Z → world Y.
func _compensate_label_scale() -> void:
	if _area_name_mesh == null:
		return
	var ps := scale
	var sx := maxf(absf(ps.x), 0.0001)
	var sy := maxf(absf(ps.y), 0.0001)
	var sz := maxf(absf(ps.z), 0.0001)
	_area_name_mesh.scale = Vector3(1.0 / sx, 1.0 / sz, 1.0 / sy)
