@tool
extends RefCounted
class_name CuratorSceneController

const KEY_OMEKA_URL := "curator/omeka_url_default"

# ------------------------------------------------------------
# Scene root
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
# Global URL stored in EditorSettings
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
