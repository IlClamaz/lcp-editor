@tool
extends MeshInstance3D

class_name LivingText

const BACKGROUND_THICKNESS: float = 0.05

@export var text_path: String = "user://example.txt" : set = set_text_path
@export var font_size: int = 32 : set = set_font_size
@export var font_depth: float = BACKGROUND_THICKNESS : set = set_depth
@export var text_color: Color = Color(0.1, 0.1, 0.1) : set = set_text_color

var mesh_instance: MeshInstance3D = null
var text_mesh: TextMesh = null
var background: MeshInstance3D = null
var loaded_text: String = ""


func _ready():

	background = self

	create_visualization()
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
	loaded_text = file.get_as_text()
	file.close()
	if mesh_instance:
		text_mesh.text = loaded_text
		_update_geometries()

func create_visualization():

	# Text mesh
	text_mesh = TextMesh.new()
	text_mesh.font_size = font_size
	text_mesh.depth = font_depth
	text_mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# The mesh instance carrying the text
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = text_mesh
	add_child(mesh_instance)
	
	
	if Engine.is_editor_hint():
		# DEBUG. Set the owner to make it visible in the scene dock and persist
		# mesh_instance.owner = get_tree().edited_scene_root
		pass
	
	# Default font (can be customized via theme/default font resource)
	var default_font = ThemeDB.fallback_font
	if default_font:
		text_mesh.font = default_font
	
	# Background rectangle (BoxMesh)
	background.mesh = BoxMesh.new()
	background.mesh.size = Vector3(1, 1, BACKGROUND_THICKNESS)  # Adjust as needed
	
	_update_font_color()
	_update_geometries()
	
	assert (mesh_instance != null)
	assert (text_mesh != null)
	assert (background != null)


func _update_geometries():

	# Update  size 
	var bounds = text_mesh.get_aabb()
	# Pad for 5% of the text width
	var padding = bounds.size.x * 0.05
	
	# Move the text mesh to the left, because in left alignment the origin of the text geometry is x=0.	
	mesh_instance.position = Vector3(- bounds.size.x / 2, 0, font_depth / 2.0)
	print("new textmesh pos: ", mesh_instance.position)

	# Resizes the background based on text bounds
	var background_w = bounds.size.x + padding * 2
	var background_h = bounds.size.y + padding * 2
	background.mesh.size.x = background_w
	background.mesh.size.y = background_h
	

func _update_font_color():
	
	if mesh_instance.material_override == null:
		var mat = StandardMaterial3D.new()
		mesh_instance.material_override = mat

	mesh_instance.material_override.albedo_color = text_color


func set_font_size(value: int):
	font_size = value
	if text_mesh:
		text_mesh.font_size = value
		_update_geometries()


func set_depth(value: float):
	font_depth = value
	if text_mesh:
		text_mesh.depth = value
		_update_geometries()


func set_text_color(value: Color):
	
	text_color = value
	_update_font_color()
