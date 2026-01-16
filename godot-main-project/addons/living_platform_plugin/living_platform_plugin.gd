@tool
extends EditorPlugin

var LIVING_SCENE_CLASS_NAME = "LivingScene"
var LIVING_ITEM_CLASS_NAME = "LivingItem"
var LIVING_MEDIA_CLASS_NAME = "LivingMedia"

func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	# Add the new type with a name, a parent type, a script and an icon.
	add_custom_type(LIVING_SCENE_CLASS_NAME, "Node3D", preload("living_scene.gd"), preload("icon.svg"))
	add_custom_type(LIVING_ITEM_CLASS_NAME, "Node3D", preload("living_item.gd"), preload("icon.svg"))
	add_custom_type(LIVING_MEDIA_CLASS_NAME, "Node", preload("living_media.gd"), preload("icon.svg"))


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	# Always remember to remove it from the engine when deactivated.
	remove_custom_type(LIVING_MEDIA_CLASS_NAME)
	remove_custom_type(LIVING_ITEM_CLASS_NAME)
	remove_custom_type(LIVING_SCENE_CLASS_NAME)
