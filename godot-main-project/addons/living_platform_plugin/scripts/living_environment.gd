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

signal rebuild_completed(success: bool)
signal import_progress(text: String)

# ==============================================================================
# LIFECYCLE
# ==============================================================================
func _ready() -> void:
	super._ready()

func _enter_tree():
	scene_upload_success.connect(_on_scene_upload_success, CONNECT_DEFERRED)
	scene_upload_error.connect(_on_scene_upload_error, CONNECT_DEFERRED)
	scene_list_success.connect(_on_scene_list_success, CONNECT_DEFERRED)
	scene_list_error.connect(_on_scene_list_error, CONNECT_DEFERRED)

func _exit_tree():
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
	if _rebuild_in_progress:
		print("LivingEnvironment: rebuild già in corso, ignoro richiesta duplicata.")
		return
	_rebuild_in_progress = true
	
	if build_finished.is_connected(_on_rebuild_guard_finished):
		build_finished.disconnect(_on_rebuild_guard_finished)
	build_finished.connect(_on_rebuild_guard_finished, CONNECT_ONE_SHOT)

	# =======================================================
	# FASE 1: Fetch e Download
	# =======================================================
	self.auto_instantiate_children = true
	self.auto_download_medium = true
	self.auto_instantiate_medium = false
	self.auto_recurse_children = true
	
	print("LivingEnvironment: Avvio FASE 1 (Fetch e Download)...")
	self.fetch_omeka_info()

	var all_finished = false
	while not all_finished:
		await get_tree().process_frame
		await get_tree().process_frame

		var all_items = self.find_children("*", "LivingItem", true, true)
		all_items.append(self)
		var finished_count = 0
		for item in all_items:
			if item.build_state == BuildState.READY or item.build_state == BuildState.ERROR:
				finished_count += 1

		if all_items.size() > 0 and finished_count == all_items.size():
			all_finished = true

	# =======================================================
	# FASE 1.5: ATTESA IMPORTAZIONE
	# =======================================================
	print("LivingEnvironment: Download conclusi. Calcolo dei file da importare...")
	if Engine.is_editor_hint():
		var fs = EditorInterface.get_resource_filesystem()
		if fs != null:
			var all_items = self.find_children("*", "LivingItem", true, true)
			all_items.append(self)
			
			# Contiamo quanti file devono essere importati
			var pending_files: Array[String] = []
			for item in all_items:
				var m_path = item.media_path
				var t_path = item.thumbnail_path
				
				for p in [m_path, t_path]:
					if p != "" and FileAccess.file_exists(p):
						var ext = p.get_extension().to_lower()
						# Se necessita di import e non lo ha ancora, lo mettiamo in lista
						if ext in ["glb", "gltf", "png", "jpg", "jpeg"] and not FileAccess.file_exists(p + ".import"):
							if not pending_files.has(p): pending_files.append(p)
			
			# Se c'è almeno un file da importare, ci mettiamo in ascolto
			if pending_files.size() > 0:
				var total_to_import = pending_files.size()
				import_progress.emit("Importazione 0/%d..." % total_to_import)
				print("LivingEnvironment: In attesa del re-import esatto di %d risorse..." % pending_files.size())
				
				for p in pending_files: 
					fs.update_file(p)
				
				var state = {"finished": false}
				
				# Questa callback si attiva automaticamente quando Godot importa una risorsa
				var on_reimport = func(resources: PackedStringArray):
					# Depenniamo il file dalla lista
					for r in resources: pending_files.erase(r) 
					
					# Se la lista è vuota, abbiamo finito
					if pending_files.is_empty(): state["finished"] = true

				if not fs.resources_reimported.is_connected(on_reimport):
					fs.resources_reimported.connect(on_reimport)
				
				if not fs.is_scanning(): 
					fs.scan()
				
				# Aspettiamo finché la lista non è vuota
				while not state["finished"]: 
					await get_tree().process_frame
					var done = total_to_import - pending_files.size()
					import_progress.emit("Importazione %d/%d..." % [done, total_to_import])

				# Pulizia
				if fs.resources_reimported.is_connected(on_reimport):
					fs.resources_reimported.disconnect(on_reimport)
					
				print("LivingEnvironment: Tutte le risorse sono state importate con successo!")
			else:
				print("LivingEnvironment: Tutti i file sono già importati e pronti.")

	# =======================================================
	# FASE 2: Istanziazione
	# =======================================================
	print("LivingEnvironment: File pronti. Avvio FASE 2 (Istanziazione media)...")
	self.auto_instantiate_children = false
	self.auto_download_medium = false
	self.auto_instantiate_medium = true
	self.auto_recurse_children = true	
	
	# Aspettiamo che il giro di istanziazione sia totalmente finito, quando lo è lanciamo il segnale
	self.build_finished.connect(func(_succ: bool):
		rebuild_completed.emit(true)
	, CONNECT_ONE_SHOT)
	
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