@tool
extends RefCounted
class_name CuratorSceneController

const KEY_OMEKA_URL := "curator/omeka_url_default"

# --- Save Signals ---
signal save_upload_finished(success: bool, msg: String)
signal save_fetch_finished(success: bool, list: Array, msg: String)
signal save_download_finished(success: bool, local_path: String, msg: String)

# Proxy signals used by direct Nextcloud ops (without an open LivingEnvironment scene)
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

func apply_global_url_to_current_scene(editor_interface: EditorInterface, undo_redo: EditorUndoRedoManager, url: String) -> void:
	# Applica l'URL globale alla LivingEnvironment attualmente aperta in editor.
	# - Se non c'è una LivingEnvironment come root, non fa nulla.
	# - Se url è vuoto/solo spazi, non fa nulla.
	# - Se undo_redo è disponibile, registra l'operazione (Ctrl+Z / Ctrl+Y).

	var env := get_environment(editor_interface)
	if env == null:
		return

	var new_url := url.strip_edges()
	if new_url == "":
		return

	if str(env.OMEKA_BASE_URL).strip_edges() == new_url:
		return # già impostato

	if undo_redo != null:
		undo_redo.create_action("Set LivingEnvironment Omeka URL")
		undo_redo.add_do_property(env, "OMEKA_BASE_URL", new_url)
		undo_redo.add_undo_property(env, "OMEKA_BASE_URL", env.OMEKA_BASE_URL)
		undo_redo.commit_action()
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
# LOGICA SALVATAGGIO
# ==============================================================================

# --- UPLOAD SCENA ---
func upload_scene(editor_interface: EditorInterface, pwd: String) -> void:
	var env := get_environment(editor_interface)
	if env == null:
		save_upload_finished.emit(false, "Ambiente non valido.")
		return

	if env.medium_uri == null or env.medium_uri.strip_edges() == "":
		save_upload_finished.emit(false, "L'ambiente non ha un link (Medium URI) valido sul database.")
		return

	var root_node = edited_scene_root(editor_interface)
	var scene_path = root_node.scene_file_path if root_node != null else ""
	
	# 1. Se la scena è "Vergine" (Nuova Scena mai salvata su disco)
	if scene_path == "":
		save_upload_finished.emit(false, "Salva la scena nel progetto la prima volta (Scena -> Salva)!")
		return
		
	# --- AUTO-SALVATAGGIO ---
	# Questo scriverà sul disco tutte le modifiche e le variabili aggiornate.
	var err = editor_interface.save_scene()
	if err != OK:
		save_upload_finished.emit(false, "Impossibile auto-salvare la scena localmente.")
		return
	# ----------------------------------

	env.nextsave_pwd = pwd.strip_edges()
	
	# Usiamo funzioni anonime one-shot per mappare i segnali
	env.scene_upload_success.connect(func(save_name, _url):
		save_upload_finished.emit(true, "Scena '%s' salvata sul db con successo!" % save_name)
	, CONNECT_ONE_SHOT)
	
	env.scene_upload_error.connect(func(err_msg):
		save_upload_finished.emit(false, "Errore: " + err_msg)
	, CONNECT_ONE_SHOT)
	
	# Avviamo l'upload della scena appena salvata, qui fa effettivamente la rihiesta http
	env.upload_scene()


# --- CERCA SCENE se l'env c'è ---
func fetch_remote_scenes(editor_interface: EditorInterface, pwd: String) -> void:
	var env := get_environment(editor_interface)
	if env == null: 
		save_fetch_finished.emit(false, [], "Ambiente non trovato.")
		return
	
	if env.medium_uri == null or env.medium_uri.strip_edges() == "":
		save_fetch_finished.emit(false, [], "Nessun Medium URI valido sul database.")
		return

	env.nextsave_pwd = pwd.strip_edges()
	
	env.scene_list_success.connect(func(list):
		save_fetch_finished.emit(true, list, "Ricerca completata.")
	, CONNECT_ONE_SHOT)
	
	env.scene_list_error.connect(func(err):
		save_fetch_finished.emit(false, [], "Errore di rete o password mancante.")
	, CONNECT_ONE_SHOT)
	
	env.list_remote_scenes() # Qui fa effettivamente la chiamata http


