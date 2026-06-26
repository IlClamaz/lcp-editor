@tool
extends RefCounted
class_name CuratorSceneController

const KEY_OMEKA_URL := "curator/omeka_url_default"

# --- Save Signals ---
signal save_upload_finished(success: bool, msg: String)
signal save_fetch_finished(success: bool, list: Array, msg: String)
signal save_download_finished(success: bool, local_path: String, msg: String)

# Proxy signals used by direct Nextcloud ops
signal direct_scene_list_success(list: Array[Dictionary])
signal direct_scene_list_error(reason: String)
signal direct_scene_download_success(filename: String, local_path: String, type: String)
signal direct_scene_download_error(reason: String)

# --- Segnali per il Flusso Master ---
signal workflow_progress(step_name: String)
signal workflow_finished(success: bool, msg: String)

# --- Segnali di appoggio per l'HTTPDownloader ---
signal _dummy_success(filename: String, local_path: String, type: String)
signal _dummy_error(reason: String)


# ------------------------------------------------------------
# Getters Environment (oggetto LivingEnvironment) and Scene (Nodo della scena aperta)
# ------------------------------------------------------------
func get_environment(editor_interface: EditorInterface) -> LivingEnvironment:
	if editor_interface == null:
		return null
	var sr := editor_interface.get_edited_scene_root()
	if sr == null:
		return null
	return sr as LivingEnvironment if sr is LivingEnvironment else null


func edited_scene_root(editor_interface: EditorInterface) -> Node:
	return null if editor_interface == null else editor_interface.get_edited_scene_root()


# ------------------------------------------------------------
# Global Omeka URL
# ------------------------------------------------------------
func load_global_default_url(editor_interface: EditorInterface) -> String:
	if editor_interface == null:
		return ""
	var es := editor_interface.get_editor_settings()
	return str(es.get_setting(KEY_OMEKA_URL)) if es.has_setting(KEY_OMEKA_URL) else ""


func save_global_default_url(editor_interface: EditorInterface, url: String) -> void:
	if editor_interface == null:
		return
	var es := editor_interface.get_editor_settings()
	es.set_setting(KEY_OMEKA_URL, url)

func apply_global_url_to_current_scene(editor_interface: EditorInterface, url: String) -> void:
	# Applica l'URL globale alla LivingEnvironment attualmente aperta in editor.
	# - Se non c'è una LivingEnvironment come root, non fa nulla.
	# - Se url è vuoto/solo spazi, non fa nulla.

	var env := get_environment(editor_interface)
	if env == null:
		return

	var new_url := url.strip_edges()
	if new_url == "":
		return

	if str(env.OMEKA_BASE_URL).strip_edges() == new_url:
		return # già impostato

	else:
		env.OMEKA_BASE_URL = new_url

# ------------------------------------------------------------
# Snapshot & Render
# ------------------------------------------------------------	

func scan_environment(env_root: LivingEnvironment) -> Array:
	var out: Array = []
	scan_environment_R(env_root, out, 0)
	return out
	
func scan_environment_R(n: LivingItem, accumulator: Array, level: int) -> void:
	# Cerca il lucchetto nei metadati del nodo!
	var is_locked = n.has_meta("_edit_lock_") and n.get_meta("_edit_lock_")
	
	accumulator.append({
		"name": n.name,
		"visible": n.is_visible_in_tree(),
		"locked": is_locked, 
		"nesting_level": level,
		"instance_id": n.get_instance_id(),
		"node_path": n.get_path(),
		"thumbnail_path": n.thumbnail_path
		})
	var children = n.get_children()
	for c in children:
		if c is LivingItem:
			scan_environment_R(c, accumulator, level + 1)

# ==============================================================================
# LOGICA SALVATAGGIO (Save)
# ==============================================================================

