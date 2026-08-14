@tool
extends LivingObject
class_name Living3DModelObject

# Typed parent for Omeka "Oggetto". Owns face_visible for GLB Face meshes.

@export_group("APPEARANCE")
@export var face_visible: bool = true :
	set(v):
		face_visible = v
		if not is_inside_tree():
			return
		apply_face_visibility()

## Visit pose (local to the object). Survives in the scene via these exports.
## The visual marker is owned/recreated by the Living3DModel medium (like colliders).
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


func _ready() -> void:
	super._ready()
	call_deferred("apply_face_visibility")


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	await get_tree().process_frame
	apply_face_visibility()


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
	var medium := get_living_3dmodel_child()
	if medium != null:
		LivingVisitPoint.sync_on_medium(medium)


func get_living_3dmodel_child() -> Living3DModel:
	for child in get_children():
		if child is Living3DModel:
			return child as Living3DModel
	return null


func apply_face_visibility() -> void:
	for c in get_children():
		_set_face_recursive(c, face_visible)


func _set_face_recursive(node: Node, is_vis: bool) -> void:
	if node is MeshInstance3D and node.name.to_lower() == LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE.to_lower():
		node.visible = is_vis

	for child in node.get_children():
		_set_face_recursive(child, is_vis)


func _has_face_in_children() -> bool:
	for c in get_children():
		if _find_face_recursive(c):
			return true
	return false


func _find_face_recursive(node: Node) -> bool:
	if node is MeshInstance3D and node.name.to_lower() == LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE.to_lower():
		return true

	for child in node.get_children():
		if _find_face_recursive(child):
			return true

	return false
