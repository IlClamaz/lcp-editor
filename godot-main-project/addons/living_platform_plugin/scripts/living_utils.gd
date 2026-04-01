class_name LivingUtils

static func _set_owner_recursive(n: Node, owner: Node) -> void:
	if n == null or owner == null:
		return
	if not is_instance_valid(n) or not is_instance_valid(owner):
		return
	if not n.is_inside_tree() or not owner.is_inside_tree():
		# Se serve, puoi fare call_deferred qui, ma di solito non serve con Undo/Redo.
		return

	# owner deve essere antenato del nodo
	if n != owner and not owner.is_ancestor_of(n):
		return

	# set owner su n e subtree
	n.owner = owner
	for c in n.get_children():
		_set_owner_recursive(c, owner)


static func floor_distance(a: Vector3, b: Vector3) -> float:

	var a_floor := Vector3(a.x, 0.0, a.z)
	var b_floor := Vector3(b.x, 0.0, b.z)
	
	return a_floor.distance_to(b_floor)


## Returns the AABB of the given node in its own reference space, but without its own transformations.
## You can compute an AABB of the object positoned and rotated in space by composing it with the Node3D global_transform.
## If the selected node has no bounding box (e.g., because of missing geometries), the returned AABB will have position in 0,0,0 and size 0,0,0. Hence, its volume (see `.get_volume()`) will be 0.0.
static func get_node_aabb(root: Node3D) -> AABB:
	return _collect_aabb_recursive(root, root)


static func _collect_aabb_recursive(root: Node3D, node: Node3D) -> AABB:
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

	return result if has_result else AABB(Vector3.ZERO, Vector3.ZERO)

## Returns the AABB of the given node in its own reference space, but considering ONLY
## children named "Volume" or "volume" (case-insensitive).
static func get_volume_aabb(root: Node3D) -> AABB:
	return _collect_volume_aabb_recursive(root, root)


static func _collect_volume_aabb_recursive(root: Node3D, node: Node3D) -> AABB:
	var result: AABB
	var has_result := false

	# Aggiunto il controllo sul nome in modo case-insensitive
	if node is VisualInstance3D and node.name.to_lower() == LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_NODE:
		var vi := node as VisualInstance3D
		var local_aabb: AABB = vi.get_aabb()
		var to_root: Transform3D = root.global_transform.affine_inverse() * node.global_transform
		result = to_root * local_aabb
		has_result = true

	# Continuiamo a scavare nei figli per trovare tutti i "volume" annidati
	for child in node.get_children():
		if child is Node3D:
			var child_aabb = _collect_volume_aabb_recursive(root, child)
			
			# Il controllo originale per capire se child_aabb contiene dei dati
			if child_aabb: 
				assert (child_aabb is AABB)
				if has_result:
					result = result.merge(child_aabb)
				else:
					result = child_aabb
					has_result = true

	return result if has_result else AABB(Vector3.ZERO, Vector3.ZERO)

static func scale_aabb_around_center(aabb: AABB, factor: float) -> AABB:
	var center = aabb.position + aabb.size * 0.5
	var half_size = aabb.size * 0.5 * factor
	var new_pos = center - half_size
	var new_size = half_size * 2.0
	return AABB(new_pos, new_size)


## Parses a NextCloud public share link and returns { "base_url": String, "token": String }.
## Example: https://nextcloud.example.com/s/5ZK4QSbQGr9bktT
## -> { "base_url": "https://nextcloud.example.com", "token": "5ZK4QSbQGr9bktT" }
static func parse_nextcloud_share_link(shared_url: String) -> Dictionary:
	var url_regex := RegEx.new()
	url_regex.compile(r"^(https?)://([^/]+)(/.+)?$")
	var m := url_regex.search(shared_url)
	if m == null:
		push_error("Invalid URL: %s" % shared_url)
		return {}
	var scheme := m.get_string(1)
	var netloc  := m.get_string(2)
	var path    := m.get_string(3)
	if path == null:
		path = ""
	var parts := path.trim_prefix("/").trim_suffix("/").split("/")
	if parts.size() < 2 or parts[0] != "s":
		push_error("Unexpected share URL format: %s" % shared_url)
		return {}
	return { "base_url": "%s://%s" % [scheme, netloc], "token": parts[1] }


static func argmin(arr: Array) -> int:
	if arr.is_empty():
		return -1

	var min_val: float = arr[0]
	var min_idx: int = 0
	for i in range(1, arr.size()):
		var x = arr[i]
		if x < min_val:
			min_val = x
			min_idx = i
	return min_idx
