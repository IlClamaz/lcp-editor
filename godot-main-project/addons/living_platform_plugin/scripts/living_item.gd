@tool
extends Node3D

class_name LivingItem

var MEDIA_SAVE_PATH: String = "res://downloaded_living_media"

const OMEKA_TITLE_MAX_LEN: int = 200

## The prototype scene to instantiate video players
var living_video_player_scene = preload("res://addons/living_platform_plugin/scripts/living_video.tscn")

# Main OmekaS properties
@export var item_id: int = 0

@export_group("OMEKAS")
@export var title: String = ""
@export var modified: String = ""
@export_multiline var short_description: String = ""
@export_multiline var long_description: String = ""
@export_multiline var catalog_description: String = ""
@export var resource_class: int = 0
@export var components: Array[int] = []
@export var areas: Array[int] = []
@export var medium_uri: String = ""
@export var thumbnail_uri: String = ""

# ------------------------------------------------------------
# BUILD / ASYNC TRACKING
# ------------------------------------------------------------
enum BuildState { IDLE, FETCHING, SPAWNING_CHILDREN, DOWNLOADING, READY, ERROR }

signal build_state_changed(new_state: int)
signal build_finished(success: bool)
signal _dummy_success(filename: String, local_path: String, type: String)
signal _dummy_error(reason: String)

# --- SEGNALI RIPRISTINATI PER IL PANNELLO PROGRESSI ---
signal fetch_json_success()
signal fetch_json_error(reason: String)
signal download_media_success(filename: String, path: String, type: String)
signal download_media_error(reason: String)
signal download_thumbnail_success(filename: String, path: String, type: String)
signal download_thumbnail_error(reason: String)
# ------------------------------------------------------

var _build_state: int = BuildState.IDLE
var build_state: int:
	get: return _build_state
	set(v):
		_build_state = v
		build_state_changed.emit(_build_state)

var _pending_children: int = 0
var _pending_downloads: int = 0
var _pending_probe_guards: int = 0
var _finished_emitted: bool = false
var _build_started: bool = false
var _is_using_cache: bool = false
var _must_reinstantiate_medium: bool = false

var item_sets: Array[int] = []
var media: Array[int] = []

@export_group("REFRESH AND MEDIUM")
@export_tool_button("Sincronizza Item da DB") var fetch_omeka_info_btn = fetch_omeka_info

@export var auto_instantiate_children: bool = true
@export var auto_download_medium: bool = true
@export var auto_instantiate_medium: bool = true
@export var auto_recurse_children: bool = true
@export var metadata_only: bool = false

@export_tool_button("Instantiate Components and Areas") var instantiate_children_btn = instantiate_children
@export_tool_button("Instantiate Media") var instantiate_medium_btn = instantiate_medium

@export var media_filename: String
@export var media_path: String
@export var media_type: String
@export var thumbnail_path: String = ""
@export_group("")

func _ready() -> void:
	if not Engine.is_editor_hint():
		print("Item '%s' ready." % self.name)


func _enter_tree() -> void:
	pass

func _exit_tree() -> void:
	pass


func set_item_visible(v: bool):
	for c in get_children():
		if c is LivingItem:
			(c as LivingItem).set_item_visible(v)

# ==============================================================================
# FLUSSO DI COSTRUZIONE DELL'ITEM
# ==============================================================================
func fetch_omeka_info():
	print("Avvio sincronizzazione per nodo '%s'." % name)
	_reset_build_tracking()
	build_state = BuildState.FETCHING
	
	# Usiamo call_deferred per staccarci dal thread chiamante ed evitare blocchi UI
	call_deferred("_run_build_process_async")

