@tool
extends LivingObject
class_name LivingFlatMediaObject

# Parent for flat curved media (Image / Video / Slideshow). Owns curvature + diagonal.

@export_group("APPEARANCE")
@export_range(-360.0, 360.0) var curvature: float = 0.0 :
	set(v):
		curvature = v
		if not is_inside_tree():
			return
		_set_curvature()

@export_range(0.01, 50.0) var diagonal: float = 1.0 :
	set(v):
		diagonal = max(v, 0.01)
		if not is_inside_tree():
			return
		_set_pixel_size()

## Visit pose (local to the object). Survives in the scene via these exports.
## The visual marker is owned/recreated by the flat-media medium (like colliders).
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
	call_deferred("_set_curvature")
	call_deferred("_set_pixel_size")


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	await get_tree().process_frame
	_set_curvature()
	_set_pixel_size()


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
	var medium := _get_flat_media_medium_node()
	if medium != null:
		LivingVisitPoint.sync_on_medium(medium)


func _get_flat_media_medium_node() -> Node:
	for child in get_children():
		if child is LivingVideo or child is LivingImage or child is LivingSlideShow:
			return child
	return null


func _set_curvature() -> void:
	var child = _get_2d_child()
	if is_instance_valid(child):
		child.curvature = self.curvature


func _set_pixel_size() -> void:
	var child = _get_2d_child()
	if is_instance_valid(child) and "diagonal" in child:
		child.diagonal = diagonal


func _get_2d_child() -> Node:
	for child in get_children():
		if child is LivingVideo or child is LivingImage or child is LivingSlideShow:
			return child
	return null


func _has_2d_in_children() -> bool:
	return get_children().any(func(c): return c is LivingVideo or c is LivingImage or c is LivingSlideShow)


func _map_pixel_size_from_target_diagonal(child: Node, diagonal_m: float) -> float:
	var native_size := _get_native_media_size(child)
	if native_size.x <= 0.0 or native_size.y <= 0.0:
		return -1.0

	var native_diagonal_px := native_size.length()
	if native_diagonal_px <= 0.0:
		return -1.0

	return diagonal_m / native_diagonal_px


func _get_native_media_size(child: Node) -> Vector2:
	if child is LivingImage:
		var image := child as LivingImage
		if image.current_texture != null:
			return image.current_texture.get_size()
		return Vector2.ZERO

	if child is LivingVideo:
		var video := child as LivingVideo
		if video.viewport != null:
			return Vector2(video.viewport.size)
		return Vector2.ZERO

	return Vector2.ZERO
