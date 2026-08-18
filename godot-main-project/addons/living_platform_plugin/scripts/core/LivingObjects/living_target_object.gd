@tool
extends LivingVisitableObject
class_name LivingTargetObject

# Typed parent for Omeka "Target". Draws a LivingArea-style colored border
# around the LivingTarget medium.

@export_group("APPEARANCE")
## Show or hide the rectangular floor border.
@export var border_visible: bool = true:
	set(value):
		border_visible = value
		_apply_border_visibility()

## Color of the border strips and floor label.
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
## Holds the 4 instances of the geometries showing the 4 border segments.
var _border_strips: Array = []
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
# BORDER VISUALIZATION (same geometry as LivingArea, fitted to LivingTarget)
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
	for strip in _border_strips:
		if strip is Node3D:
			(strip as Node3D).visible = border_visible


func _initialize_border_visualization() -> void:
	if _border_transform != null:
		_border_transform.free()
		_border_transform = null

	var mat := _ensure_border_material()

	_border_transform = Node3D.new()
	_border_transform.name = BORDER_NODE_NAME
	_border_strips.clear()
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = mat
		mi.name = "%s-%s" % [BORDER_NODE_NAME, i]
		_border_transform.add_child(mi)
		_border_strips.append(mi)
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
	assert(_border_strips.size() == 4)

	# Thickness is authored in world metres; divide by object scale so the
	# inherited parent scale does not stretch the strips.
	var sx := maxf(absf(scale.x), 0.0001)
	var sy := maxf(absf(scale.y), 0.0001)
	var sz := maxf(absf(scale.z), 0.0001)
	var bw_x := border_thickness_h / sx
	var bw_z := border_thickness_h / sz
	var bh := border_thickness_v / sy
	var hw := width / 2.0
	var hd := depth / 2.0
	var inner_depth := maxf(depth - 2.0 * bw_z, 0.0)

	var north: MeshInstance3D = _border_strips[0]
	(north.mesh as BoxMesh).size = Vector3(width, bh, bw_z)
	north.position = Vector3(0.0, bh / 2.0, -hd + bw_z / 2.0)

	var south: MeshInstance3D = _border_strips[1]
	(south.mesh as BoxMesh).size = Vector3(width, bh, bw_z)
	south.position = Vector3(0.0, bh / 2.0, hd - bw_z / 2.0)

	var west: MeshInstance3D = _border_strips[2]
	(west.mesh as BoxMesh).size = Vector3(bw_x, bh, inner_depth)
	west.position = Vector3(-hw + bw_x / 2.0, bh / 2.0, 0.0)

	var east: MeshInstance3D = _border_strips[3]
	(east.mesh as BoxMesh).size = Vector3(bw_x, bh, inner_depth)
	east.position = Vector3(hw - bw_x / 2.0, bh / 2.0, 0.0)

	var tm := _area_name_mesh.mesh as TextMesh
	var text_z_offset = tm.font_size * tm.pixel_size
	tm.depth = bh
	_area_name_mesh.position = Vector3(0.0, bh / 2.0, hd - bw_z - text_z_offset)


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
