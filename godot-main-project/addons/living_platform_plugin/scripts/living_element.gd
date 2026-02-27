@tool
extends LivingItem

class_name LivingElement


@export_group("DESCRIPTION")
@export var long_description_center_height: float = 1.7
@export var long_description_max_width: float = 2.0
@export var long_description_max_height: float = 2.5


# Set any of the given flags from the editor.
@export_flags(LivingConstants.ITEM_VISIBILITY_PRE_STR, LivingConstants.ITEM_VISIBILITY_POST_STR) var visibility: int = LivingConstants.ItemVisibility.PRE_EXPERIENCE | LivingConstants.ItemVisibility.POST_EXPERIENCE


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super._ready()
	
	# Set this "grouping" flag to catch the selection on this objects any time the user clicks on an object further down on the hierarchy.
	self.set_meta("_edit_group_", true)


func _enter_tree():
	self.add_to_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME)


func _exit_tree():
	self.add_to_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME)


func set_visible(v: bool):
	for c in get_children():
		if c is LivingItem:
			(c as LivingItem).visible = v


var description_text: LivingCaption = null


#
# LONG + CATALOG TEXT VISUALIZATION
#
const DESCRIPTION_SIDE_LEFT := -1
const DESCRIPTION_SIDE_RIGHT := +1

func create_description_node(text: String, side: int) -> void:

	_destroy_description_node()	
	assert (description_text == null)

	# print("CREATING LONG DESCRIPTION FOR ", self.name)

	if text == null or text.strip_edges() == "":
		return

	# This will be the AABB of this self object
	var combined_aabb: AABB = LivingUtils.get_node_aabb(self)
	var combined_aabb_center: Vector3 = combined_aabb.position + combined_aabb.size * 0.5

	# description_text = LivingText.new(false)
	description_text = living_caption_scene.instantiate()
	
	add_child(description_text)
	description_text.set_text(text)
	description_text.set_text_color(Color(0.9, 0.9, 0.9))
	# description_text.set_background_color(Color(0.18, 0.18, 0.18, 1.0))


	# var description_aabb = description_text.get_aabb()
	var description_aabb = LivingUtils.get_node_aabb(description_text)
	
	if description_aabb.size.x > long_description_max_width or description_aabb.size.y > long_description_max_height:
		var x_scale = long_description_max_width / description_aabb.size.x
		var y_scale = long_description_max_height / description_aabb.size.y
		var min_scale = min(x_scale, y_scale)
	
		description_aabb = LivingUtils.scale_aabb_around_center(description_aabb, min_scale)
		description_text.scale = Vector3(min_scale, min_scale, min_scale)
	
	# Compute to watch the text ortogonal on the right side
	# Strong assumption that the floor is always at 0 height
	var description_offset := Vector3(
		combined_aabb_center.x + (combined_aabb.size.x / 2.0) ,
		long_description_center_height - self.position.y,
		combined_aabb_center.z + (combined_aabb.size.z / 2.0) + (description_aabb.size.x / 2)
	)
	var description_rotation := Vector3(0.0, -90.0, 0)

	# Adjust for the left/right side
	description_offset.x = float(side) * description_offset.x
	description_rotation.y = float(side) * description_rotation.y

	# print("COMBINED AABB: ", combined_aabb)
	# print("COMBINED CENTER: ", combined_aabb_center)
	# print("OFFSET: ", description_offset)
	# print("ROT: ", description_rotation)
	
	description_text.position = description_offset
	description_text.rotation_degrees = description_rotation


func _destroy_description_node() -> void:

	if description_text:
		# print("DESTROYING LONG DESCRIPTION FOR ", self.name)
		description_text.free()
		description_text = null
