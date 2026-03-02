@tool
extends LivingCaption

class_name LivingCaptionHud

# The resource to instantiate the background geometry
# var background_hud = preload("res://addons/living_platform_plugin/scripts/living_caption/001 - Didascalia 20260223_LCC.glb")
var background_hud = preload("res://addons/living_platform_plugin/scripts/living_caption/CaptionHUDBackground-centered.blend")



func _init(use_text_path: bool = true) -> void:

	var bg = background_hud.instantiate()
	
	# TEMP - Waiting for final working mesh
	#var bg := MeshInstance3D.new()
	#bg.mesh = BoxMesh.new()
	#bg.scale = Vector3(2, 0.25, 0.01)

	super(bg, use_text_path)


func _ready():
	
	self.background_x_proportion = 0.8
	self.background_y_proportion = 0.9

	super._ready()