func _run_build_process_async() -> void:
	# 1. FETCH METADATI DA OMEKA
	var meta_ok = await _fetch_omeka_metadata_async()
	if not meta_ok:
		_fail_build("Errore fetch JSON da Omeka per %s" % name)
		return

	# 2. ISTANZIAZIONE DELLA STRUTTURA (Sottonodi e Aree)
	if auto_instantiate_children:
		build_state = BuildState.SPAWNING_CHILDREN
		instantiate_children()

	# 3. RICORSIONE (Avvia i figli)
	if auto_recurse_children:
		for child in get_children():
			if child is LivingItem:
				child.auto_instantiate_children = auto_instantiate_children
				child.auto_recurse_children = auto_recurse_children
				child.auto_download_medium = auto_download_medium
				child.auto_instantiate_medium = auto_instantiate_medium
				child.metadata_only = metadata_only
				
				_begin_child_build(child)
				child.fetch_omeka_info() 

	# 4. DOWNLOAD MEDIA
	if auto_download_medium and not metadata_only:
		build_state = BuildState.DOWNLOADING
		_mark_download_started()
		await _sync_media_async()
		_mark_download_done()

	# 5. ISTANZIAZIONE DEL MEDIA
	if auto_instantiate_medium and not metadata_only:
		if Engine.is_editor_hint() and self.is_inside_tree() and _must_reinstantiate_medium:
			await _wait_for_godot_import_and_instantiate()
		else:
			instantiate_medium()

	_try_emit_build_finished()

# ==============================================================================
# 1. METADATA: Lettura asincrona da Omeka S
# ==============================================================================
func _fetch_omeka_metadata_async() -> bool:
	var living_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if living_root == null: 
		fetch_json_error.emit("Root mancante")
		return false
	
	var base_url := str(living_root.get("OMEKA_BASE_URL")).strip_edges().trim_suffix("/")
	var item_url := base_url + "/api/items?pretty_print=1&id=" + str(item_id)
	
	var response = await HTTPDownloader.request_json(self, item_url, 25.0)
	if not response.get("ok", false): 
		fetch_json_error.emit("HTTP Error")
		return false
	
	var data = response.get("json", [])
	if typeof(data) != TYPE_ARRAY or data.is_empty(): 
		fetch_json_error.emit("Empty JSON")
		return false
	var item_dict = data[0]
	if typeof(item_dict) != TYPE_DICTIONARY: 
		fetch_json_error.emit("Invalid JSON")
		return false

	title = item_dict.get("o:title", "Senza Titolo")
	self.name = title.substr(0, OMEKA_TITLE_MAX_LEN)
	modified = item_dict.get("o:modified", {}).get("@value", "")
	short_description = get_omeka_text(item_dict, "lcp_form:has_short_text_f")
	long_description = get_omeka_text(item_dict, "lcp_form:has_long_text_f")
	catalog_description = get_omeka_text(item_dict, "lcp_form:has_catalogue_text_f")

	if item_dict.get("o:resource_class"): resource_class = item_dict["o:resource_class"]["o:id"]

	components.clear()
	for comp in item_dict.get("lcp_form:is_composed_of_f", []): 
		components.append(int(comp.get("value_resource_id", 0)))

	areas.clear()
	for a in item_dict.get("lcp_form:has_participatory_area_f", []): 
		areas.append(int(a.get("value_resource_id", 0)))

	medium_uri = ""
	if item_dict.has("lcp_form:has_URI") and typeof(item_dict["lcp_form:has_URI"]) == TYPE_ARRAY and not item_dict["lcp_form:has_URI"].is_empty(): 
		var mu = item_dict["lcp_form:has_URI"][0].get("@id")
		if mu != null: medium_uri = str(mu)

	thumbnail_uri = ""
	if item_dict.has("thumbnail_display_urls") and typeof(item_dict["thumbnail_display_urls"]) == TYPE_DICTIONARY:
		var tu = item_dict["thumbnail_display_urls"].get("square")
		if tu != null: thumbnail_uri = str(tu)

	notify_property_list_changed()
	fetch_json_success.emit() # Avvisa il Dock!
	return true

func get_omeka_text(item_dict: Dictionary, key: String) -> String:
	if not item_dict.has(key): return ""
	var arr = item_dict[key]
	if typeof(arr) != TYPE_ARRAY or arr.is_empty() or typeof(arr[0]) != TYPE_DICTIONARY: return ""
	return str(arr[0].get("@value", ""))

