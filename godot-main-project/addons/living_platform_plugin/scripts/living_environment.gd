# Questo è il nodo da utilizzare come radice della scena.
# Contiene le variabili globali utilizzate dai Living Items nella scena.
@tool
extends LivingItem
class_name LivingEnvironment

@export var OMEKA_BASE_URL: String = "https://omekas.livingculture.it"

var nextsave_pwd: String
var _rebuild_in_progress: bool = false

# ==============================================================================
# CONTROLLI EDITOR
# ==============================================================================
@export_tool_button("(Re-)build Environment") var rebuild_environment_btn = rebuild_environment
@export_tool_button("Save/Upload scene to server") var upload_scene_btn = upload_scene
@export_tool_button("List scenes in server") var list_remote_scenes_btn = list_remote_scenes

# ==============================================================================
# SEGNALI DI RETE
# ==============================================================================
signal scene_upload_success(save_name: String, remote_url: String)
signal scene_upload_error(reason: String)

signal scene_list_success(list: Array[Dictionary])
signal scene_list_error(reason: String)

signal scene_download_success(local_path: String)
signal scene_download_error(reason: String)

# ==============================================================================
# LIFECYCLE
# ==============================================================================
func _ready() -> void:
	super._ready()

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

# ==============================================================================
# FLUSSO DI RICOSTRUZIONE
# ==============================================================================
func rebuild_environment():
	# Guardia anti-loop: evita rebuild concorrenti/duplicati.
	if _rebuild_in_progress:
		print("LivingEnvironment: rebuild già in corso, ignoro richiesta duplicata.")
		return
	_rebuild_in_progress = true
	
	if build_finished.is_connected(_on_rebuild_guard_finished):
		build_finished.disconnect(_on_rebuild_guard_finished)
	build_finished.connect(_on_rebuild_guard_finished, CONNECT_ONE_SHOT)
	
	# Passa il testimone al Flusso Master in living_item.gd
	self.auto_instantiate_children = true
	self.auto_download_medium = true
	self.auto_instantiate_medium = true
	self.auto_recurse_children = true
	
	self.fetch_omeka_info()

func _on_rebuild_guard_finished(_success: bool) -> void:
	_rebuild_in_progress = false

# ==============================================================================
# FUNZIONALITA' SALVATAGGIO (UPLOAD, DOWNLOAD E LISTA)
# ==============================================================================
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

func _on_scene_upload_success(save_name: String, remote_url: String):
	print("Scene '%s' successfully uploaded to '%s'" % [save_name, remote_url])

func _on_scene_upload_error(err: String):
	push_error("Scene upload failed: %s" % err)

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

func _on_scene_list_success(file_list: Array[Dictionary]):
	var remote_scenes = []
	for f in file_list:
		var file_name: String = f["name"]
		var file_type: String = f["type"]

		if not file_type == "file": continue
		if not file_name.ends_with(".tscn"): continue

		remote_scenes.append(f)
		
	print("Got list of %s files. Recognized %s scenes:" % [file_list.size(), remote_scenes.size()])
	for s in remote_scenes:
		print("- %s" % s)

func _on_scene_list_error(err: String):
	push_error("Scene list failed: %s" % err)

func download_scene(remote_name: String):
	var local_dir = "res://curated_scenes/"
	if not DirAccess.dir_exists_absolute(local_dir):
		DirAccess.make_dir_recursive_absolute(local_dir)
		
	print("Downloading '%s' to '%s'" % [remote_name, local_dir])
	
	var downloader = HTTPDownloader.new(
		self.medium_uri, 
		local_dir, 
		"", 
		scene_download_success, 
		scene_download_error
	)
	
	downloader.remote_pwd = self.nextsave_pwd
	downloader.target_remote_file = remote_name
	add_child(downloader)
	downloader.do_download()