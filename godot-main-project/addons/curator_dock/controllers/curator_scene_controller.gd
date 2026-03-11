@tool
extends RefCounted
class_name CuratorSceneController

const KEY_OMEKA_URL := "curator/omeka_url_default"

# --- Save Signals ---
signal save_upload_finished(success: bool, msg: String)
signal save_fetch_finished(success: bool, list: Array, msg: String)
signal save_download_finished(success: bool, local_path: String, msg: String)

# ------------------------------------------------------------
# Getters Environment and Scene
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
	
	if scene_path == "":
		save_upload_finished.emit(false, "Salva la scena nel progetto (CTRL+S) prima di caricarla!")
		return
		
	if FileAccess.file_exists(scene_path) and EditorInterface.get_resource_filesystem().get_file_type(scene_path) == "":
		save_upload_finished.emit(false, "Ci sono modifiche non salvate (CTRL+S)!")
		return

	env.nextsave_pwd = pwd.strip_edges()
	
	# Usiamo funzioni anonime one-shot per mappare i segnali dell'ambiente sui nostri segnali del Controller
	env.scene_upload_success.connect(func(save_name, _url):
		save_upload_finished.emit(true, "Scena '%s' salvata sul db con successo!" % save_name)
	, CONNECT_ONE_SHOT)
	
	env.scene_upload_error.connect(func(err):
		save_upload_finished.emit(false, "Errore: " + err)
	, CONNECT_ONE_SHOT)
	
	env.upload_scene()


# --- CERCA SCENE ---
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
		save_fetch_finished.emit(false, [], "Errore: " + err)
	, CONNECT_ONE_SHOT)
	
	env.list_remote_scenes()


# --- DOWNLOAD SCENA ---
func download_scene(editor_interface: EditorInterface, remote_file_name: String, pwd: String) -> void:
	var env := get_environment(editor_interface)
	if env == null:
		save_download_finished.emit(false, "", "Ambiente non trovato.")
		return

	if not env.has_method("download_scene"):
		save_download_finished.emit(false, "", "Manca la funzione download_scene nel LivingEnvironment!")
		return

	env.nextsave_pwd = pwd.strip_edges()
	
	env.connect("scene_download_success", func(_filename, local_path, _type):
		save_download_finished.emit(true, local_path, "Scena scaricata con successo.")
	, CONNECT_ONE_SHOT)
	
	env.connect("scene_download_error", func(err):
		save_download_finished.emit(false, "", "Errore: " + err)
	, CONNECT_ONE_SHOT)
	
	env.download_scene(remote_file_name)