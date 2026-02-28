# This is the node type to be used as scene root.
# It contains the global variables used by the Living Items in the scene
@tool
extends LivingItem

class_name LivingEnvironment

@export var OMEKA_BASE_URL: String = "https://omekas.livingculture.it"

@export_tool_button("(Re-)build Environment") var rebuild_environment_btn = rebuild_environment
@export_tool_button("Instantiate all Media") var instantiate_all_media_btn = instantiate_all_media
@export_tool_button("Refresh all Living Elements") var refresh_all_living_elements_btn = refresh_all_living_elements


func _ready() -> void:
	super._ready()

func _ensure_self_is_root() -> bool:

	var scene_root: Node = null
	if Engine.is_editor_hint():
		scene_root = get_tree().edited_scene_root
	else:
		scene_root = get_tree().current_scene

	if self == scene_root:
		return true

	push_error("LivingEnvironment is supposed to be the root. self is '%s', while root is '%s'" % [self.name, scene_root.name])
	return false
	

# Recurse the whole scene 
func refresh_all_living_elements():
	
	self.auto_instantiate_children = false
	self.auto_download_medium = false
	self.auto_instantiate_medium = false
	self.auto_recurse_children = true
	
	self.fetch_omeka_info()

	var scene_root: Node = null
	if Engine.is_editor_hint():
		scene_root = get_tree().edited_scene_root
	else:
		scene_root = get_tree().current_scene

	assert (self == scene_root)


func rebuild_environment():
	
	self.auto_instantiate_children = true
	self.auto_download_medium = true
	self.auto_instantiate_medium = false
	self.auto_recurse_children = true
	
	self.fetch_omeka_info()


func instantiate_all_media():
	
	var scene_root: Node = null
	if Engine.is_editor_hint():
		scene_root = get_tree().edited_scene_root
	else:
		scene_root = get_tree().current_scene

	# If it is a LivingEnvironment, it is also a LivingItem
	assert(scene_root is LivingItem)


	# Force re-scan of the freshly retrieved media
	var fs := EditorInterface.get_resource_filesystem()
	# Loop wait until other processes have finished scanning	fs.scan()
	fs.scan()
	# Loop until the current scan has finished
	print("SCANNING PROGRESS-PRE: ", fs.get_scanning_progress())
	while fs.is_scanning():
		print("SCANNING PROGRESS: ", fs.get_scanning_progress())
		await get_tree().process_frame
	print("SCANNING PROGRESS-POST: ", fs.get_scanning_progress())

	# Get a list of all media paths used in the scene
	var all_media_paths = get_all_media_paths()
	print("ALL PATHS", all_media_paths)
	
	# --- FILTRIAMO PER EVITARE REIMPORT ---
	var paths_to_reimport: PackedStringArray = []
	for p in all_media_paths:
		var ext = p.get_extension().to_lower()
		# Escludiamo zip, pck e i file video che non hanno un importer nativo
		if ext not in ["zip", "ogv", "mp4", "avi"]:
			paths_to_reimport.append(p)
			
	print("REIMPORTABLE PATHS", paths_to_reimport)
	
	# Diamo a Godot un attimo di respiro (mezzo secondo) per concludere
	# le sue importazioni automatiche di background innescate dallo scan()
	# evitando così l'errore "Attempted to call reimport_files() recursively"
	await get_tree().create_timer(0.5).timeout
	
	# Reimportiamo solo i file supportati dall'importer
	if paths_to_reimport.size() > 0:
		fs.reimport_files(paths_to_reimport)
	# ----------------------------------------

	# Recurse instantiation of all media
	instantiate_all_media_R(scene_root)


func instantiate_all_media_R(n: LivingItem):

	n.instantiate_medium()

	for child in n.get_children():
		if child is LivingItem:
			instantiate_all_media_R(child)


func get_all_media_paths() -> PackedStringArray:
	var out: PackedStringArray = []

	var scene_root: Node = null
	if Engine.is_editor_hint():
		scene_root = get_tree().edited_scene_root
	else:
		scene_root = get_tree().current_scene

	get_all_media_paths_R(scene_root, out)
	
	return out

func get_all_media_paths_R(n: LivingItem, acc: PackedStringArray) -> void:
	
	if n.media_path != "":
		acc.append(n.media_path)
	
	for child in n.get_children():
		if child is LivingItem:
			get_all_media_paths_R(child, acc)




# TODO - PUSH scene on MediumURI