# ==============================================================================
# 2. STRUTTURA: Istanziazione Figli
# ==============================================================================
func instantiate_children() -> void:
	var existing_children = {}
	for child in get_children():
		if child is LivingItem: existing_children[child.item_id] = child

	for c in components:
		if existing_children.has(c):
			existing_children.erase(c)
		else:
			var new_element := LivingElement.new() 
			new_element.item_id = c
			new_element.name = "LivingElement-" + str(c)
			add_child(new_element)
			if Engine.is_editor_hint(): new_element.owner = get_tree().edited_scene_root

	for a in areas:
		if existing_children.has(a):
			existing_children.erase(a)
		else:
			var new_area := LivingArea.new()
			new_area.item_id = a
			new_area.name = "LivingArea-" + str(a)
			add_child(new_area)
			if Engine.is_editor_hint(): new_area.owner = get_tree().edited_scene_root

	for old_child in existing_children.values(): 
		remove_child(old_child)
		old_child.queue_free()

# ==============================================================================
# 4. MEDIA
# ==============================================================================
func _sync_media_async() -> void:
	if medium_uri == "" and thumbnail_uri == "": return
	
	var item_dir = MEDIA_SAVE_PATH.path_join(str(item_id))
	if not DirAccess.dir_exists_absolute(item_dir): DirAccess.make_dir_recursive_absolute(item_dir)
	var cache_path = item_dir.path_join("cache_info.json")
	var cache_data = _read_cache(cache_path)
	
	_is_using_cache = true
	_must_reinstantiate_medium = false
	var remote_pwd = _resolve_remote_pwd()

	# --- SYNC MEDIUM PRINCIPALE ---
	if medium_uri != "" and not _looks_like_directory_medium_uri(medium_uri):
		var remote_fp = await _get_remote_fingerprint_async(medium_uri, remote_pwd)
		var local_fp = _build_media_fingerprint_from_cache(cache_data)
		var file_exists = cache_data.get("media_path", "") != "" and FileAccess.file_exists(cache_data["media_path"])
		
		if not file_exists or (_has_valid_media_fingerprint(remote_fp) and not _media_fingerprint_equal(remote_fp, local_fp)):
			print("Item %d: Media obsoleto o mancante. Avvio download..." % item_id)
			_is_using_cache = false
			_must_reinstantiate_medium = true
			var dl_res = await _download_file_async(medium_uri, item_dir, str(item_id) + "-", remote_pwd)
			if dl_res.get("ok", false):
				media_path = dl_res["local_path"]
				media_type = dl_res["type"]
				media_filename = media_path.get_file()
				remote_fp["media_path"] = media_path
				remote_fp["media_type"] = media_type
				_update_cache(cache_path, remote_fp)
				download_media_success.emit(media_filename, media_path, media_type)
			else:
				download_media_error.emit(dl_res["error"])
		else:
			print("Item %d: Cache file principale valida." % item_id)
			media_path = cache_data.get("media_path", "")
			
			# FIX SCENARIO A: Assicuriamoci che il media type non sia mai vuoto!
			media_type = cache_data.get("media_type", "")
			if media_type == "": 
				media_type = _get_fallback_media_type(media_path)
				
			media_filename = media_path.get_file()
			download_media_success.emit(media_filename, media_path, media_type)

	# --- SYNC THUMBNAIL ---
	if thumbnail_uri != "":
		var thumb_exists = cache_data.get("thumb_path", "") != "" and FileAccess.file_exists(cache_data["thumb_path"])
		if not thumb_exists or cache_data.get("thumb_source_uri", "") != thumbnail_uri:
			var dl_res = await _download_file_async(thumbnail_uri, item_dir, str(item_id) + "-thumbnail-", remote_pwd)
			if dl_res.get("ok", false):
				thumbnail_path = dl_res["local_path"]
				_update_cache(cache_path, {"thumb_path": thumbnail_path, "thumb_source_uri": thumbnail_uri})
				download_thumbnail_success.emit(thumbnail_path.get_file(), thumbnail_path, "image/jpeg")
			else:
				download_thumbnail_error.emit(dl_res["error"])
		else:
			thumbnail_path = cache_data.get("thumb_path", "")
			download_thumbnail_success.emit(thumbnail_path.get_file(), thumbnail_path, "image/jpeg")

