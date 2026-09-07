@tool
extends Marker3D

class_name LivingVisitPoint

## Runtime/editor visualization of the guided visit pose.
## Created by media nodes like colliders: no owner, not packed in .tscn,
## recreated on medium `_ready`. Pose data lives on the Living*Object parent.

const NODE_NAME := "LivingVisitPoint"
const VISUAL_NODE_NAME := "VisitPointVisual"
const PIN_NODE_NAME := "pin"
const PIN_SCENE: PackedScene = preload("res://addons/living_platform_plugin/scenes/pin.glb")


## Ensure a visit marker exists under `medium` and matches the parent object's pose.
static func sync_on_medium(medium: Node3D) -> void:
	if medium == null or not medium.is_inside_tree():
		return
	var host := medium.get_parent()
	if host == null or not host.has_method("get_visit_transform"):
		return

	var vp := medium.get_node_or_null(NODE_NAME) as LivingVisitPoint
	if vp == null:
		vp = LivingVisitPoint.new()
		vp.name = NODE_NAME
		medium.add_child(vp)
		# Intentionally no owner — same pattern as collider helpers on media.

	vp.global_transform = host.get_visit_transform()
	vp._compensate_visual_world_scale()
	if "show_visit_point" in host:
		vp.set_visual_visible(bool(host.get("show_visit_point")))


func _ready() -> void:
	# Ignore parent scale so the marker keeps a constant world size.
	top_level = true
	_ensure_visual()
	set_process(true)


func _process(_delta: float) -> void:
	_follow_host_pose()
	_compensate_visual_world_scale()
	_apply_host_visual_visibility()


func _follow_host_pose() -> void:
	if not is_inside_tree():
		return
	var medium := get_parent() as Node3D
	if medium == null or not medium.is_inside_tree():
		return
	var host := medium.get_parent()
	if host == null or not host.has_method("get_visit_transform"):
		return
	global_transform = host.get_visit_transform()


func _apply_host_visual_visibility() -> void:
	if not is_inside_tree():
		return
	var medium := get_parent() as Node3D
	if medium == null:
		return
	var host := medium.get_parent()
	if host != null and "show_visit_point" in host:
		set_visual_visible(bool(host.get("show_visit_point")))


## Undo inherited parent scale so the marker keeps a constant world size.
func _compensate_visual_world_scale() -> void:
	var visual := get_node_or_null(VISUAL_NODE_NAME) as Node3D
	if visual == null:
		return
	if not is_inside_tree():
		return
	var gs := global_transform.basis.get_scale()
	visual.scale = Vector3(
		1.0 / maxf(absf(gs.x), 0.0001),
		1.0 / maxf(absf(gs.y), 0.0001),
		1.0 / maxf(absf(gs.z), 0.0001)
	)


func set_visual_visible(is_vis: bool) -> void:
	var visual := get_node_or_null(VISUAL_NODE_NAME) as Node3D
	if visual == null:
		_ensure_visual()
		visual = get_node_or_null(VISUAL_NODE_NAME) as Node3D
	if visual != null:
		visual.visible = is_vis


func _ensure_visual() -> void:
	var root_visual := get_node_or_null(VISUAL_NODE_NAME) as Node3D
	if root_visual == null:
		root_visual = Node3D.new()
		root_visual.name = VISUAL_NODE_NAME
		add_child(root_visual)

	var pin := root_visual.get_node_or_null(PIN_NODE_NAME)
	if pin != null:
		return

	while root_visual.get_child_count() > 0:
		root_visual.get_child(0).free()

	if PIN_SCENE == null:
		push_error("LivingVisitPoint: missing pin scene at res://addons/living_platform_plugin/scenes/pin.glb")
		return

	pin = PIN_SCENE.instantiate()
	pin.name = PIN_NODE_NAME
	root_visual.add_child(pin)
