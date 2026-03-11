# This is the node type to be used as scene root.
# It contains the global variables used by the Living Items in the scene
@tool
extends LivingItem

class_name LivingEnvironment

@export var OMEKA_BASE_URL: String = "https://omekas.livingculture.it"

@export var nextsave_pwd: String

@export_tool_button("(Re-)build Environment") var rebuild_environment_btn = rebuild_environment
@export_tool_button("Instantiate all Media") var instantiate_all_media_btn = instantiate_all_media
@export_tool_button("Refresh all Living Elements") var refresh_all_living_elements_btn = refresh_all_living_elements

@export_tool_button("Save/Upload scene to server") var upload_scene_btn = upload_scene
@export_tool_button("List scenes in server") var list_remote_scenes_btn = list_remote_scenes


signal scene_upload_success(save_name: String, remote_url: String)
signal scene_upload_error(reason: String)

signal scene_list_success(list: Array[Dictionary])
signal scene_list_error(reason: String)

signal scene_download_success(local_path: String)
signal scene_download_error(reason: String)

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


func _enter_tree():
	super._enter_tree()
	
	scene_upload_success.connect(_on_scene_upload_success, CONNECT_DEFERRED)
	scene_upload_error.connect(_on_scene_upload_error, CONNECT_DEFERRED)
	
	scene_list_success.connect(_on_scene_list_success, CONNECT_DEFERRED)
	scene_list_error.connect(_on_scene_list_error, CONNECT_DEFERRED)
	

func _exit_tree():
	super._exit_tree()
	
	scene_upload_success.disconnect(_on_scene_upload_success)
	scene_upload_error.disconnect(_on_scene_upload_error)

	scene_list_success.disconnect(_on_scene_list_success)
	scene_list_error.disconnect(_on_scene_list_error)


func _on_scene_upload_success(save_name: String, remote_url: String):

	print("Scene '%s' successfully uploaded to '%s'" % [save_name, remote_url])

func _on_scene_upload_error(err: String):
	
	push_error("Scene upload failed: %s" % err)


## Upload (PUT) the scene on MediumURI, which is supposed to be a writable directory.
func upload_scene():

	var scene_res_path := self.scene_file_path
	if scene_res_path == "":
		push_error("Scene has no file path (unsaved scene?)")
		return

	var local_path := ProjectSettings.globalize_path(scene_res_path)
	var remote_name := scene_res_path.get_file()
	var remote_dir_uri = self.medium_uri
	var remote_pwd = self.nextsave_pwd
	
	print("Uploading file '%s' to '%s'" % [local_path, remote_dir_uri])

	var uploader = HTTPUploader.new(
		remote_dir_uri,
		remote_pwd,
		local_path,
		remote_name,
		scene_upload_success,
		scene_upload_error
	)

	add_child(uploader)
	uploader.do_upload()


func _on_scene_list_success(file_list: Array[Dictionary]):
	# file_list: array with one entry (Dictionarfy) per file in the remote directory.
	# Example of entry:
	# {
	#   "href": "/public.php/dav/files/nDS4cZMJBAPXPiq/env_1687_2026-03-06T16-44-15.tscn",
	#   "name": "env_1687_2026-03-06T16-44-15.tscn",
	#   "displayname": "env_1687_2026-03-06T16-44-15.tscn",
	#   "size": 8906,
	#   "modified": "Fri, 06 Mar 2026 15:58:58 GMT",
	#   "content_type": "application/octet-stream",
	#   "type": "file"
	# }


	var remote_scenes = []

	for f in file_list:
		var file_name: String = f["name"]
		var file_type: String = f["type"]

		if not file_type == "file":
			continue
		
		if not file_name.ends_with(".tscn"):
			continue

		remote_scenes.append(f)
		
	print("Got list of %s files. Recognized %s scenes:" % [file_list.size(), remote_scenes.size()])
	for s in remote_scenes:
		print("- %s" % s)


func _on_scene_list_error(err: String):
	
	push_error("Scene list failed: %s" % err)


## List the content of the directory represented by the mediumURI
func list_remote_scenes():

	var remote_dir_uri = self.medium_uri
	var remote_pwd = self.nextsave_pwd

	var lister = HTTPLister.new(
		remote_dir_uri,
		remote_pwd,
		scene_list_success,
		scene_list_error
		)

	add_child(lister)
	lister.do_list()


func download_scene(remote_name: String):
	var local_dir = "res://curated_scenes/"
	if not DirAccess.dir_exists_absolute(local_dir):
		DirAccess.make_dir_recursive_absolute(local_dir)
		
	print("Downloading '%s' to '%s'" % [remote_name, local_dir])
	

	var downloader = HTTPDownloader.new(
		self.medium_uri, 
		local_dir, 
		"", # Nessun prefisso per le scene
		scene_download_success, 
		scene_download_error
	)
	
	# Impostiamo le variabili prima di avviarlo
	downloader.remote_pwd = self.nextsave_pwd
	downloader.target_remote_file = remote_name
	
	add_child(downloader)
	downloader.do_download()
