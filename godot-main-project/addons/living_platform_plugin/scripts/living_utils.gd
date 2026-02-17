extends Node

class_name LivingUtils

static func set_owner_R(n: Node, owner: Node):
	n.owner = owner
	for c in n.get_children():
		set_owner_R(c, owner)


static func get_node_aabb(root: Node3D) -> AABB:
	return _collect_aabb_recursive(root, root)


static func _collect_aabb_recursive(root: Node3D, node: Node3D) :
	var result: AABB
	var has_result := false

	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		var local_aabb: AABB = vi.get_aabb()
		var to_root: Transform3D = root.global_transform.affine_inverse() * node.global_transform
		result = to_root * local_aabb
		has_result = true

	for child in node.get_children():
		if child is Node3D:
			var child_aabb = _collect_aabb_recursive(root, child)
			if child_aabb: # if not null
				assert (child_aabb is AABB)
				if has_result:
					result = result.merge(child_aabb)
				else:
					result = child_aabb
					has_result = true

	return result if has_result else null


static func scale_aabb_around_center(aabb: AABB, factor: float) -> AABB:
	var center = aabb.position + aabb.size * 0.5
	var half_size = aabb.size * 0.5 * factor
	var new_pos = center - half_size
	var new_size = half_size * 2.0
	return AABB(new_pos, new_size)
