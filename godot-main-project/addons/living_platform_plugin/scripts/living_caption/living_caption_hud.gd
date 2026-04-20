@tool
extends LivingCaption

class_name LivingCaptionHud

# The resource to instantiate the background geometry
# var background_hud = preload("res://addons/living_platform_plugin/scripts/living_caption/001 - Didascalia 20260223_LCC.glb")
var background_hud = preload("res://addons/living_platform_plugin/scripts/living_caption/CaptionHUDBackground-centered.glb")

func _init(use_text_path: bool = true) -> void:

	var bg = background_hud.instantiate()

	# TEMP - Waiting for final working mesh
	#var bg := MeshInstance3D.new()
	#bg.mesh = BoxMesh.new()
	#bg.scale = Vector3(2, 0.25, 0.01)

	# Use find_children to recursively collect all MeshInstance3D nodes and then set each surface's material to unshaded.
	for node in bg.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(i)
			if mat is BaseMaterial3D:
				var mat_copy := mat.duplicate() as BaseMaterial3D
				mat_copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mi.set_surface_override_material(i, mat_copy)

	super(bg, use_text_path)


func _ready():

	self.background_x_proportion = 0.8
	self.background_y_proportion = 0.9

	super._ready()