# ==============================================================================
# UTILS PER IL MEDIA SYNC E PROBE
# ==============================================================================
func _get_fallback_media_type(path: String, header_type: String = "") -> String:
	if header_type != "" and header_type != "application/octet-stream": return header_type
	var ext = path.get_extension().to_lower()
	if ext in ["png"]: return "image/png"
	elif ext in ["jpg", "jpeg"]: return "image/jpeg"
	elif ext in ["txt"]: return "text/plain"
	elif ext in ["ogg", "ogv"]: return "video/ogg"
	elif ext in ["glb", "gltf"]: return "model/gltf-binary"
	elif ext in ["zip", "pck"]: return "application/zip"
	return "application/octet-stream"

func _get_remote_fingerprint_async(uri: String, pwd: String) -> Dictionary:
	var probe_url = _get_probe_url_for_medium(uri)
	var head_res = await HTTPDownloader.request_head(self, probe_url, 10.0, pwd)
	var fp = _build_media_fingerprint_from_headers(head_res.get("headers", []))
	if not head_res.get("ok", false) or not _has_valid_media_fingerprint(fp):
		var get_res = await HTTPDownloader.request_probe_get(self, probe_url, 10.0, pwd)
		if get_res.get("ok", false):
			return _build_media_fingerprint_from_headers(get_res.get("headers", []))
	return fp

func _download_file_async(uri: String, local_dir: String, prefix: String, pwd: String) -> Dictionary:
	var downloader := HTTPDownloader.new(uri, local_dir, prefix, _dummy_success, _dummy_error)
	downloader.remote_pwd = pwd.strip_edges()
	add_child(downloader)

	var result = {"ok": false, "local_path": "", "error": "", "type": ""}
	downloader.success_signal.connect(func(_fname, path, type):
		result["ok"] = true
		result["local_path"] = path
		result["type"] = _get_fallback_media_type(path, type)
	, CONNECT_ONE_SHOT)
	
	downloader.error_signal.connect(func(err): result["error"] = err, CONNECT_ONE_SHOT)
	downloader.do_download()

	while not result["ok"] and result["error"] == "":
		if not is_instance_valid(downloader) or downloader.is_queued_for_deletion():
			if result["error"] == "" and not result["ok"]: result["error"] = "Download interrotto."
			break
		await get_tree().process_frame

	return result

func _read_cache(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY: return parsed
	return {}

func _update_cache(path: String, new_data: Dictionary) -> void:
	var data = _read_cache(path)
	data.merge(new_data, true)
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data))

func _resolve_remote_pwd() -> String:
	var living_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if living_root == null: return ""
	return str(living_root.get("nextsave_pwd")).strip_edges()

func _looks_like_directory_medium_uri(uri: String) -> bool:
	if uri == "": return false
	if uri.contains("/public.php/dav/files/"):
		var marker := "/public.php/dav/files/"
		var idx := uri.find(marker)
		if idx == -1: return false
		var rest := uri.substr(idx + marker.length()).strip_edges().trim_suffix("/")
		return rest != "" and rest.split("/").size() == 1
	if uri.contains("/s/"):
		return not uri.ends_with("/download")
	return false

func _get_probe_url_for_medium(uri: String) -> String:
	if uri.contains("/s/"):
		var url_info := LivingUtils.parse_nextcloud_share_link(uri)
		if typeof(url_info) == TYPE_DICTIONARY and url_info.has("base_url") and url_info.has("token"):
			return str(url_info["base_url"]) + "/public.php/dav/files/" + str(url_info["token"])
	return uri

func _build_media_fingerprint_from_headers(headers: PackedStringArray) -> Dictionary:
	return {
		"media_remote_etag": _get_header_value(headers, "etag"),
		"media_remote_last_modified": _get_header_value(headers, "last-modified"),
		"media_remote_content_length": _get_header_value(headers, "content-length")
	}

