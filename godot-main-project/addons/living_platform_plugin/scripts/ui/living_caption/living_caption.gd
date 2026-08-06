@tool
extends Node3D

class_name LivingCaption

const DEFAULT_FONT_DEPTH: float = 0.002
const CAPTION_FONT: Font = preload("res://addons/living_platform_plugin/scripts/ui/living_caption/malayalam-mn.ttf")

enum TextFitMode {SCALE, WRAP}

@export var text_path: String = "res://addons/living_platform_plugin/scripts/ui/living_caption/lorem_ipsum.txt" : set = set_text_path
@export var loaded_text: String = "": set = set_text
@export var font_size: int = 32 : set = set_font_size
@export var font_depth: float = DEFAULT_FONT_DEPTH : set = set_font_depth
@export var text_color: Color = Color(0.9, 0.9, 0.9) : set = set_text_color
@export var text_alpha: float = 1.0: set = set_text_alpha
## The maximum background horizontal proportion that will be covered by the text
@export var background_x_proportion: float = 0.9 : set = set_background_x_proportion
## The maximum background vertical proportion that will be covered by the text
@export var background_y_proportion: float = 0.9 : set = set_background_y_proportion
## If true, the text node will be resized when it exceeds the maximum horizontal of vertical area of the background allowed to be covered by the text.
## Can lead to very small fonts for very long lines.
#@export var auto_resize_text: bool = true
@export var text_fit_mode: TextFitMode = TextFitMode.SCALE : set = set_text_fit_mode

## This is the node that will contain the text mesh and added as child of this node.
var _font_mesh_instance: MeshInstance3D = null
var _font_text_mesh: TextMesh = null
var _font_material: StandardMaterial3D = null

## Holding the background object
var background: Node3D

# TODO -- if clicking the caption is unused, those vars might be deleted
var _click_body: StaticBody3D = null
var _click_shape: BoxShape3D = null

# By default, shene entering the scene, the text will be loaded from a file pointed in text_path.
# You can skip by setting "use_text_path" to false in the constructor, and set the text directly later using "set_text()"
var use_text_path: bool = true



enum VisibilityState {VISIBLE, FADING_OUT, FADED_OUT}

var _life_state: VisibilityState = VisibilityState.VISIBLE

const SHRINK_SPEED_FACTOR = 5.0


func _init(background: Node3D, use_text_path: bool = true) -> void:

	self.background = background
	 
	self.use_text_path = use_text_path
	
	_font_material = StandardMaterial3D.new()
	_font_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	_font_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_create_visualization()

	#
	# Initialize the collision face/volume for this caption, as happens for other 3d models, video, images, ...
	_click_body = StaticBody3D.new()
	_click_body.name = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE
	_click_body.collision_layer = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
	_click_body.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
	var collision_shape := CollisionShape3D.new()
	_click_shape = BoxShape3D.new()
	collision_shape.shape = _click_shape
	_click_body.add_child(collision_shape)
	self.background.add_child(_click_body)


func _ready():

	assert (background != null)

	if use_text_path:
		load_text()

	_update_colors()
	_update_geometries()

	var bg_aabb := LivingUtils.get_node_aabb(self.background)
	_click_shape.size = bg_aabb.size
	_click_body.position = bg_aabb.get_center()


func _process(delta: float) -> void:

	if _life_state != VisibilityState.FADING_OUT:
		return

	assert(_life_state == VisibilityState.FADING_OUT)

	var target_scale = Vector3.ZERO

	var current_scale: Vector3 = self.scale
	var new_scale = current_scale + (target_scale - current_scale) * delta * SHRINK_SPEED_FACTOR
	# print(current_scale, " --> ", new_scale)

	self.scale = new_scale

	if self.scale.length() < 0.01:
		self.queue_free()
		_life_state = VisibilityState.FADED_OUT


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

	assert (_font_mesh_instance != null)

	_font_text_mesh.text = loaded_text

	_update_geometries()


func set_text_alpha(f: float) -> void:
	text_alpha = f
	_font_material.albedo_color.a = f


func fade_out():
	# self.queue_free()
	# print("Starting fade-out for ", name)
	self._life_state = VisibilityState.FADING_OUT



func _create_visualization():

	# Shift the background position on the X/Y plane to be centered according to its AABB
	# self.background.position = Vector3(-self._background_aabb.size.x / 2, self._background_aabb.size.y / 2, 0.0)
	# print("BBB ", self.background.position)
	# Attach the background
	add_child(self.background)

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
	
	_font_text_mesh.font = CAPTION_FONT

	assert (_font_mesh_instance != null)
	assert (_font_text_mesh != null)


func _update_geometries():

	
	## Getting the current background AABB (when computing it in "_init()" or "_ready()", it is wrong).
	var _background_aabb: AABB = LivingUtils.get_node_aabb(self.background)
	var x_max = _background_aabb.size.x * background_x_proportion
	var y_max = _background_aabb.size.y * background_y_proportion

	var x_scale = 1.0
	var y_scale = 1.0

	match self.text_fit_mode:

		TextFitMode.SCALE:
			_font_text_mesh.autowrap_mode = TextServer.AUTOWRAP_OFF

			# Update size
			var font_bounds = _font_text_mesh.get_aabb()

			if font_bounds.size.x > x_max:
				x_scale = x_max / font_bounds.size.x
			
			if font_bounds.size.y > y_max:
				y_scale = y_max / font_bounds.size.y

			#print("BACKGROUND TR: ", self.background.transform)
			#print("BACKGROUND AABB RT: ", LivingUtils.get_node_aabb(self.background))
			#print("BACKGROUND AABB: ", _background_aabb)
			#print("FONT BOUNDS: ", font_bounds)
			#print("FONTS SCALE X/Y: ", x_scale, " / ", y_scale)

		
		TextFitMode.WRAP:
			_font_text_mesh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

			var text_w = x_max / _font_text_mesh.pixel_size
			_font_text_mesh.width = text_w
	
		_:
			push_error("TextFitMode %s not supported" % self.text_fit_mode)

	# Resize and reposition the font node
	var min_scale = min(x_scale, y_scale)
	_font_mesh_instance.scale = Vector3(min_scale, min_scale, 1.0)
	# Move the text mesh to the left, because in left alignment the origin of the text geometry is x=0.
	var font_bounds = _font_text_mesh.get_aabb()
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

func set_text_fit_mode(v: TextFitMode):
	text_fit_mode = v
	_update_geometries()
