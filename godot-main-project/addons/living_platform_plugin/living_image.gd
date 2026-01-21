@tool
extends MeshInstance3D
class_name LivingImage

@export var image_path: String = "":
	set(value):
		image_path = value
		_update_texture()

@export var pixels_per_unit: float = 1.0:  # Optional: Adjust scale (e.g., 0.01 for smaller)
	set(value):
		pixels_per_unit = value
		if has_node("."):  # Avoid init loop
			_update_texture()

var current_texture: Texture2D

func _ready():
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
	else:
		push_error("Image path '%s' doesn't exist " % image_path)
		current_texture = null
		mesh = null
		material_override = null
		
