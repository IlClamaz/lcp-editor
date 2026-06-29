# Questo è il nodo da utilizzare come radice della scena.
# Contiene le variabili globali utilizzate dai Living Items nella scena.
@tool
extends LivingItem
class_name LivingEnvironment

@export var OMEKA_BASE_URL: String = "https://omekas.livingculture.it"
## Omeka events for this environment (filled on editor rebuild / restore).
@export var omeka_events: Array[LivingEvent] = []

var nextsave_pwd: String
var _rebuild_in_progress: bool = false
var _omeka_event_service := OmekaEventService.new()

## The path to the audio the will be played in loop when visualizing this environment
@export var ambient_sound_path: String
## stream player for looping ambient sounds
var _environment_stream_player: AudioStreamPlayer
## stream player for one-shot event triggered sounds
var _event_stream_player: AudioStreamPlayer

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

	# Initialized sound emitting nodes
	_environment_stream_player = AudioStreamPlayer.new()
	add_child(_environment_stream_player)
	_event_stream_player = AudioStreamPlayer.new()
	_event_stream_player.volume_db = -12  # TO FIX!!
	add_child(_event_stream_player)

	# Start playing back the 
	if not Engine.is_editor_hint() and ambient_sound_path != "":
		play_ambient_sound(ambient_sound_path)


func _enter_tree():
	scene_upload_success.connect(_on_scene_upload_success, CONNECT_DEFERRED)
	scene_upload_error.connect(_on_scene_upload_error, CONNECT_DEFERRED)
	scene_list_success.connect(_on_scene_list_success, CONNECT_DEFERRED)
	scene_list_error.connect(_on_scene_list_error, CONNECT_DEFERRED)


func _exit_tree():

	stop_ambient_sound()

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
	self.auto_fetch_metadata = true
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

	if Engine.is_editor_hint():
		await _get_events()

	# =======================================================
	# FASE 1.5: ATTESA IMPORTAZIONE
	# =======================================================
	print("LivingEnvironment: Download conclusi. Calcolo dei file da importare...")
	if Engine.is_editor_hint():
		var fs = _get_fs()
		if fs != null:
			var all_items = self.find_children("*", "LivingItem", true, true)
			all_items.append(self)
			
			# Contiamo quanti file devono essere importati
			var pending_files: Array[String] = []
			for item in all_items:
				var m_path = item.media_path
				var t_path = item.thumbnail_path
				var paths_to_check: Array[String] = [m_path, t_path]
				
				# Se è uno ZIP, controlliamo tutti i file estratti nella sua cartella!
				if item.media_type == "application/zip" and m_path != "":
					var extract_dir = m_path.get_base_dir()
					_collect_files_recursive(extract_dir, paths_to_check)
				
				for p in paths_to_check:
					if p != "" and FileAccess.file_exists(p):
						var ext = p.get_extension().to_lower()
						if ext in ["glb", "gltf", "png", "jpg", "jpeg", "hdr"]:
							# Se l'item ha appena scaricato roba nuova, 
							# distruggiamo la vecchia ricevuta di Godot. Lo obbligherà a importarlo.
							if item._must_reinstantiate_medium and FileAccess.file_exists(p + ".import"):
								DirAccess.remove_absolute(p + ".import")
								
							# Se il file .import manca, lo mettiamo nella lista dei "ricercati"
							if not FileAccess.file_exists(p + ".import"):
								if not pending_files.has(p): pending_files.append(p)

			# Se c'è almeno un file da importare, ci mettiamo in attesa blindata
			if pending_files.size() > 0:
				import_progress.emit("Verifying resources...")
				print("LivingEnvironment: In attesa dell'importazione fisica di %d file..." % pending_files.size())
				
				# Svegliamo l'Editor
				for p in pending_files: 
					fs.update_file(p)
				fs.scan()
				
				# Non ci fidiamo di Godot, guardiamo i file sul disco
				var timeout_counter = 0
				while true:
					var all_done = true
					for p in pending_files:
						if not FileAccess.file_exists(p + ".import"):
							all_done = false
							break
					
					# Usciamo se tutti i file .import sono stati creati (o dopo 60 secondi come sicurezza)
					if all_done or timeout_counter > 600: 
						break
						
					await get_tree().create_timer(0.1).timeout
					timeout_counter += 1

				print("LivingEnvironment: Tutte le risorse sono state importate con successo!")
			else:
				print("LivingEnvironment: Tutti i file sono già importati e pronti.")
	# =======================================================
	# FASE 2: Istanziazione
	# =======================================================
	print("LivingEnvironment: File pronti. Avvio FASE 2 (Istanziazione media)...")
	self.auto_fetch_metadata = false
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


