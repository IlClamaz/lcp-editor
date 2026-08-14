@tool
@abstract
extends LivingObject
class_name LivingVisitableObject

# Shared base for LivingObject types that expose a "visit point": a pose the
# player teleports to when visiting the object. Subclasses only need to say
# which of their children is the medium node the visit marker syncs onto.

## Visit pose (local to the object). Survives in the scene via these exports.
## The visual marker is owned/recreated by the medium node (like colliders).
## If `visit_position` is left at ZERO, a temporary fallback will be used.
var _visit_position: Vector3 = Vector3.ZERO
var _visit_rotation_degrees: Vector3 = Vector3.ZERO

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

const _DEFAULT_VISIT_OFFSET_M := 1.8


func get_visit_transform() -> Transform3D:
	# Choose the visit position in world space.
	var visit_pos_local := _visit_position
	var has_custom_pos := visit_pos_local != Vector3.ZERO
	if not has_custom_pos:
		visit_pos_local = Vector3(0.0, 0.0, _DEFAULT_VISIT_OFFSET_M)

	var visit_pos_world := global_transform.origin + global_transform.basis * visit_pos_local

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


func _on_visit_pose_changed() -> void:
	if not is_inside_tree():
		return
	var medium := _get_visit_medium_node()
	if medium != null:
		LivingVisitPoint.sync_on_medium(medium)


## Returns the child node the visit marker is attached/synced to, or null if none exists yet.
@abstract
func _get_visit_medium_node() -> Node3D