# --- UPLOAD SCENA ---
func upload_scene(editor_interface: EditorInterface, pwd: String) -> void:
	var env := get_environment(editor_interface)
	if env == null:
		save_upload_finished.emit(false, "Environment not valid")
		return

	if env.medium_uri == null or env.medium_uri.strip_edges() == "":
		save_upload_finished.emit(false, "The environment has a problem on the database")
		return

	var root_node = edited_scene_root(editor_interface)
	var scene_path = root_node.scene_file_path if root_node != null else ""

	# --- 1. CREAZIONE DELLA COPIA PULITA IN MEMORIA ---
	var temp_packed := load(scene_path) as PackedScene
	var temp_root := temp_packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)

	# Puliamo la scena
	_clean_media_recursive(temp_root)

	# --- 2. SALVATAGGIO DEL FILE TEMPORANEO ---
	var clean_packed := PackedScene.new()
	clean_packed.pack(temp_root)

	var original_filename = scene_path.get_file()
	var temp_upload_path := "user://".path_join(original_filename)
	
	var err = ResourceSaver.save(clean_packed, temp_upload_path)
	
	temp_root.free() 

	if err != OK:
		save_upload_finished.emit(false, "Impossible creating temporary clean file.")
		return

	# --- 3. UPLOAD E PULIZIA ---
	env.nextsave_pwd = pwd.strip_edges()
	
	env.scene_upload_success.connect(func(save_name, _url):
		if FileAccess.file_exists(temp_upload_path):
			DirAccess.remove_absolute(temp_upload_path)
		save_upload_finished.emit(true, "Scene saved with success!")
	, CONNECT_ONE_SHOT)
	
	env.scene_upload_error.connect(func(err_msg):
		if FileAccess.file_exists(temp_upload_path):
			DirAccess.remove_absolute(temp_upload_path)
		save_upload_finished.emit(false, "Error: " + err_msg)
	, CONNECT_ONE_SHOT)
	
	env.upload_scene(temp_upload_path) 


func _clean_media_recursive(node: Node) -> void:
	var children = node.get_children()
	for child in children:
		# Controlliamo se il figlio appartiene a una delle classi "protette"
		var is_protected = (
			child is LivingItem or 
			child is LivingCamera or 
			child is LivingLights or
			child is LivingPortal or
			child is GestureGameController or 
			child is ExperienceController or
			child is TransferGameController
		)
		
		# Se il padre è un LivingItem e il figlio NON è protetto, lo cancelliamo
		if node is LivingItem and not is_protected:
			child.free() 
		else:
			# Altrimenti procediamo con la ricorsione
			_clean_media_recursive(child)

