@tool
extends EditorPlugin

# Main hierarchy classes
var LIVING_ITEM_CLASS_NAME = "LivingItem"
var LIVING_ENVIRONMENT_CLASS_NAME = "LivingEnvironment"
var LIVING_AREA_CLASS_NAME = "LivingArea"
var LIVING_OBJECT_CLASS_NAME = "LivingObject"
# Classes for media visualization
var LIVING_IMAGE_CLASS_NAME = "LivingImage"
var LIVING_TEXT_CLASS_NAME = "LivingText"
var LIVING_VIDEO_CLASS_NAME = "LivingVideo"
var LIVING_3DMODEL_CLASS_NAME = "Living3DModel"
var LIVING_TARGET_CLASS_NAME = "LivingTarget"
var LIVING_3DMODEL_ANIMATED_CLASS_NAME = "Living3DModelAnimated"
var LIVING_CROWD_CLASS_NAME = "LivingCrowd"
var LIVING_SCENE_CLASS_NAME = "LivingScene"
var LIVING_CAPTION_CLASS_NAME = "LivingCaption"
var LIVING_CAPTION_LONG_CLASS_NAME = "LivingCaptionLong"
var LIVING_CAPTION_HUD_CLASS_NAME = "LivingCaptionHUD"
# Extra
var LIVING_STARGATE_CLASS_NAME = "LivingStargate"
var LIVING_AUDIO_OBJECT_CLASS_NAME = "LivingAudioObject"
var LIVING_3DMODEL_OBJECT_CLASS_NAME = "Living3DModelObject"
var LIVING_TARGET_OBJECT_CLASS_NAME = "LivingTargetObject"
var LIVING_3DMODEL_ANIMATED_OBJECT_CLASS_NAME = "Living3DModelAnimatedObject"
var LIVING_CROWD_OBJECT_CLASS_NAME = "LivingCrowdObject"
var LIVING_CONTAINER_MODEL_OBJECT_CLASS_NAME = "LivingContainerModelObject"
var LIVING_STARGATE_OBJECT_CLASS_NAME = "LivingStargateObject"
var LIVING_FLAT_MEDIA_OBJECT_CLASS_NAME = "LivingFlatMediaObject"
var LIVING_IMAGE_OBJECT_CLASS_NAME = "LivingImageObject"
var LIVING_VIDEO_OBJECT_CLASS_NAME = "LivingVideoObject"
var LIVING_SLIDESHOW_OBJECT_CLASS_NAME = "LivingSlideShowObject"
var LIVING_VIDEO360_OBJECT_CLASS_NAME = "LivingVideo360Object"
var LIVING_AUDIO_CLASS_NAME = "LivingAudio"


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
	add_custom_type(LIVING_ITEM_CLASS_NAME, "Node3D", preload("core/living_item.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_ENVIRONMENT_CLASS_NAME, LIVING_ITEM_CLASS_NAME, preload("core/living_environment.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_AREA_CLASS_NAME, LIVING_ITEM_CLASS_NAME, preload("core/living_area.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_OBJECT_CLASS_NAME, LIVING_ITEM_CLASS_NAME, preload("core/LivingObjects/living_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_AUDIO_OBJECT_CLASS_NAME, LIVING_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_audio_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_3DMODEL_OBJECT_CLASS_NAME, LIVING_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_3dmodel_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_TARGET_OBJECT_CLASS_NAME, LIVING_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_target_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_3DMODEL_ANIMATED_OBJECT_CLASS_NAME, LIVING_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_3dmodel_animated_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_CROWD_OBJECT_CLASS_NAME, LIVING_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_crowd_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_CONTAINER_MODEL_OBJECT_CLASS_NAME, LIVING_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_container_model_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_STARGATE_OBJECT_CLASS_NAME, LIVING_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_stargate_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_FLAT_MEDIA_OBJECT_CLASS_NAME, LIVING_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_flat_media_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_IMAGE_OBJECT_CLASS_NAME, LIVING_FLAT_MEDIA_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_image_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_VIDEO_OBJECT_CLASS_NAME, LIVING_FLAT_MEDIA_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_video_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_SLIDESHOW_OBJECT_CLASS_NAME, LIVING_FLAT_MEDIA_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_slideshow_object.gd"), preload("../LCLogo.png"))
	add_custom_type(LIVING_VIDEO360_OBJECT_CLASS_NAME, LIVING_OBJECT_CLASS_NAME, preload("core/LivingObjects/living_video360_object.gd"), preload("../LCLogo.png"))

	# Classes for media visualization
	add_custom_type(LIVING_IMAGE_CLASS_NAME, "MeshInstance3D", preload("media/image/living_image.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_SCENE_CLASS_NAME, "Node3D", preload("media/scene/living_scene.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_TEXT_CLASS_NAME, "MeshInstance3D", preload("media/text/living_text.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_VIDEO_CLASS_NAME, "Sprite3D", preload("media/video/living_video.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_3DMODEL_CLASS_NAME, "Node3D", preload("media/model3d/living_3dmodel.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_TARGET_CLASS_NAME, "Node3D", preload("media/target/living_target.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_3DMODEL_ANIMATED_CLASS_NAME, "CharacterBody3D", preload("media/model3d/living_3dmodel_animated.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_CROWD_CLASS_NAME, "Node3D", preload("media/crowd/living_crowd.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_STARGATE_CLASS_NAME, "Node3D", preload("media/stargate/living_stargate.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_AUDIO_CLASS_NAME, "AudioStreamPlayer3D", preload("media/audio/living_audio.gd"), preload("../icon.svg"))

	# Classes for captions and HUD
	add_custom_type(LIVING_CAPTION_CLASS_NAME, "Node3D", preload("ui/living_caption/living_caption.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_CAPTION_LONG_CLASS_NAME, LIVING_CAPTION_CLASS_NAME, preload("ui/living_caption/living_caption_long.gd"), preload("../icon.svg"))
	add_custom_type(LIVING_CAPTION_HUD_CLASS_NAME, LIVING_CAPTION_CLASS_NAME, preload("ui/living_caption/living_caption_hud.gd"), preload("../icon.svg"))

func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	# Always remember to remove it from the engine when deactivated.
	remove_custom_type(LIVING_AUDIO_CLASS_NAME)
	remove_custom_type(LIVING_STARGATE_CLASS_NAME)

	remove_custom_type(LIVING_CAPTION_HUD_CLASS_NAME)
	remove_custom_type(LIVING_CAPTION_LONG_CLASS_NAME)
	remove_custom_type(LIVING_CAPTION_CLASS_NAME)
	remove_custom_type(LIVING_TARGET_CLASS_NAME)
	remove_custom_type(LIVING_3DMODEL_CLASS_NAME)
	remove_custom_type(LIVING_VIDEO_CLASS_NAME)
	remove_custom_type(LIVING_TEXT_CLASS_NAME)
	remove_custom_type(LIVING_IMAGE_CLASS_NAME)

	remove_custom_type(LIVING_VIDEO360_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_SLIDESHOW_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_VIDEO_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_IMAGE_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_FLAT_MEDIA_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_3DMODEL_ANIMATED_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_CROWD_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_CONTAINER_MODEL_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_TARGET_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_3DMODEL_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_AUDIO_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_STARGATE_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_OBJECT_CLASS_NAME)
	remove_custom_type(LIVING_AREA_CLASS_NAME)
	remove_custom_type(LIVING_ENVIRONMENT_CLASS_NAME)
	remove_custom_type(LIVING_ITEM_CLASS_NAME)
