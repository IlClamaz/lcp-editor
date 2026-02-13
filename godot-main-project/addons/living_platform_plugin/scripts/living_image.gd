@tool
extends MeshInstance3D
class_name LivingImage

@export var image_path: String = "":
	set(value):
		image_path = value
		if is_node_ready():
			_update_texture()

@export var pixels_per_unit: float = 1.0:  # Optional: Adjust scale (e.g., 0.01 for smaller)
	set(value):
		pixels_per_unit = value
		if is_node_ready():
			_update_texture()

# This will contain the reference to the image 2D texture
var current_texture: Texture2D
# This will be added as child and will containg the box geometry acting as background
var background: MeshInstance3D = null

# The background thickness is computed as this factor of the video width
const BACKGROUND_THICKNESS_PROP: float = 0.01
# Absolute background padding size around the video area
const BACKGROUND_PADDING: float = 0.2


func _ready():
	# Background rectangle (BoxMesh)
	background = MeshInstance3D.new()
	background.mesh = BoxMesh.new()
	background.mesh.size = Vector3(1, 1, BACKGROUND_THICKNESS_PROP)  # Adjust as needed
	add_child(background)
	
	_update_texture()


func _update_texture():

	if ResourceLoader.exists(image_path):
		current_texture = load(image_path) as Texture2D

		if current_texture:
			var tex_size = current_texture.get_size()
			var quad_size = tex_size / pixels_per_unit
			var quad_mesh = QuadMesh.new()
			quad_mesh.size = quad_size
			mesh = quad_mesh
			
			var material = StandardMaterial3D.new()
			material.albedo_texture = current_texture
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material_override = material
			
			# Resizes the background
			var background_w = quad_size.x + BACKGROUND_PADDING * 2
			var background_h = quad_size.y + BACKGROUND_PADDING * 2
			var background_depth = background_w * BACKGROUND_THICKNESS_PROP
			background.mesh.size.x = background_w
			background.mesh.size.y = background_h
			background.mesh.size.z = background_depth
			background.position.x = 0
			background.position.y = 0
			background.position.z = - 1.01 * background_depth / 2.0  # Behind the image quad, with a additional epsilon to avoid z-fight
		else:
			push_error("Couldn't load imahe '%s'" % [image_path])
			
	else:
		push_error("Image path '%s' doesn't exist " % [image_path])
		current_texture = null
		mesh = null
		material_override = null
