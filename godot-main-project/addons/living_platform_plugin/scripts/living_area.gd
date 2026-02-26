@tool
extends LivingItem

# Conceptually, an area is a set of items within a scene
class_name LivingArea


@export var visibility_state: LivingConstants.ItemVisibility

@export_tool_button("Update Item Visibility") var update_items_visibility_btn = update_items_visibility
@export_tool_button("Show All Items") var show_all_items_btn = show_all_items

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super._ready()

func show_all_items():
	for c in self.get_children():
		if c is LivingItem:
			(c as LivingItem).set_visible(true)
	

func update_items_visibility():
	for c in self.get_children():
		if c is LivingItem:
			var li = c as LivingItem
			var must_be_visible: bool = li.visibility & visibility_state
			c.set_visible(must_be_visible)
