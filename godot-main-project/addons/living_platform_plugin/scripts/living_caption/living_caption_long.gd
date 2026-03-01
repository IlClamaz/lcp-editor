@tool
extends LivingCaption

class_name LivingCaptionLong

# The resource to instantiate the background geometry
var background_long = preload("res://addons/living_platform_plugin/scripts/living_caption/001 - Didascalia 17022026_LCC.glb")


func _init(use_text_path: bool = true) -> void:

	var bg = background_long.instantiate()

	super(bg, use_text_path)


func _ready():

	self.background_x_proportion = 0.75
	self.background_y_proportion = 0.75

	super._ready()
