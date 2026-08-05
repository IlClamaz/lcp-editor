@tool
extends LivingCaption

class_name LivingCaptionHud
signal clicked

# The resource to instantiate the background geometry
# var background_hud = preload("res://addons/living_platform_plugin/scripts/ui/living_caption/001 - Didascalia 20260223_LCC.glb")
var background_hud = preload("res://addons/living_platform_plugin/scripts/ui/living_caption/CaptionHUDBackground-centered.glb")
var stargate_hud = preload("res://addons/living_platform_plugin/scripts/ui/living_caption/CaptionHUDStargate.glb")

func _init(use_text_path: bool = true, stargate_hud_bg: bool = false) -> void:

	var bg: Node
	if stargate_hud_bg:
		bg = stargate_hud.instantiate()
	else:
		bg = background_hud.instantiate()

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

	# TODO - remove listener of user click. Long texts will open together with the short text
	if _click_body and not _click_body.input_event.is_connected(_on_click_body_input_event):
		_click_body.input_event.connect(_on_click_body_input_event)


func set_display_text(value: String) -> void:
	set_text(value)


func _on_click_body_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
