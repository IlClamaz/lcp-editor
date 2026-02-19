@tool
extends MeshInstance3D

class_name LivingText2

const DEFAULT_FONT_DEPTH: float = 0.05

## The child object that should be a flat surface on which to visualizize the text
@onready var background = $"001 - Didascalia 17022026_LCC"


@export var text_path: String = "res://addons/living_platform_plugin/scripts/living_text/lorem_ipsum.txt" : set = set_text_path
@export var loaded_text: String = "": set = set_text
@export var font_size: int = 32 : set = set_font_size
@export var font_depth: float = DEFAULT_FONT_DEPTH : set = set_font_depth
@export var text_color: Color = Color(0.9, 0.9, 0.9) : set = set_text_color
@export var text_alpha: float = 1.0: set = set_text_alpha
## The maximum background horizontal proportion that will be ocnvered by text
@export var background_x_proportion: float = 0.9 : set = set_background_x_proportion
## The maximum background vertical proportion that will be ocnvered by text
@export var background_y_proportion: float = 0.9 : set = set_background_y_proportion

## This is the node that will contain the text mesh and added as child of this node.
var _font_mesh_instance: MeshInstance3D = null
var _font_text_mesh: TextMesh = null
var _font_material: StandardMaterial3D = null

## Measured on ready. Will be used to resize the text node to have the text fitting the background
var _background_aabb: AABB 

# By default, shene entering the scene, the text will be loaded from a file pointed in text_path.
# You can skip by setting "use_text_path" to false in the constructor, and set the text directly later using "set_text()"
var use_text_path: bool = true


func _init(use_text_path: bool = true) -> void:
	
	self.use_text_path = use_text_path
	
	_font_material = StandardMaterial3D.new()
	_font_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH

	create_visualization()
	

func _ready():

	_background_aabb = LivingUtils.get_node_aabb(background)
	# print("BG AABB: ", _background_aabb)

	if use_text_path:
		load_text()


func set_text_path(value: String):
	text_path = value
	if is_inside_tree():  #  and loaded_text.is_empty() == false:
		# print("Loading text from ", text_path)
		load_text()


func load_text():

	if not FileAccess.file_exists(text_path):
		push_error("Text file not found: " + text_path)
		return

	var file = FileAccess.open(text_path, FileAccess.READ)
	var txt = file.get_as_text()
	file.close()
	
	self.set_text(txt)


func set_text(value: String):
	loaded_text = value

	if _font_mesh_instance:
		_font_text_mesh.text = loaded_text
		_update_geometries()


func set_text_alpha(f: float) -> void:
	text_alpha = f
	_font_material.albedo_color.a = f


func create_visualization():

	# Text mesh
	_font_text_mesh = TextMesh.new()
	_font_text_mesh.font_size = font_size
	_font_text_mesh.depth = font_depth
	_font_text_mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# The mesh instance carrying the text
	_font_mesh_instance = MeshInstance3D.new()
	_font_mesh_instance.mesh = _font_text_mesh
	_font_mesh_instance.material_override = _font_material
	add_child(_font_mesh_instance)
	
	
	if Engine.is_editor_hint():
		# DEBUG. Set the owner to make it visible in the scene dock and persist
		# mesh_instance.owner = get_tree().edited_scene_root
		pass
	
	# Default font (can be customized via theme/default font resource)
	var default_font = ThemeDB.fallback_font
	if default_font:
		_font_text_mesh.font = default_font
		
	_update_colors()
	_update_geometries()
	
	assert (_font_mesh_instance != null)
	assert (_font_text_mesh != null)
	assert (background != null)


func _update_geometries():

	# Update  size 
	var font_bounds = _font_text_mesh.get_aabb()
	# Pad for 5% of the text width/height
	#var x_padding = _background_aabb.size.x * 0.05
	#var y_padding = _background_aabb.size.y * 0.05
	#var padding = min(bounds.size.y, bounds.size.y) * 0.1
	
	var x_max = _background_aabb.size.x * background_x_proportion
	var y_max = _background_aabb.size.y * background_y_proportion
	

	var x_scale = 1.0
	if font_bounds.size.x > x_max:
		x_scale = x_max / font_bounds.size.x
	
	var y_scale = 1.0
	if font_bounds.size.y > y_max:
		y_scale = y_max / font_bounds.size.y

	# Resize and reposition the font node
	var min_scale = min(x_scale, y_scale)
	_font_mesh_instance.scale = Vector3(min_scale, min_scale, 1.0)
	# Move the text mesh to the left, because in left alignment the origin of the text geometry is x=0.	
	_font_mesh_instance.position = Vector3(
		- (font_bounds.size.x * x_scale) / 2,
		0,
		font_depth / 2.0
	)
	
	
func _update_colors():
	_font_material.albedo_color = text_color


func set_font_size(value: int):
	font_size = value

	_font_text_mesh.font_size = value
	_update_geometries()


func set_font_depth(value: float):
	font_depth = value

	_font_text_mesh.depth = value
	_update_geometries()


func set_text_color(value: Color):
	text_color = value
	_update_colors()


func set_background_x_proportion(v: float):
	background_x_proportion = v
	_update_geometries()


func set_background_y_proportion(v: float):
	background_y_proportion = v
	_update_geometries()