# --- CERCA SCENE DA UNITA' TEMATICA SELEZIONATA (SENZA SCENA APERTA) ---
func fetch_remote_scenes_for_env(host: Node, base_url: String, env_id: int, pwd: String) -> void:
	if host == null:
		save_fetch_finished.emit(false, [], "Host non valido.")
		return
	if env_id <= 0:
		save_fetch_finished.emit(false, [], "Seleziona prima un ambiente valido.")
		return
	if base_url.strip_edges() == "":
		save_fetch_finished.emit(false, [], "URL Omeka non valido.")
		return

	# Usiamo la nuova funzione asincrona interna invece del vecchio HTTPDownloader!
	var medium_uri = await _resolve_env_medium_uri_async(host, base_url, env_id)
	
	if medium_uri == "":
		save_fetch_finished.emit(false, [], "Nessun Medium URI valido sul database.")
		return

	_disconnect_all_signal_slots(direct_scene_list_success)
	_disconnect_all_signal_slots(direct_scene_list_error)

	direct_scene_list_success.connect(func(list):
		save_fetch_finished.emit(true, list, "Ricerca completata.")
	, CONNECT_ONE_SHOT)

	direct_scene_list_error.connect(func(_reason):
		save_fetch_finished.emit(false, [], "Errore di rete o password mancante.")
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


# ==============================================================================
# FLUSSO APERTURA SCENA DAL DB: Download -> Prefetch -> Open -> Sync
# ==============================================================================
func download_and_setup_remote_scene(
	host: Node, 
	editor_interface: EditorInterface, 
	prefetch_ctrl: CuratorMediaPrefetchController,
	base_url: String, 
	env_id: int, 
	remote_file_name: String, 
	pwd: String,
	media_cache_dir: String,
	dl_progress  # L'istanza di CuratorDownloadProgress dal dock
) -> void:
	
	if host == null or env_id <= 0 or base_url.strip_edges() == "" or remote_file_name.strip_edges() == "":
		workflow_finished.emit(false, "Parametri non validi per il download.")
		return

	# STEP 1: Risolvi URI da Omeka
	workflow_progress.emit("Risoluzione URI ambiente...")
	var medium_uri = await _resolve_env_medium_uri_async(host, base_url, env_id)
	if medium_uri == "":
		workflow_finished.emit(false, "Nessun Medium URI valido trovato su Omeka.")
		return

	# STEP 2: Download della Scena (.tscn)
	workflow_progress.emit("Download scena in corso...")
	var local_dir := "res://curated_scenes/"
	if not DirAccess.dir_exists_absolute(local_dir):
		DirAccess.make_dir_recursive_absolute(local_dir)
		
	var scene_download_result = await _download_file_async(host, medium_uri, local_dir, remote_file_name, pwd)
	if not scene_download_result.get("ok", false):
		workflow_finished.emit(false, "Errore download scena: " + scene_download_result.get("error", "Sconosciuto"))
		return
		
	var local_scene_path: String = scene_download_result["local_path"]

	# STEP 3: Aggiornamento FileSystem
	workflow_progress.emit("Sincronizzazione file system...")
	var fs = EditorInterface.get_resource_filesystem()
	fs.update_file(local_scene_path)
	# Forza lo scan senza bloccare
	if not fs.is_scanning(): fs.scan()

	# STEP 4: Prefetch dei Media
	workflow_progress.emit("Preparazione media mancanti...")
	var prefetch_res = await prefetch_ctrl.prefetch_scene_media(
		host, local_scene_path, env_id, base_url, media_cache_dir, pwd,
		func(_phase: String, _done: int, _total: int, label: String):
			workflow_progress.emit(label)
	)
	if not prefetch_res.get("ok", false):
		push_warning("Prefetch: alcuni media non risultano pronti in tempo, provo comunque ad aprire la scena.")

	# STEP 5: Apertura Sicura della Scena
	workflow_progress.emit("Apertura scena...")
	await _safe_open_scene_async(host, fs, local_scene_path)

	# STEP 6: Sincronizzazione Finale (Post-Open Sync)
	workflow_progress.emit("Sync finale da Omeka...")
	var env := get_environment(editor_interface)
	if env != null:
		# FIX: Recuperiamo l'undo_redo direttamente dall'host (il Dock)
		var undo_redo = host.undo_redo if "undo_redo" in host else null
		apply_global_url_to_current_scene(editor_interface, undo_redo, base_url)
		
		dl_progress.reset()
		dl_progress.start(env, host)
		
		# Ci mettiamo in ascolto della fine della build dell'ambiente
		env.build_finished.connect(func(success: bool):
			dl_progress.mark_build_finished(success)
			if success:
				workflow_finished.emit(true, "Scena caricata e sincronizzata!")
			else:
				workflow_finished.emit(false, "Scena aperta, ma sync media fallito.")
		, CONNECT_ONE_SHOT)
		
		env.rebuild_environment()
	else:
		workflow_finished.emit(false, "Scena aperta, ma nodo Ambiente non trovato.")

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
				result["error"] = "Download interrotto dal sistema."
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
