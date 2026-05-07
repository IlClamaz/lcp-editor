@tool
extends Node3D

class_name Living3DModel

@export var model_path: String = ""

@export_tool_button("Visualize 3D model") var load_model_btn = load_model


## Cache to remember if the collision geometry was already calculated.
var collision_shapes_created: bool = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	## Create the model node and adds it as child
	var scene_root := load_model()

	if not collision_shapes_created:
		print("Finding collision shapes for %s" % self.name)

		# Front faces
		var faces = scene_root.find_children(LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE, "MeshInstance3D", true, false)
		faces += scene_root.find_children(LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE.to_lower(), "MeshInstance3D", true, false)
		for face in faces:
			var child_mesh := face as MeshInstance3D
			print("Found Face '%s'" % child_mesh.name)
			# create_trimesh_collision() adds a StaticBody3D sibling automatically
			#child_mesh.create_trimesh_collision()
			# Use create_convex_collision() instead for a faster/simpler convex hull.
			child_mesh.create_convex_collision(true, false)
			
			for subchild in child_mesh.find_children("*", "CollisionObject3D", true, false):
				var collision_obj := subchild as CollisionObject3D
				collision_obj.collision_layer = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
				collision_obj.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER

		# Area triggers
		var triggers = scene_root.find_children(LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_NODE, "MeshInstance3D", true, false)
		triggers += scene_root.find_children(LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_NODE.to_lower(), "MeshInstance3D", true, false)
		for trigger in triggers:
			var child_mesh := trigger as MeshInstance3D
			print("Found Trigger '%s'" % child_mesh.name)
			# create_trimesh_collision() adds a StaticBody3D sibling automatically
			#child_mesh.create_trimesh_collision()
			# Use create_convex_collision() instead for a faster/simpler convex hull.
			child_mesh.create_convex_collision(true, false)

			for subchild in child_mesh.find_children("*", "CollisionObject3D", true, false):
				var collision_obj := subchild as CollisionObject3D
				collision_obj.collision_layer = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
				collision_obj.collision_mask = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
				collision_obj.input_ray_pickable = false 

		# Volume triggers
		var volumes = scene_root.find_children(LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_NODE, "MeshInstance3D", true, false)
		volumes += scene_root.find_children(LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_NODE.to_lower(), "MeshInstance3D", true, false)
		for volume in volumes:
			var child_mesh := volume as MeshInstance3D
			print("Found Volume '%s'" % child_mesh.name)

			child_mesh.create_convex_collision(true, false)

			for subchild in child_mesh.find_children("*", "CollisionObject3D", true, false):
				var collision_obj := subchild as CollisionObject3D
				if not scene_root.get_parent().get_parent().name.to_lower().contains("aux"):  ##### TO FIXXX!!!!
					collision_obj.collision_layer = LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_LAYER | 1
				else:
					collision_obj.collision_layer = LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_LAYER
				collision_obj.collision_mask = LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_LAYER

		collision_shapes_created = true


func _print_state_info(s: GLTFState):
	print(s.base_path, s.filename, s.copyright, s.bake_fps, s.major_version, s.minor_version, s.json)
	print(s.json)


func load_model() -> Node3D:
	
	# Remove all children first
	for child in get_children():
		child.queue_free()
	
	# Internal vs. External: Use load() or preload() for files already inside your res:// folder. If you are trying to load a file from the user's desktop (outside the game folder) at runtime, you'll need to use GLTFDocument and GLTFState classes instead.
	var model_root: Node3D = null
	if model_path.begins_with("res://"):
		print("Loading from resources ...")
		model_root = load_model_from_res()
	else:
		print("Loading from file ...")
		model_root = load_model_from_file()

	if model_root:
		print("Adding GLTF obj ", model_root)
		add_child(model_root)
		# Optional: Position or scale the model
		model_root.position = Vector3.ZERO
		model_root.scale = Vector3.ONE
		
	else:
		push_error("Failed to load 3D model from path ", model_path)

	return model_root


func load_model_from_res() -> Node3D:
	# 1. Check if the file exists to avoid errors
	if not ResourceLoader.exists(model_path):
		print("Error: File not found at ", model_path)
		return

	# 2. Load the resource as a PackedScene
	var model_scene = load(model_path)
	
	var model_root = null
	
	if model_scene is PackedScene:
		# 3. Instance the scene
		model_root = model_scene.instantiate()
		print("Model loaded successfully!")
		
	else:
		print("Error: Resource at path is not a 3D scene.")
	
	return model_root


func load_model_from_file() -> Node3D:

	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
		
	var error := gltf_doc.append_from_file(model_path, gltf_state)
	if error != OK:
		push_error("Failed to load GLB: " + gltf_state.get_message() if gltf_state.has_method("get_message") else "Error code: " + str(error))
		return null

	# print("State: ")
	# _print_state_info(gltf_state)
	
	var model_root := gltf_doc.generate_scene(gltf_state)
	
	# Traverse the tree and convert ImporterMeshes to standard Meshes
	_convert_to_runtime_glb_nodes(model_root)

	if not model_root:
		push_error("Failed to generate scene from GLTF state")
	
	return model_root


# This function recursively finds ImporterMeshInstance3D and replaces it 
# with a standard MeshInstance3D that the renderer can see.
func _convert_to_runtime_glb_nodes(node: Node):
	print("Converting meshes for node ", node.name)
	if node is ImporterMeshInstance3D:
		var mesh_instance = MeshInstance3D.new()
		
		# Get the actual renderable Mesh from the ImporterMesh
		if node.mesh:
			mesh_instance.mesh = node.mesh.get_mesh() 
		
		mesh_instance.skin = node.skin
		# mesh_instance.skeleton = node.skeleton
		mesh_instance.name = node.name
		mesh_instance.transform = node.transform
		
		# Swap the nodes
		var parent = node.get_parent()
		if parent:
			parent.add_child(mesh_instance)
			parent.remove_child(node)
			node.queue_free()
			# Continue traversing from the new node
			node = mesh_instance 

	# Continue down the tree
	for child in node.get_children():
		_convert_to_runtime_glb_nodes(child)
