@tool
extends EditorPlugin

# Main hierarchy classes
var LIVING_ITEM_CLASS_NAME = "LivingItem"
var LIVING_ENVIRONMENT_CLASS_NAME = "LivingEnvironment"
var LIVING_AREA_CLASS_NAME = "LivingArea"
var LIVING_ELEMENT_CLASS_NAME = "LivingElement"
# Classes for media visualization
var LIVING_IMAGE_CLASS_NAME = "LivingImage"
var LIVING_TEXT_CLASS_NAME = "LivingText"
var LIVING_VIDEO_CLASS_NAME = "LivingVideo"
var LIVING_3DMODEL_CLASS_NAME = "Living3DModel"
var LIVING_CAPTION_CLASS_NAME = "LivingCaption"
var LIVING_CAPTION_LONG_CLASS_NAME = "LivingCaptionLong"
var LIVING_CAPTION_HUD_CLASS_NAME = "LivingCaptionHUD"
# Extra
var LIVING_PORTAL_CLASS_NAME = "LivingPortal"


func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	# Add the new type with a name, a parent type, a script and an icon.
	# SceneItem and its subclasses
	add_custom_type(LIVING_ITEM_CLASS_NAME, "Node3D", preload("living_item.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_ENVIRONMENT_CLASS_NAME, LIVING_ITEM_CLASS_NAME, preload("living_environment.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_AREA_CLASS_NAME, LIVING_ITEM_CLASS_NAME, preload("living_area.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_ELEMENT_CLASS_NAME, LIVING_ITEM_CLASS_NAME, preload("living_element.gd"), preload("../LCLogo.png"))

	# Classes for media visualization
	add_custom_type(LIVING_IMAGE_CLASS_NAME, "MeshInstance3D", preload("living_image.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_TEXT_CLASS_NAME, "MeshInstance3D", preload("living_text.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_VIDEO_CLASS_NAME, "Sprite3D", preload("living_video.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_3DMODEL_CLASS_NAME, "Node3D", preload("living_3dmodel.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_CAPTION_CLASS_NAME, "Node3D", preload("living_caption/living_caption.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_CAPTION_LONG_CLASS_NAME, LIVING_CAPTION_CLASS_NAME, preload("living_caption/living_caption_long.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_CAPTION_HUD_CLASS_NAME, LIVING_CAPTION_CLASS_NAME, preload("living_caption/living_caption_hud.gd"), preload("../icon.svg"))

	add_custom_type(LIVING_PORTAL_CLASS_NAME, "Node3D", preload("living_portal.gd"), preload("../icon.svg"))


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	# Always remember to remove it from the engine when deactivated.
	remove_custom_type(LIVING_PORTAL_CLASS_NAME)

	remove_custom_type(LIVING_CAPTION_HUD_CLASS_NAME)
	remove_custom_type(LIVING_CAPTION_LONG_CLASS_NAME)
	remove_custom_type(LIVING_CAPTION_CLASS_NAME)
	remove_custom_type(LIVING_3DMODEL_CLASS_NAME)
	remove_custom_type(LIVING_VIDEO_CLASS_NAME)
	remove_custom_type(LIVING_TEXT_CLASS_NAME)
	remove_custom_type(LIVING_IMAGE_CLASS_NAME)

	remove_custom_type(LIVING_ELEMENT_CLASS_NAME)
	remove_custom_type(LIVING_AREA_CLASS_NAME)
	remove_custom_type(LIVING_ENVIRONMENT_CLASS_NAME)
	remove_custom_type(LIVING_ITEM_CLASS_NAME)
