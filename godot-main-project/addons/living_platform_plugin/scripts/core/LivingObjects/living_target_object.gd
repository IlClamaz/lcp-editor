@tool
extends LivingVisitableObject
class_name LivingTargetObject

# Typed parent for Omeka "Target". Draws a colored floor border
# around the LivingTarget medium.

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
@export var border_thickness_h: float = 0.1:
	set(value):
		border_thickness_h = value
		if is_node_ready():
			update_border()

## Vertical border thickness
@export var border_thickness_v: float = 0.1:
	set(value):
		border_thickness_v = value
		if is_node_ready():
			update_border()

## Corner radius of the floor border, in metres. 0 is a sharp rectangle;
## large values clamp to a full ellipse inscribed in the AABB.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:m") var border_corner_radius: float = 0.0:
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

## The font size used for the name of the target on the floor
@export var border_name_font_size: float = 32.0:
	set(value):
		border_name_font_size = value
		if is_node_ready():
			update_border()


## Transform to shift the border according to the AABB center.
var _border_transform: Node3D = null
## Rounded-rect (or ellipse) floor frame.
var _border_mesh: MeshInstance3D = null
## MeshInstance3D with a TextMesh displaying the target name, laid flat on the floor near the south edge.
var _area_name_mesh: MeshInstance3D = null
var _border_material: StandardMaterial3D = null

## Default border width (X) when the AABB is not available.
const DEFAULT_BORDER_W = 2.0
## Default border depth (Z) when the AABB is not available.
const DEFAULT_BORDER_D = 1.0
const BORDER_NODE_NAME := "TargetBorder"
const BORDER_FONT: Font = preload("res://addons/living_platform_plugin/scripts/ui/living_caption/malayalam-mn.ttf")
## Padding as a fraction of object size so the frame sits off the mesh.
const _BORDER_PADDING_FRAC := 0.1


func _ready() -> void:
	super._ready()
	_copy_text_fields_from_parent()
	set_notify_transform(true)
	_initialize_border_visualization()
	update_border.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		update_border()


func _apply_prefetched_meta(meta: Dictionary) -> void:
	super._apply_prefetched_meta(meta)
	_copy_text_fields_from_parent()
	if is_node_ready():
		update_border.call_deferred()


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
	super.instantiate_medium()
	await get_tree().process_frame
	await get_tree().process_frame
	update_border()


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


func _ensure_border_material() -> StandardMaterial3D:
	if _border_material == null:
		_border_material = StandardMaterial3D.new()
		_border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_border_material.albedo_color = border_color
	return _border_material


func _apply_border_color() -> void:
	if _border_material != null:
		_border_material.albedo_color = border_color


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
		my_aabb = LivingUtils.scale_aabb_around_center(my_aabb, 1.0 + _BORDER_PADDING_FRAC)
		var box_w = my_aabb.size.x
		var box_d = my_aabb.size.z
		_resize_border(box_w, box_d)
		var border_center = my_aabb.get_center()
		_border_transform.position = Vector3(border_center.x, self.border_y, border_center.z)
	else:
		_resize_border(DEFAULT_BORDER_W, DEFAULT_BORDER_D)
		_border_transform.position = Vector3(0, self.border_y, 0)

	_compensate_label_scale()


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
	var text_z_offset = tm.font_size * tm.pixel_size
	tm.depth = bh
	_area_name_mesh.position = Vector3(0.0, bh / 2.0, hd - bw_z - text_z_offset)


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


## Keep the floor label uniformly scaled in world space so non-uniform object
## scale stretches the frame but not the text. TextMesh is rotated -90° on X,
## so local Y maps to world Z and local Z maps to world Y.
func _compensate_label_scale() -> void:
	if _area_name_mesh == null:
		return
	var ps := scale
	var sx := maxf(absf(ps.x), 0.0001)
	var sy := maxf(absf(ps.y), 0.0001)
	var sz := maxf(absf(ps.z), 0.0001)
	var uniform := sqrt(sx * sz)
	_area_name_mesh.scale = Vector3(uniform / sx, uniform / sz, uniform / sy)
