@tool
extends LivingItem

class_name LivingElement


# Set any of the given flags from the editor.
@export_flags(LivingConstants.ITEM_VISIBILITY_PRE_STR, LivingConstants.ITEM_VISIBILITY_POST_STR) var visibility: int = LivingConstants.ItemVisibility.PRE_EXPERIENCE | LivingConstants.ItemVisibility.POST_EXPERIENCE


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super._ready()
	
	# Set this "grouping" flag to catch the selection on this objects any time the user clicks on an object further down on the hierarchy.
	self.set_meta("_edit_group_", true)


func _enter_tree():
	super._enter_tree()
	
	self.add_to_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME)


func _exit_tree():
	super._exit_tree()
	
	self.add_to_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME)


func set_visible(v: bool):
	for c in get_children():
		if c is LivingItem:
			(c as LivingItem).visible = v