# ==============================================================================
# FLUSSO APERTURA SCENA DAL DB (Download)
# ==============================================================================
func download_and_setup_remote_scene(
	host: Node, 
	editor_interface: EditorInterface, 
	base_url: String, 
	env_id: int, 
	remote_file_name: String, 
	pwd: String,
	dl_progress  # L'istanza di CuratorDownloadProgress dal dock
) -> void:
	
	if host == null or env_id <= 0 or base_url.strip_edges() == "" or remote_file_name.strip_edges() == "":
		workflow_finished.emit(false, "Parameters not valid for download.")
		return

	# STEP 1: Risolvi URI da Omeka
	workflow_progress.emit("Getting the scene URL...")
	var medium_uri = await _resolve_env_medium_uri_async(host, base_url, env_id)
	if medium_uri == "":
		workflow_finished.emit(false, "No medium URI found for this environment.")
		return

	# STEP 2: Download della Scena (.tscn)
	workflow_progress.emit("Downloading Scene...")
	var local_dir := "res://curated_scenes/"
	if not DirAccess.dir_exists_absolute(local_dir):
		DirAccess.make_dir_recursive_absolute(local_dir)
		
	var scene_download_result = await _download_file_async(host, medium_uri, local_dir, remote_file_name, pwd)
	if not scene_download_result.get("ok", false):
		workflow_finished.emit(false, "Error downloading scene: " + scene_download_result.get("error", "Sconosciuto"))
		return
		
	var local_scene_path: String = scene_download_result["local_path"]

	# STEP 3: Aggiornamento FileSystem
	workflow_progress.emit("Importing Scene...")
	var fs = EditorInterface.get_resource_filesystem()
	fs.update_file(local_scene_path)
	if not fs.is_scanning(): fs.scan()

	# STEP 4: Apertura Sicura della Scena
	# Visto che la scena è stata "pulita" in upload, non lamenterà missing dependencies.
	workflow_progress.emit("Opening Scene...")
	await _safe_open_scene_async(host, fs, local_scene_path)

	# STEP 5: Sincronizzazione Finale e Download Media
	workflow_progress.emit("Downloading composition & media...")
	var env := get_environment(editor_interface)
	if env != null:
		apply_global_url_to_current_scene(editor_interface, base_url)
		
		dl_progress.reset()
		dl_progress.start(env, host)
		
		# Quando il rebuild è finito, dichiariamo successo!
		env.rebuild_completed.connect(func(success: bool):
			dl_progress.mark_build_finished(success)
			if success:
				workflow_finished.emit(true, "Scene downloaded and components restored")
			else:
				workflow_finished.emit(false, "Scene downloaded but components restore failed")
		, CONNECT_ONE_SHOT)
		
		# instanzia gli oggetti a runtime dentro la scena editor appena aperta
		env.rebuild_environment()
	else:
		workflow_finished.emit(false, "Scene downloaded, but no env found")

# --- CERCA SCENE se l'env c'è ---
func fetch_remote_scenes(editor_interface: EditorInterface, pwd: String) -> void:
	var env := get_environment(editor_interface)
	if env == null: 
		save_fetch_finished.emit(false, [], "Environment not found")
		return
	
	if env.medium_uri == null or env.medium_uri.strip_edges() == "":
		save_fetch_finished.emit(false, [], "No medium attached to this environment.")
		return

	env.nextsave_pwd = pwd.strip_edges()
	
	env.scene_list_success.connect(func(list):
		save_fetch_finished.emit(true, list, "Query completed")
	, CONNECT_ONE_SHOT)
	
	env.scene_list_error.connect(func(err):
		save_fetch_finished.emit(false, [], "Connection error or missing password")
	, CONNECT_ONE_SHOT)
	
	env.list_remote_scenes() # Qui fa effettivamente la chiamata http


# --- CERCA SCENE DA UNITA' TEMATICA SELEZIONATA (SENZA SCENA APERTA) ---
func fetch_remote_scenes_for_env(host: Node, base_url: String, env_id: int, pwd: String) -> void:
	if host == null:
		save_fetch_finished.emit(false, [], "Host not valid")
		return
	if env_id <= 0:
		save_fetch_finished.emit(false, [], "Firstly select a valid environment")
		return
	if base_url.strip_edges() == "":
		save_fetch_finished.emit(false, [], "Database URL not valid.")
		return

	# Usiamo la nuova funzione asincrona interna invece del vecchio HTTPDownloader!
	var medium_uri = await _resolve_env_medium_uri_async(host, base_url, env_id)
	
	if medium_uri == "":
		save_fetch_finished.emit(false, [], "No medium found attached to this environment")
		return

	_disconnect_all_signal_slots(direct_scene_list_success)
	_disconnect_all_signal_slots(direct_scene_list_error)

	direct_scene_list_success.connect(func(list):
		save_fetch_finished.emit(true, list, "Query completed")
	, CONNECT_ONE_SHOT)

	direct_scene_list_error.connect(func(_reason):
		save_fetch_finished.emit(false, [], "Connection error")
	, CONNECT_ONE_SHOT)

	var lister := HTTPLister.new(
		medium_uri,
		pwd.strip_edges(),
		direct_scene_list_success,
		direct_scene_list_error
	)
	host.add_child(lister)
	lister.do_list()

