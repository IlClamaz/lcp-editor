# This is the node type to be used as scene root.
# It contains the global variables used by the Living Items in the scene
@tool
extends LivingItem

class_name LivingEnvironment

@export var OMEKA_BASE_URL: String = "https://omekas.livingculture.it"

@export_tool_button("(Re-)build Environment") var rebuild_environment_btn = rebuild_environment
@export_tool_button("Refresh all Living Elements") var refresh_all_living_elements_btn = refresh_all_living_elements


func _ensure_self_is_root() -> bool:

	var scene_root: Node = null
	if Engine.is_editor_hint():
		scene_root = get_tree().edited_scene_root
	else:
		scene_root = get_tree().current_scene

	if self == scene_root:
		return true

	push_error("LivingEnvironment is supposed to be the root. slef is '%s', while root is '%s'" % [self.name, scene_root.name])
	return false
	

# Recurse the whole scene 
func refresh_all_living_elements():
	
	self.auto_instantiate_children = false
	self.auto_download_medium = false
	self.auto_instantiate_medium = false
	self.auto_recurse_children = true
	
	self.fetch_omeka_info()

	var scene_root: Node = null
	if Engine.is_editor_hint():
		scene_root = get_tree().edited_scene_root
	else:
		scene_root = get_tree().current_scene

	assert (self == scene_root)


func rebuild_environment():
	
	self.auto_instantiate_children = true
	self.auto_download_medium = true
	self.auto_instantiate_medium = true
	self.auto_recurse_children = true
	
	self.fetch_omeka_info()


# TODO - PUSH scene on MediumURI
