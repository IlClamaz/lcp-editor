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
