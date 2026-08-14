@tool
extends LivingVisitableObject
class_name Living3DModelObject

# Typed parent for Omeka "Oggetto". Owns face_visible for GLB Face meshes.

@export_group("APPEARANCE")
@export var face_visible: bool = true :
	set(v):
		face_visible = v
		if not is_inside_tree():
			return
		apply_face_visibility()


func _ready() -> void:
	super._ready()
	call_deferred("apply_face_visibility")


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	await get_tree().process_frame
	apply_face_visibility()


func _get_visit_medium_node() -> Node3D:
	return get_living_3dmodel_child()


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