func _get_events() -> void:
	if item_id <= 0:
		push_warning("LivingEnvironment: skip event sync — invalid item_id.")
		return

	var base_url := str(OMEKA_BASE_URL).strip_edges().trim_suffix("/")
	if base_url == "":
		push_warning("LivingEnvironment: skip event sync — OMEKA_BASE_URL is empty.")
		return

	var result := await _omeka_event_service.fetch_events_for_environment(
		self,
		base_url,
		item_id
	)
	if not result.get("ok", false):
		push_warning(
			"LivingEnvironment: event sync failed for id %d (%s)."
			% [item_id, str(result.get("error", "unknown error"))]
		)
		omeka_events.clear()
		return

	omeka_events = result.get("events", [])
	_omeka_event_service.print_events_to_console(omeka_events, item_id, title)
	notify_property_list_changed()

# ==============================================================================
# FUNZIONALITA' SALVATAGGIO (UPLOAD, DOWNLOAD E LISTA)
# ==============================================================================
func upload_scene(custom_file_path: String = ""):
	var path_to_upload = custom_file_path if custom_file_path != "" else self.scene_file_path
	if path_to_upload == "":
		push_error("Scene has no file path (unsaved scene?)")
		return

	var local_path := ProjectSettings.globalize_path(path_to_upload)
	var remote_name := path_to_upload.get_file()
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
	
func _collect_files_recursive(dir_path: String, out_array: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir_path): return
	var d = DirAccess.open(dir_path)
	if d:
		d.list_dir_begin()
		var file_name = d.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path = dir_path.path_join(file_name)
				if d.current_is_dir():
					_collect_files_recursive(full_path, out_array)
				else:
					out_array.append(full_path)
			file_name = d.get_next()
		d.list_dir_end()


# Funzioni helper per nascondere EditorInterface al compilatore del gioco esportato
func _get_fs():
	if not Engine.is_editor_hint(): return null
	
	# Creiamo un micro-script fantasma in RAM
	var script = GDScript.new()
	script.source_code = "func execute():\n\treturn EditorInterface.get_resource_filesystem()"
	script.reload() # Lo compiliamo al volo
	
	# Creiamo un'istanza e la eseguiamo
	var obj = script.new()
	return obj.execute()

func _mark_unsaved():
	if not Engine.is_editor_hint(): return
	
	var script = GDScript.new()
	script.source_code = "func execute():\n\tEditorInterface.mark_scene_as_unsaved()"
	script.reload()
	
	var obj = script.new()
	obj.execute()


# ==============================================================================
# AUDIO
# ==============================================================================

func play_ambient_sound(path: String) -> void:

	# Load the stream and configure it.
	var stream := (load(path) as AudioStream)
	if stream == null:
		push_error("LivingEnvironment: could not load ambient sound '%s'" % path)
		return

	print("Playing ambient sound ", stream, " loaded from ", stream.resource_path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)

	# Set the stream abnd play
	_environment_stream_player.stream = stream
	_environment_stream_player.play()


func stop_ambient_sound() -> void:
	print("Stopping ambient sound.")
	_environment_stream_player.stop()


func play_sound(stream: AudioStream) -> void:

	# Load the stream
	if stream == null:
		push_error("LivingEnvironment.play_sound: stream is null")
		return

	print("Playing event sound ", stream, " loaded from ", stream.resource_path)
	_event_stream_player.stream = stream
	_event_stream_player.play()
