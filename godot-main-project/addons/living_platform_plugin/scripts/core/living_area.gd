@tool
extends LivingItem

# Conceptually, an area is a set of items within a scene
class_name LivingArea


@export_tool_button("Show All Items") var show_all_items_btn = show_all_items
@export_tool_button("Update Area Border") var update_area_btn = update_area

## Whether to use the automatic_visuals computation for this area, or leave it to the associated medium
@export var automatic_visuals: bool = false:
	set = _set_automatic_visuals

## The material to be used for the border
@export var border_material: Material:
	set(value):
		border_material = value
		if is_node_ready(): update_area()
## The horizontal border thickness
@export var border_tickness_h: float = 0.1:
	set(value):
		border_tickness_h = value
		if is_node_ready(): update_area()
## Th vertical border thickness
@export var border_thickness_v: float = 0.1:
	set(value):
		border_thickness_v = value
		if is_node_ready(): update_area()
## The y position of the border. Useful if the visible florr is above or below the y=0 plane.
@export var border_y: float = 0.0:
	set(value):
		border_y = value
		if is_node_ready(): update_area()
## A multiplier to add some margin to the borders and prevent it to stay attached to objects
@export var border_scale: float = 1.1:
	set(value):
		border_scale = value
		if is_node_ready(): update_area()
## The font size used for the name of the area on the floor
@export var border_name_font_size = 32.0:
	set(value):
		border_name_font_size = value
		if is_node_ready(): update_area()


## Transform to shift the border according to the AABB center
## This is also used as global flag to check if the area has been automatically computed or not.
var _border_transform: Node3D = null
## Holds the 4 instances of the geometries showing the 4 border segments.
var _border_strips: Array = []  # Array of 4 MeshInstance3D forming the rectangular frame
## MeshInstance3D with a TextMesh displaying the area name, laid flat on the floor near the south edge.
var _area_name_mesh: MeshInstance3D = null
## This is needed to intercept collisions for ray casting
var _volume_collision_shape: CollisionShape3D = null

## Default border width (X) when the AABB is not available.
const DEFAULT_BORDER_W = 2.0
## Default border depth (Z) when the AABB is not available.
const DEFAULT_BORDER_D = 1.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super._ready()

	if automatic_visuals:
		_initialize_area_visualization()

		# TODO -- actually call this evera time the Environment is updated (e.g., new Elements)
		# and when all Items in the environment have instantiated their children.
		update_area.call_deferred()

	# Scene-owned visit target (also ensured after instantiate_children / rebuild).
	LivingTargetObject.ensure_under.call_deferred(self)


func _enter_tree():
	self.add_to_group(LivingConstants.RAY_PICKABLE_GROUP_NAME)


func _exit_tree():
	if self.is_in_group(LivingConstants.RAY_PICKABLE_GROUP_NAME):
		self.remove_from_group(LivingConstants.RAY_PICKABLE_GROUP_NAME)


func _on_node_added(node: Node) -> void:
	if is_ancestor_of(node):
		if not is_node_ready(): return
		print("descendant added: ", node.name)
		update_area()


func _on_node_removed(node: Node) -> void:
	if is_ancestor_of(node):
		if not is_node_ready(): return
		print("descendant removed: ", node.name)
		update_area()


func show_all_items():
	for c in self.get_children():
		if c is LivingItem:
			(c as LivingItem).set_visible(true)


#
# (AUTOMATED) AREA VISUALIZATION
#


func _set_automatic_visuals(value: bool) -> void:

	automatic_visuals = value

	if automatic_visuals and is_node_ready():
		## Istantiate the visuals
		if _border_transform != null:
			_border_transform.free()
			_border_transform = null
		_initialize_area_visualization()
		update_area.call_deferred()
	else:
		# Remove the previously instantiated visuals
		if _border_transform != null:
			_border_transform.free()
			_border_transform = null


