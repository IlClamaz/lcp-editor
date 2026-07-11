@tool
extends LivingObject
class_name LivingContainerModelObject

# Typed parent for Omeka "ModelloContenitore". Medium child is LivingScene.


func get_living_scene_child() -> LivingScene:
	for child in get_children():
		if child is LivingScene:
			return child as LivingScene
	return null
