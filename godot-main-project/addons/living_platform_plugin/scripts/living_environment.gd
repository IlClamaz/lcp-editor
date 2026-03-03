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

	assert(scene_root is LivingItem)

	# 1. Avvia la primissima scansione
	var fs := EditorInterface.get_resource_filesystem()
	fs.scan()
	
	while fs.is_scanning():
		await get_tree().process_frame

	var all_media_paths = get_all_media_paths()
	
	# 2. Troviamo i file di cui aspettare l'importazione
	var paths_to_wait: PackedStringArray = []
	for p in all_media_paths:
		var ext = p.get_extension().to_lower()
		if ext in ["glb", "gltf", "png", "jpg", "jpeg", "hdr", "exr"]:
			paths_to_wait.append(p)
			
	# 3. Aspettiamo l'ondata principale (i file .import)
	var all_ready = false
	var wait_loops = 0
	while not all_ready and wait_loops < 60: # Max 12 secondi
		all_ready = true
		for p in paths_to_wait:
			if not FileAccess.file_exists(p + ".import"):
				all_ready = false
				break
		if not all_ready:
			await get_tree().create_timer(0.2).timeout
			wait_loops += 1
			
	# Quando Godot importa un GLB, spesso estrae le sue texture interne 
	# e innesca autonomamente una SECONDA scansione dell'Editor.
	# Diamo mezzo secondo di respiro per farla partire...
	await get_tree().create_timer(0.5).timeout
	
	# ...e poi aspettiamo che finisca anche questa!
	while fs.is_scanning():
		await get_tree().process_frame
	
	# Un'ultimissima pausa per la cache dell'Editor
	await get_tree().create_timer(0.5).timeout
	# ----------------------------

	# Tutto è finalmente pronto, stabile e importato. Instanziamo!
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
