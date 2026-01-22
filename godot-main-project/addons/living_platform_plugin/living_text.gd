@tool
extends Node

class_name LivingText


@export var text_path: String = "user://example.txt" : set = set_text_path
@export var font_size: int = 32 : set = set_font_size
@export var font_depth: float = 0.01 : set = set_depth
@export var text_color: Color = Color(0.1, 0.1, 0.1) : set = set_text_color

var mesh_instance: MeshInstance3D = null
var text_mesh: TextMesh = null
var background: MeshInstance3D = null
var loaded_text: String = ""

#@export_storage var mesh_instance: MeshInstance3D = null
#@export_storage var text_mesh: TextMesh = null
#@export_storage var background: MeshInstance3D = null
#@export_storage var loaded_text: String = ""


const BACKGROUND_THICKNESS: float = 0.05

func _ready():
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
		_update_background_geometry()

func create_visualization():
	print("Visualization check.")

	# Needs to be created onyl the first time the object enters the scene.
	if mesh_instance != null:
		print("Visualization already there.")
		return
	
	# Text mesh
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	text_mesh = TextMesh.new()
	text_mesh.font_size = font_size
	text_mesh.depth = font_depth
	text_mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mesh_instance.mesh = text_mesh
	
	if Engine.is_editor_hint():
		# Important. Set the owner to make it visible in the scene dock and persist
		# mesh_instance.owner = get_tree().edited_scene_root
		pass
	
	# Default font (can be customized via theme/default font resource)
	var default_font = ThemeDB.fallback_font
	if default_font:
		text_mesh.font = default_font
	
	# Background rectangle (BoxMesh)
	background = MeshInstance3D.new()
	add_child(background)
	background.mesh = BoxMesh.new()
	background.mesh.size = Vector3(1, 1, BACKGROUND_THICKNESS)  # Adjust as needed
	
	if Engine.is_editor_hint():
		# Important. Set the owner to make it visible in the scene dock and persist
		# background.owner = get_tree().edited_scene_root
		pass

	_update_font_color()
	_update_background_geometry()
	
	assert (mesh_instance != null)
	assert (text_mesh != null)
	assert (background != null)

func _update_background_geometry():
	# Update background size based on text bounds
	var bounds = text_mesh.get_aabb()
	print("Bounds ", bounds)
	var padding = 0.2
	
	print("new val for x pos ", - bounds.size.x / 2)
	# Move the text mesh to the left, because in left alignment the origin of the text geometry is x=0.
	#mesh_instance.position.x = (- bounds.size.x / 2)
	#mesh_instance.position.z = font_depth / 2.0
	
	mesh_instance.position = Vector3(- bounds.size.x / 2, 0, font_depth / 2.0)
	print("new textmesh pos: ", mesh_instance.position)

	# Resizes the background
	var background_w = bounds.size.x + padding * 2
	var background_h = bounds.size.y + padding * 2
	background.mesh.size.x = background_w
	background.mesh.size.y = background_h
	background.position.x = 0 # background_w / 2 - padding
	background.position.y = 0
	
	# background.position.z = - font_depth / 2 - 0.03  # Behind text
	background.position.z = - BACKGROUND_THICKNESS / 2.0  # Behind text

func _update_font_color():
	
	if mesh_instance.material_override == null:
		var mat = StandardMaterial3D.new()
		mesh_instance.material_override = mat

	mesh_instance.material_override.albedo_color = text_color

func set_font_size(value: int):
	font_size = value
	if text_mesh:
		text_mesh.font_size = value
		_update_background_geometry()

func set_depth(value: float):
	font_depth = value
	if text_mesh:
		text_mesh.depth = value
		_update_background_geometry()

func set_text_color(value: Color):
	
	text_color = value

	_update_font_color()