## Initializes the nodes needed to visualize the area
func _initialize_area_visualization() -> void:

	# Prepare the material for the area, if not set by the user
	if self.border_material == null:
		self.border_material = StandardMaterial3D.new()
		self.border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Instantiate the node for centering the area
	_border_transform = Node3D.new()
	_border_transform.name = "AreaBorder"
	# Initializes the four segments of the border
	_border_strips.clear()
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = self.border_material
		mi.name = "AreaBorder-%s" % i
		_border_transform.add_child(mi)
		_border_strips.append(mi)

	# Instantiate the text showing the self.name of the area.
	# The TextMesh lays flat on the floor (rotated -90° on X), aligned along the X axis,
	# just inside the south border (+Z). Its height matches border_thickness_v.
	var text_mesh := TextMesh.new()
	text_mesh.text = self.name
	text_mesh.font_size = self.border_name_font_size
	_area_name_mesh = MeshInstance3D.new()
	_area_name_mesh.name = "AreaLabel"
	_area_name_mesh.mesh = text_mesh
	_area_name_mesh.material_override = self.border_material
	_area_name_mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_border_transform.add_child(_area_name_mesh)

	add_child(_border_transform)

	# Initialize a collision volume to default size
	# The collision box to be picked up by ray cast
	# The static body collecting the background geometry and the collision box
	var volume_collision_body = StaticBody3D.new()
	volume_collision_body.name = "VolumeCollisionBody"
	volume_collision_body.input_ray_pickable = false  # Avoid being picked when the user clicks on the scene
	volume_collision_body.collision_layer = LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_LAYER
	volume_collision_body.collision_mask = LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_LAYER
	_volume_collision_shape = CollisionShape3D.new()
	_volume_collision_shape.name = LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_NODE
	_volume_collision_shape.shape = BoxShape3D.new()
	volume_collision_body.add_child(_volume_collision_shape)

	_border_transform.add_child(volume_collision_body)


## Computes the AABB of the area and upadtes the area border visualization accordingly
func update_area() -> void:

	if not self.automatic_visuals:
		return

	(_area_name_mesh.mesh as TextMesh).text = self.name
	(_area_name_mesh.mesh as TextMesh).font_size = self.border_name_font_size

	# Get the current recursive AABB
	var my_aabb := LivingUtils.get_node_aabb(self, [_border_transform])
	print("Updating area for AABB ", my_aabb)

	if my_aabb.get_volume() > 0.0:

		my_aabb = LivingUtils.scale_aabb_around_center(my_aabb, self.border_scale)

		# Adjust area size
		var box_w = my_aabb.size.x
		var box_d = my_aabb.size.z
		_resize_area_border(box_w, box_d)

		# adjust area position
		var border_center = my_aabb.get_center()
		_border_transform.position = Vector3(border_center.x, self.border_y, border_center.z)

		# Updates the size of the _volume_collision_shape so that it matches the size of my_aabb
		_volume_collision_shape.shape.size = my_aabb.size

	else:
		_resize_area_border(DEFAULT_BORDER_W, DEFAULT_BORDER_D)
		_border_transform.position = Vector3(0, self.border_y, 0)
		_volume_collision_shape.shape.size = Vector3(DEFAULT_BORDER_W, 1.0, DEFAULT_BORDER_D)


## Resizes the rectangular border frame to the given [param width] and [param depth] (on the XZ plane).
func _resize_area_border(width: float, depth: float) -> void:
	assert (_border_strips.size() == 4)

	var bw := border_tickness_h
	var bh := border_thickness_v
	var hw := width / 2.0
	var hd := depth / 2.0
	var inner_depth := maxf(depth - 2.0 * bw, 0.0)

	# North strip (-Z side), spans full width
	var north: MeshInstance3D = _border_strips[0]
	(north.mesh as BoxMesh).size = Vector3(width, bh, bw)
	north.position = Vector3(0.0, bh / 2.0, -hd + bw / 2.0)

	# South strip (+Z side), spans full width
	var south: MeshInstance3D = _border_strips[1]
	(south.mesh as BoxMesh).size = Vector3(width, bh, bw)
	south.position = Vector3(0.0, bh / 2.0, hd - bw / 2.0)

	# West strip (-X side), fits between north and south
	var west: MeshInstance3D = _border_strips[2]
	(west.mesh as BoxMesh).size = Vector3(bw, bh, inner_depth)
	west.position = Vector3(-hw + bw / 2.0, bh / 2.0, 0.0)

	# East strip (+X side), fits between north and south
	var east: MeshInstance3D = _border_strips[3]
	(east.mesh as BoxMesh).size = Vector3(bw, bh, inner_depth)
	east.position = Vector3(hw - bw / 2.0, bh / 2.0, 0.0)

	# Size the text to match border_thickness_v, then place it flat on the floor just inside the south border.
	# The south strip acts as an underline: the text bottom edge aligns with the strip's inner face (hd - bw),
	# so the center is offset inward by the size of the font.
	var tm := _area_name_mesh.mesh as TextMesh
	var text_z_offset = tm.font_size * tm.pixel_size
	tm.depth = bh
	_area_name_mesh.position = Vector3(0.0, bh / 2.0, hd - bw - text_z_offset)
