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
