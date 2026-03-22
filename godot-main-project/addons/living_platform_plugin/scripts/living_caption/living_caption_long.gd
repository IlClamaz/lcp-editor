@tool
extends LivingCaption

class_name LivingCaptionLong

# The resource to instantiate the background geometry
# var background_long = preload("res://addons/living_platform_plugin/scripts/living_caption/001 - Didascalia 17022026_LCC.glb")
# var background_long = preload("res://addons/living_platform_plugin/scripts/living_caption/001a - Didascalia Grande 20260302_LCC.glb")
var background_long = preload("res://addons/living_platform_plugin/scripts/living_caption/CaptionLongBackground-centered.blend")

var _more_button: Label3D = null
var _more_button_area: Area3D = null
var _more_button_font_size: int = 24

var _overlay_text: String

var _overlay: LivingCaption = null

const DEFAULT_CATALOG_MISSING_TEXT = "No catalog info..."

## The default color for the overlay. The last value is the transparency factor (1.0 == opaque)
const OVERLAY_BG_COLOR := Color(0.15, 0.14, 0.10, 0.98)


func _init(use_text_path: bool = true, overlay_text = null) -> void:

	if overlay_text == null:
		_overlay_text = DEFAULT_CATALOG_MISSING_TEXT
	else:
		_overlay_text = overlay_text

	var bg = background_long.instantiate()

	super(bg, use_text_path)


func _ready():

	# Constants valid for the current background geometry.
	# To be adjusted if you change the background object.
	self.background_x_proportion = 0.85
	self.background_y_proportion = 0.85
	self.text_fit_mode = TextFitMode.WRAP
	self.font_size = 7

	_create_more_button()

	super._ready()

	# Position the button after the super _ready(), so that the background AABB is valid.
	_position_more_button()


func _create_more_button():

	_more_button = Label3D.new()
	_more_button.text = "More..."
	_more_button.font_size = _more_button_font_size
	_more_button.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_more_button.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(_more_button)

	# Clickable area attached to the label
	_more_button_area = Area3D.new()
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = BoxShape3D.new()
	_more_button_area.add_child(collision_shape)
	_more_button_area.input_event.connect(_on_more_button_input)
	_more_button.add_child(_more_button_area)


func _position_more_button():

	if _more_button == null:
		return

	var bg_aabb: AABB = LivingUtils.get_node_aabb(self.background)
	var right = bg_aabb.position.x + bg_aabb.size.x
	var top = bg_aabb.position.y + bg_aabb.size.y
	_more_button.position = Vector3(right, top, font_depth)

	# Wait another frame, so that the AABB of the label is correctly computed
	await get_tree().process_frame

	# Fit the collision box to the label's rendered AABB
	if _more_button_area != null:
		# var label_aabb = _more_button.get_aabb()
		var label_aabb = LivingUtils.get_node_aabb(_more_button)
		print("LABEL AABB ", label_aabb, label_aabb.size )
		var collision_shape = _more_button_area.get_child(0) as CollisionShape3D
		if collision_shape:
			var box = BoxShape3D.new()
			box.size = label_aabb.size + Vector3(0.0, 0.0, 0.02)
			print("BOX size ", box.size)
			collision_shape.shape = box
			collision_shape.position = label_aabb.get_center()


func _on_more_button_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_more_button_pressed()


func _on_more_button_pressed():

	# Toggle: if the overlay is visible, close it
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
		_more_button.text = "More..."
		return

	print("More selected.")

	var bg_aabb: AABB = LivingUtils.get_node_aabb(self.background)

	# Build a flat panel at 90% of the existing background size
	var overlay_bg = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(bg_aabb.size.x * 0.9, bg_aabb.size.y * 0.9, 0.01)
	var bg_material = StandardMaterial3D.new()
	bg_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_material.albedo_color = OVERLAY_BG_COLOR
	overlay_bg.mesh = box_mesh
	overlay_bg.material_override = bg_material

	# Create the overlay caption (no file loading) and place it in front of self
	_overlay = LivingCaption.new(overlay_bg, false)
	_overlay.text_fit_mode = TextFitMode.WRAP
	_overlay.font_size = self.font_size
	_overlay.background_x_proportion = 0.95
	_overlay.background_y_proportion = 0.95
	_overlay.position = Vector3(0.0, 0.0, 0.05)
	add_child(_overlay)

	# Set text after entering the tree so _update_geometries can read the AABB
	_overlay.set_text(_overlay_text)

	_more_button.text = "X"
