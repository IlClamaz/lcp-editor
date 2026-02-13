# This is the node type to be used as scene root.
# It contains the global variables used by the Living Items in the scene
@tool
extends Node3D

class_name LivingScene

@export var OMEKA_BASE_URL: String = "https://omekas.livingculture.it"

@export_tool_button("Refresh all Living Elements") var refresh_all_living_elements_btn = refresh_all_living_elements


# Recurse the whole scene 
func refresh_all_living_elements():
	var scene_root: Node = null
	if Engine.is_editor_hint():
		scene_root = get_tree().edited_scene_root
	else:
		scene_root = get_tree().current_scene
	
	refresh_all_living_elements_R(scene_root)


func refresh_all_living_elements_R(n: Node):
	
	if n is LivingElement:
		n.fetch_omeka_info()
	
	for c in n.get_children():
		refresh_all_living_elements_R(c)
