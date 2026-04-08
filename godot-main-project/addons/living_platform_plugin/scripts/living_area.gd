@tool
extends LivingItem

# Conceptually, an area is a set of items within a scene
class_name LivingArea


@export var visibility_state: LivingConstants.ItemVisibility

@export_tool_button("Update Item Visibility") var update_items_visibility_btn = update_items_visibility
@export_tool_button("Show All Items") var show_all_items_btn = show_all_items
@export_tool_button("Update Area Border") var update_area_btn = update_area

## The material to be used for the border
@export var border_material: Material
## The horizontal border thickness
@export var border_tickness_h: float = 0.1
## Th vertical border thickness
@export var border_thickness_v: float = 0.4
## The y position of the border. Useful if the visible florr is above or below the y=0 plane.
@export var border_y: float = 0.0
## A multiplier to add some margin to the borders and prevent it to stay attached to objects
@export var border_scale: float = 1.1

## Holds the 4 instances of the geometries showing the 4 border segments.
var _border_strips: Array = []  # Array of 4 MeshInstance3D forming the rectangular frame
## Transform to shift the border according to the AABB center
var _border_transform: Node3D 

## Default border width (X) when the AABB is not available.
const DEFAULT_BORDER_W = 2.0
## Default border depth (Z) when the AABB is not available.
const DEFAULT_BORDER_D = 1.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super._ready()

	_initialize_area_visualization()

	# update_area()

	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)

	update_area.call_deferred()


# func _enter_tree():
# 	get_tree().node_added.connect(_on_node_added)
# 	get_tree().node_removed.connect(_on_node_removed)


# func _exit_tree() -> void:
# 	get_tree().node_added.disconnect(_on_node_added)
# 	get_tree().node_removed.disconnect(_on_node_removed)


func _on_node_added(node: Node) -> void:
	if is_ancestor_of(node):
		if not is_node_ready(): return
		print("descendant added: ", node.name)
		update_area()


func _on_node_removed(node: Node) -> void:
	if is_ancestor_of(node):
		if not is_node_ready(): return
		print("descendant added: ", node.name)
		update_area()


func show_all_items():
	for c in self.get_children():
		if c is LivingItem:
			(c as LivingItem).set_visible(true)
	

## Gets the current AABB and updates the area visualization border accordingly
func update_items_visibility():
	for c in self.get_children():
		if c is LivingItem:
			var li = c as LivingItem
			var must_be_visible: bool = li.visibility & visibility_state
			c.set_visible(must_be_visible)


## Initializes the nodes needed to visualize the area
func _initialize_area_visualization() -> void:

	if self.border_material == null:
		self.border_material = StandardMaterial3D.new()
		self.border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_border_transform = Node3D.new()
	_border_strips.clear()
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = self.border_material
		mi.name = "AreaBorder-%s" % i
		_border_transform.add_child(mi)
		_border_strips.append(mi)
	
	add_child(_border_transform)


## Computes the AABB of the area and upadtes the area border visualization accordingly
func update_area() -> void:

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

	else:
		_resize_area_border(DEFAULT_BORDER_W, DEFAULT_BORDER_D)
		_border_transform.position = Vector3(0, self.border_y, 0)




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
