@tool
extends EditorPlugin

var LIVING_SCENE_CLASS_NAME = "LivingScene"
var LIVING_ITEM_CLASS_NAME = "LivingItem"
var LIVING_MEDIA_CLASS_NAME = "LivingMedia"
# The sub types of Living Media
var LIVING_IMAGE_CLASS_NAME = "LivingImage"
var LIVING_TEXT_CLASS_NAME = "LivingText"
var LIVING_VIDEO_CLASS_NAME = "LivingVideo"
# TODO - 3D object


func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	# Add the new type with a name, a parent type, a script and an icon.
	add_custom_type(LIVING_SCENE_CLASS_NAME, "Node3D", preload("living_scene.gd"), preload("LCLogo.png"))
	add_custom_type(LIVING_ITEM_CLASS_NAME, "Node", preload("living_item.gd"), preload("icon.svg"))
	add_custom_type(LIVING_MEDIA_CLASS_NAME, "Node3D", preload("living_media.gd"), preload("icon.svg"))
	add_custom_type(LIVING_IMAGE_CLASS_NAME, "MeshInstance3D", preload("living_image.gd"), preload("icon.svg"))
	add_custom_type(LIVING_TEXT_CLASS_NAME, "Node3D", preload("living_text.gd"), preload("icon.svg"))
	add_custom_type(LIVING_VIDEO_CLASS_NAME, "Sprite3D", preload("living_video.gd"), preload("icon.svg"))


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	# Always remember to remove it from the engine when deactivated.
	remove_custom_type(LIVING_VIDEO_CLASS_NAME)
	remove_custom_type(LIVING_TEXT_CLASS_NAME)
	remove_custom_type(LIVING_IMAGE_CLASS_NAME)
	remove_custom_type(LIVING_MEDIA_CLASS_NAME)
	remove_custom_type(LIVING_ITEM_CLASS_NAME)
	remove_custom_type(LIVING_SCENE_CLASS_NAME)