func _build_media_fingerprint_from_cache(cache_data: Dictionary) -> Dictionary:
	return {
		"media_remote_etag": str(cache_data.get("media_remote_etag", "")).strip_edges(),
		"media_remote_last_modified": str(cache_data.get("media_remote_last_modified", "")).strip_edges(),
		"media_remote_content_length": str(cache_data.get("media_remote_content_length", "")).strip_edges()
	}

func _has_valid_media_fingerprint(fingerprint: Dictionary) -> bool:
	return (
		str(fingerprint.get("media_remote_etag", "")).strip_edges() != ""
		or str(fingerprint.get("media_remote_last_modified", "")).strip_edges() != ""
		or str(fingerprint.get("media_remote_content_length", "")).strip_edges() != ""
	)

func _media_fingerprint_equal(a: Dictionary, b: Dictionary) -> bool:
	var a_etag := str(a.get("media_remote_etag", "")).strip_edges()
	var b_etag := str(b.get("media_remote_etag", "")).strip_edges()
	var a_lm := str(a.get("media_remote_last_modified", "")).strip_edges()
	var b_lm := str(b.get("media_remote_last_modified", "")).strip_edges()
	var a_len := str(a.get("media_remote_content_length", "")).strip_edges()
	var b_len := str(b.get("media_remote_content_length", "")).strip_edges()

	if a_lm != "" and b_lm != "" and a_len != "" and b_len != "":
		return a_lm == b_lm and a_len == b_len
	if a_etag != "" and b_etag != "":
		return a_etag == b_etag
	if a_lm != "" and b_lm != "":
		return a_lm == b_lm
	if a_len != "" and b_len != "":
		return a_len == b_len
	return false

func _get_header_value(headers: PackedStringArray, header_name: String) -> String:
	var prefix := header_name.to_lower() + ":"
	for h in headers:
		var line := str(h)
		var low := line.to_lower()
		if low.begins_with(prefix):
			return line.substr(line.find(":") + 1).strip_edges()
	return ""

# ==============================================================================
# 5. ISTANZIAZIONE DEL MEDIA NEL 3D E ATTESA IMPORT GODOT
# ==============================================================================
func instantiate_medium() -> void:
	if media_type == "" or media_path == "": 
		return 
	
	if _is_using_cache and not _must_reinstantiate_medium:
		for child in get_children():
			if child is Living3DModel or child is LivingImage or child is LivingVideo or child is LivingText or child is LivingScene:
				print("LivingItem: Media già presente e aggiornato.")
				return 

	for child in get_children():
		if child is Living3DModel or child is LivingImage or child is LivingVideo or child is LivingText or child is LivingScene:
			remove_child(child)
			child.queue_free()
	
	var new_child = null
	
	if media_type == "image/png" or media_type == "image/jpeg":
		new_child = LivingImage.new()
		new_child.name = "LivingImage-" + str(item_id)
		new_child.image_path = media_path
	elif media_type == "text/plain":
		new_child = LivingText.new()
		new_child.name = "LivingText-" + str(item_id)
		new_child.text_path = media_path
	elif media_type == "video/ogg":
		new_child = living_video_player_scene.instantiate()
		new_child.name = "LivingVideo-" + str(item_id)
		new_child.video_path = media_path
	elif media_type == "model/gltf-binary":
		new_child = Living3DModel.new()
		new_child.name = "Living3DModel-" + str(item_id)
		new_child.model_path = media_path
	elif media_type == "application/zip":
		self.visible = true 
		new_child = LivingScene.new()
		new_child.name = "LivingScene-" + str(item_id)
		new_child.pack_path = media_path
		
		var extract_dir = media_path.get_base_dir()
		self.set_meta("_edit_lock_", true)
		new_child.set_meta("_edit_lock_", true)
		
		new_child.extraction_dir = extract_dir
		new_child.entry_scene_path = extract_dir.path_join("LivingEnvironmentTemplate.tscn")
	else:
		push_error("Unknown media type '%s'" % [media_type])
		return
	
	add_child(new_child)
	_must_reinstantiate_medium = false
	
	if Engine.is_editor_hint():
		var root = get_tree().edited_scene_root
		if root != null:
			new_child.owner = root
		else:
			new_child.owner = self.owner
		EditorInterface.mark_scene_as_unsaved()

