@tool
extends LivingCaption

class_name LivingCaptionLong

# The resource to instantiate the background geometry
# var background_long = preload("res://addons/living_platform_plugin/scripts/living_caption/001 - Didascalia 17022026_LCC.glb")
# var background_long = preload("res://addons/living_platform_plugin/scripts/living_caption/001a - Didascalia Grande 20260302_LCC.glb")
var background_long = preload("res://addons/living_platform_plugin/scripts/living_caption/CaptionLongBackground-centered.blend")

func _init(use_text_path: bool = true) -> void:

	var bg = background_long.instantiate()

	super(bg, use_text_path)


func _ready():

	self.background_x_proportion = 0.85
	self.background_y_proportion = 0.85

	super._ready()
