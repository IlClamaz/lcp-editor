@tool
@abstract
extends LivingObject
class_name LivingVisitableObject

# Shared base for LivingObject types that expose a "visit point": a pose the
# player teleports to when visiting the object. Subclasses only need to say
# which of their children is the medium node the visit marker syncs onto.

## Offset from the auto visit pose (AABB +Z front). Survives in the scene via
## these exports. The visual marker is owned/recreated by the medium node (like
## colliders). (0, 0, 0) keeps the AABB-computed pose (world Y = 0). Inspector
## X/Z nudge on the floor plane; Y raises/lowers from that floor.
var _visit_position: Vector3 = Vector3.ZERO
var _visit_rotation_degrees: Vector3 = Vector3.ZERO

@export_group("APPEARANCE")
@export var visit_position: Vector3:
	get:
		return _visit_position
	set(value):
		_visit_position = value
		_on_visit_pose_changed()

@export var visit_rotation_degrees: Vector3:
	get:
		return _visit_rotation_degrees
	set(value):
		_visit_rotation_degrees = value
		_on_visit_pose_changed()

@export_group("BEHAVIOR")
## When false, CaptionManager will not show the short HUD caption for this object.
@export var show_caption: bool = true
## When false, the visit-point marker is hidden. The visit pose still works.
@export var show_visit_point: bool = true:
	set(value):
		show_visit_point = value
		_apply_visit_point_visibility()

## Extra padding beyond the AABB face, as a fraction of the half-extent along +Z.
const _VISIT_AABB_PADDING_FRAC := 0.05
## Minimum air gap past the AABB face so thin/small objects still have standing room.
const _VISIT_STAND_CLEARANCE_M := 1.5


func get_visit_transform() -> Transform3D:
	var default_local := _default_visit_position_local()
	var visit_pos_local := Vector3(
		default_local.x + _visit_position.x,
		default_local.y,
		default_local.z + _visit_position.z
	)
	var visit_pos_world := global_transform.origin + global_transform.basis * visit_pos_local
	visit_pos_world.y = _visit_position.y

	# Yaw: base direction is toward the object origin projected on XZ plane.
	var to_obj := global_transform.origin - visit_pos_world
	to_obj.y = 0.0

	var dir := to_obj
	if dir.length_squared() < 0.0001:
		# Fallback if player position equals object position.
		dir = global_transform.basis * Vector3(0.0, 0.0, 1.0)
		dir.y = 0.0

	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
		dir.y = 0.0

	dir = dir.normalized()
	var yaw_base := atan2(dir.x, dir.z)
	var basis_base := Basis(Vector3.UP, yaw_base)
	var basis_local_rot := Basis.from_euler(Vector3(
		deg_to_rad(_visit_rotation_degrees.x),
		deg_to_rad(_visit_rotation_degrees.y),
		deg_to_rad(_visit_rotation_degrees.z)
	))
	var basis := basis_base * basis_local_rot

	return Transform3D(basis, visit_pos_world)


## Local pose just outside the +Z face of the object's AABB, on the object's Y = 0 plane.
func _default_visit_position_local() -> Vector3:
	var aabb := AABB(Vector3.ZERO, Vector3.ZERO)
	if is_inside_tree():
		var exclude: Array[Node3D] = []
		for node in find_children(LivingVisitPoint.NODE_NAME, "Node3D", true, false):
			if node is Node3D:
				exclude.append(node as Node3D)
		exclude.append_array(_get_visit_aabb_exclude_nodes())
		aabb = LivingUtils.get_node_aabb(self, exclude)

	var center := aabb.get_center()
	var half_z := aabb.size.z * 0.5
	var extra := maxf(_VISIT_STAND_CLEARANCE_M, half_z * _VISIT_AABB_PADDING_FRAC)
	return Vector3(center.x, 0.0, center.z + half_z + extra)


## Extra nodes to leave out of the visit AABB (border frames, etc.).
func _get_visit_aabb_exclude_nodes() -> Array[Node3D]:
	return []


func _on_visit_pose_changed() -> void:
	if not is_inside_tree():
		return
	var medium := _get_visit_medium_node()
	if medium != null:
		LivingVisitPoint.sync_on_medium(medium)
		_apply_visit_point_visibility()


func _apply_visit_point_visibility() -> void:
	if not is_inside_tree():
		return
	var medium := _get_visit_medium_node()
	if medium == null:
		return
	var vp := medium.get_node_or_null(LivingVisitPoint.NODE_NAME) as LivingVisitPoint
	if vp != null:
		vp.set_visual_visible(show_visit_point)


## Returns the child node the visit marker is attached/synced to, or null if none exists yet.
@abstract
func _get_visit_medium_node() -> Node3D
