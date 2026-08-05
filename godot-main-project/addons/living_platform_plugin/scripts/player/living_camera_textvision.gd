extends Node3D

class_name LivingCameraTextVision

# Riferimenti
@export var camera: Node3D
@export var _camera_feet: Area3D
## The instance to manage the floating HUDs
@export var caption_manager: CaptionManager

# Variabili interne
var _feet_collision_item_to_node_dict: Dictionary[LivingItem, Node3D] = {}
var _feet_collision_node_to_item_dict: Dictionary[Node3D, LivingItem] = {}



func _ready() -> void:

	if caption_manager == null:
		caption_manager = CaptionManager.new(self)
		caption_manager.hud_clicked.connect(self._on_hud_clicked)

	_camera_feet.collision_layer = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
	_camera_feet.collision_mask = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
	_camera_feet.body_entered.connect(_on_feet_entered_body)
	_camera_feet.body_exited.connect(_on_feet_exited_body)
	# We need to intercept also collision with areas, because in some cases the Trigger is instantiates as Area, in some other cases as Body.
	_camera_feet.area_entered.connect(_on_feet_entered_body)
	_camera_feet.area_exited.connect(_on_feet_entered_body)


func _process(delta: float) -> void:

	# Update the position of the feet collision object: it must stay on the floor regardless of the camera movement
	if camera and _camera_feet:
		var feet_position := camera.global_position
		# TODO - It might not work for highly elevated floors. Should be better soved by casting a ray downwards
		feet_position.y = 0.0
		_camera_feet.global_position = feet_position

		caption_manager._process(delta)


func _on_feet_entered_body(b: Node3D):
	print("Camera feet entered body/area ", b)

	var node: Node3D = b
	while node != null:
		if node is LivingObject:
			print("Camera entered LivingObject: ", node.name)
			break
		elif node is LivingArea:
			print("Camera entered LivingArea: ", node.name)
			break
		elif node is LivingStargate:
			print("Camera entered LivingStargate. Ignoring: ", node.name)
			return
		node = node.get_parent()

	assert ((node == null) or (node is LivingObject) or (node is LivingArea))
	var item: LivingItem = node as LivingItem

	_feet_collision_item_to_node_dict[item] = b
	_feet_collision_node_to_item_dict[b] = item

	assert (_feet_collision_item_to_node_dict.size() == _feet_collision_node_to_item_dict.size())


func _on_feet_exited_body(b: Node3D) -> void:
	print("Camera feet left body ", b)

	if b in _feet_collision_node_to_item_dict:
		var n: LivingItem = _feet_collision_node_to_item_dict[b]
		_feet_collision_node_to_item_dict.erase(b)
		_feet_collision_item_to_node_dict.erase(n)

	assert (_feet_collision_item_to_node_dict.size() == _feet_collision_node_to_item_dict.size())


func get_stepping_on_items() -> Array[LivingItem]:
	return _feet_collision_item_to_node_dict.keys()


func _on_hud_clicked(item: LivingItem):
	# TODO -- remove this creation and relative invokations
	caption_manager.create_long_caption(item)


func raycast_closest_in_group(group_name: String, ray_length: float = 1000.0) -> LivingItem:
	var space_state := get_world_3d().direct_space_state
	var ray_origin: Vector3 = camera.global_position
	var ray_target: Vector3 = ray_origin + camera.global_transform.basis * Vector3(0.0, 0.0, -ray_length)

	var exclude: Array[RID] = []

	while true:
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
		query.exclude = exclude
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER | LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_LAYER
		var result: Dictionary = space_state.intersect_ray(query)

		if result.is_empty():
			return null

		var node: Node = result["collider"]
		while node != null:
			if node.is_in_group(group_name):
				assert(node is LivingItem)
				return node as LivingItem
			node = node.get_parent()

		exclude.append(result["rid"])

	return null


func raycast_all_in_group(group_name: String, blocking_group: String = "", ray_length: float = 1000.0) -> Array[LivingItem]:
	var space_state := get_world_3d().direct_space_state
	var ray_origin: Vector3 = camera.global_position
	var ray_target: Vector3 = ray_origin + camera.global_transform.basis * Vector3(0.0, 0.0, -ray_length)

	var exclude: Array[RID] = []
	var found: Array[LivingItem] = []
	var seen_items: Dictionary = {}
	var blocked := false

	while true:
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
		query.exclude = exclude
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER | LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_LAYER
		var result: Dictionary = space_state.intersect_ray(query)

		if result.is_empty():
			break

		exclude.append(result["rid"])

		var node: Node = result["collider"]
		while node != null:
			if blocking_group != "" and node.is_in_group(blocking_group):
				blocked = true
				break
			if node.is_in_group(group_name):
				assert(node is LivingItem)
				if not seen_items.has(node):
					found.append(node as LivingItem)
					seen_items[node] = true
				break
			node = node.get_parent()

		if blocked:
			break

	return found