# ATTESA IMPORTAZIONE GODOT + INSTANZIAZIONE ---
func _wait_for_godot_import_and_instantiate() -> void:
	var fs = EditorInterface.get_resource_filesystem()
	if fs != null and media_path != "":
		print("LivingItem: Segnalo a Godot il file %s" % media_path.get_file())
		
		var state = {"import_done": false}
		
		# Questa funzione scatterà IN AUTOMATICO non appena Godot avrà 
		# completato con successo l'importazione in background del nostro file.
		var on_reimport = func(resources: PackedStringArray):
			if media_path in resources:
				state["import_done"] = true

		# Ci mettiamo in ascolto
		if not fs.resources_reimported.is_connected(on_reimport):
			fs.resources_reimported.connect(on_reimport)

		# Diciamo all'editor: "Ehi, il file su disco è cambiato, aggiornalo!"
		fs.update_file(media_path)
		
		var ext := media_path.get_extension().to_lower()
		if ext in ["glb", "gltf"]:
			print("LivingItem: In attesa del re-import in background di Godot...")
			var loops := 0
			
			# Aspettiamo fino a 1m la CONFERMA UFFICIALE di Godot
			while loops < 3600 and not state["import_done"]:
				# Se l'editor sembra addormentato, diamo un colpetto al filesystem
				if loops % 180 == 0 and not fs.is_scanning():
					fs.scan()
				await get_tree().process_frame
				loops += 1
				
			if state["import_done"]:
				print("LivingItem: Re-import confermato dal motore!")
			else:
				print("LivingItem: Timeout attesa re-import, provo comunque il caricamento.")
		else:
			# Per le immagini e i video basta una frazione di secondo
			for i in range(15):
				await get_tree().process_frame
			while fs.is_scanning():
				await get_tree().process_frame

		
		if fs.resources_reimported.is_connected(on_reimport):
			fs.resources_reimported.disconnect(on_reimport)
			
		# Mettiamo in cassaforte l'aggiornamento: carichiamo il file appena 
		# sfornato forzando Godot a scartare eventuali rimasugli in RAM
		ResourceLoader.load(media_path, "PackedScene" if ext in ["glb", "gltf"] else "", ResourceLoader.CACHE_MODE_REPLACE)

	instantiate_medium()
	_mark_download_done()

# ==============================================================================
# TRACKING E STATO BUILD
# ==============================================================================
func get_pending_downloads() -> int:
	return maxi(0, _pending_downloads - _pending_probe_guards)
	
func _reset_build_tracking() -> void:
	_pending_children = 0
	_pending_downloads = 0
	_pending_probe_guards = 0
	_finished_emitted = false
	_build_started = true

func _try_emit_build_finished() -> void:
	if _finished_emitted or _pending_children > 0 or _pending_downloads > 0: return
	_finished_emitted = true
	build_state = BuildState.READY
	build_finished.emit(true)

func _fail_build(reason: String = "") -> void:
	if reason.strip_edges() != "": push_error(reason)
	if _finished_emitted: return
	_finished_emitted = true
	build_state = BuildState.ERROR
	build_finished.emit(false)

func _begin_child_build(child: LivingItem) -> void:
	_pending_children += 1
	child.build_finished.connect(func(_success: bool):
		_pending_children -= 1
		_try_emit_build_finished()
	, CONNECT_ONE_SHOT)

func _mark_download_started() -> void:
	_pending_downloads += 1
	build_state = BuildState.DOWNLOADING

func _mark_download_done() -> void:
	_pending_downloads -= 1
	if _pending_downloads < 0: _pending_downloads = 0
	_try_emit_build_finished()