@tool
extends LivingCaption

class_name LivingCaptionHud

# The resource to instantiate the background geometry
# var background_hud = preload("res://addons/living_platform_plugin/scripts/living_caption/001 - Didascalia 20260223_LCC.glb")
var background_hud = preload("res://addons/living_platform_plugin/scripts/living_caption/CaptionHUDBackground-centered.glb")

var _click_area: Area3D = null
var _click_shape: BoxShape3D = null


func _init(use_text_path: bool = true) -> void:

	var bg = background_hud.instantiate()

	# TEMP - Waiting for final working mesh
	#var bg := MeshInstance3D.new()
	#bg.mesh = BoxMesh.new()
	#bg.scale = Vector3(2, 0.25, 0.01)

	# Create a collision box of the same size of the background,
	# so that an input event is triggered when the user clicks on the HUD, as if it is a 3D button.
	_click_area = Area3D.new()
	_click_area.name = "ClickArea"
	var collision_shape := CollisionShape3D.new()
	_click_shape = BoxShape3D.new()
	collision_shape.shape = _click_shape
	_click_area.add_child(collision_shape)

	super(bg, use_text_path)

	add_child(_click_area)


func _ready():

	self.background_x_proportion = 0.8
	self.background_y_proportion = 0.9

	super._ready()

	# Size and center the collision box to match the background AABB
	var aabb := LivingUtils.get_node_aabb(self.background)
	_click_shape.size = aabb.size
	_click_area.position = aabb.get_center()