func _disconnect_all_signal_slots(sig: Signal) -> void:
	for conn in sig.get_connections():
		var cb = conn.get("callable")
		if cb != null:
			sig.disconnect(cb)


# ------------------------------------------------------------
# Gestione Password, locale al progetto
# ------------------------------------------------------------
# carico dalle prefs dell'editor
func load_env_password(editor_interface: EditorInterface, env_id: int) -> String:
	if editor_interface == null or env_id <= 0: return ""
	var key = "curator/save_pwd_env_" + str(env_id)
	var es = editor_interface.get_editor_settings()
	if es.has_setting(key):
		return str(es.get_setting(key))
	return ""
# salvo nelle prefs dell'editor
func save_env_password(editor_interface: EditorInterface, env_id: int, pwd: String) -> void:
	if editor_interface == null or env_id <= 0: return
	var key = "curator/save_pwd_env_" + str(env_id)
	var es = editor_interface.get_editor_settings()
	es.set_setting(key, pwd)

# --- HELPER ASINCRONI PER IL CONTROLLER ---

func _resolve_env_medium_uri_async(host: Node, base_url: String, env_id: int) -> String:
	var item_url := base_url.strip_edges().trim_suffix("/") + "/api/items?pretty_print=1&id=" + str(env_id)
	var response = await HTTPDownloader.request_json(host, item_url, 15.0)
	if not response.get("ok", false): return ""
	var data = response.get("json", [])
	if typeof(data) != TYPE_ARRAY or data.is_empty(): return ""
	var item = data[0]
	if typeof(item) != TYPE_DICTIONARY: return ""
	if item.has("lcp_form:has_URI"):
		var uri_array: Array = item["lcp_form:has_URI"]
		if not uri_array.is_empty() and typeof(uri_array[0]) == TYPE_DICTIONARY:
			return str(uri_array[0].get("@id", ""))
	return ""

func _download_file_async(host: Node, uri: String, local_dir: String, remote_file: String, pwd: String) -> Dictionary:
	var downloader := HTTPDownloader.new(uri, local_dir, "", _dummy_success, _dummy_error)
	
	# FIX: Aggiunto strip_edges() fondamentale per evitare errori 401 o 404 da Nextcloud
	downloader.remote_pwd = pwd.strip_edges()
	downloader.target_remote_file = remote_file.strip_edges()
	print(downloader.remote_pwd, downloader.target_remote_file)
	host.add_child(downloader)
	
	var result = {"ok": false, "local_path": "", "error": ""}
	
	downloader.success_signal.connect(func(_fname, path, _type):
		result["ok"] = true
		result["local_path"] = path
	, CONNECT_ONE_SHOT)
	
	downloader.error_signal.connect(func(err):
		result["error"] = err
	, CONNECT_ONE_SHOT)
	
	downloader.do_download()
	
	# Loop di attesa asincrona reso a prova di crash
	while not result["ok"] and result["error"] == "":
		if not is_instance_valid(downloader) or downloader.is_queued_for_deletion():
			if result["error"] == "" and not result["ok"]:
				result["error"] = "Download canceled by the system"
			break
		await host.get_tree().process_frame
		
	return result

func _safe_open_scene_async(host: Node, fs: EditorFileSystem, path: String) -> void:
	var clean_path = path.simplify_path()
	while fs.is_scanning():
		await host.get_tree().process_frame
	await host.get_tree().create_timer(0.4).timeout
	
	var current_root = EditorInterface.get_edited_scene_root()
	var current_path = current_root.scene_file_path.simplify_path() if current_root != null else ""

	if current_path == clean_path:
		EditorInterface.reload_scene_from_path(clean_path)
	else:
		EditorInterface.open_scene_from_path(clean_path)
	
	# Diamo tempo all'editor di caricare l'albero
	await host.get_tree().create_timer(0.5).timeout
