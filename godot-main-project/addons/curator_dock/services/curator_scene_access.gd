@tool
extends RefCounted
class_name CuratorSceneAccess

## Read/write access to the edited LivingEnvironment and curator editor prefs.
## No UI. No remote I/O.

const KEY_OMEKA_URL := "curator/omeka_url_default"
const DEFAULT_OMEKA_URL := "omekadev.livingculture.it"


func get_environment(editor_interface: EditorInterface) -> LivingEnvironment:
	if editor_interface == null:
		return null
	var sr := editor_interface.get_edited_scene_root()
	if sr == null:
		return null
	return sr as LivingEnvironment if sr is LivingEnvironment else null


func edited_scene_root(editor_interface: EditorInterface) -> Node:
	return null if editor_interface == null else editor_interface.get_edited_scene_root()


func load_global_default_url(editor_interface: EditorInterface) -> String:
	if editor_interface == null:
		return DEFAULT_OMEKA_URL
	var es := editor_interface.get_editor_settings()
	if es.has_setting(KEY_OMEKA_URL):
		var saved := str(es.get_setting(KEY_OMEKA_URL)).strip_edges()
		if saved != "":
			return saved
	return DEFAULT_OMEKA_URL


func save_global_default_url(editor_interface: EditorInterface, url: String) -> void:
	if editor_interface == null:
		return
	var es := editor_interface.get_editor_settings()
	es.set_setting(KEY_OMEKA_URL, url)


func apply_global_url_to_current_scene(editor_interface: EditorInterface, url: String) -> void:
	var env := get_environment(editor_interface)
	if env == null:
		return
	var new_url := url.strip_edges()
	if new_url == "":
		return
	if str(env.OMEKA_BASE_URL).strip_edges() == new_url:
		return
	env.OMEKA_BASE_URL = new_url


func load_env_password(editor_interface: EditorInterface, env_id: int) -> String:
	if editor_interface == null or env_id <= 0:
		return ""
	var key := "curator/save_pwd_env_" + str(env_id)
	var es := editor_interface.get_editor_settings()
	if es.has_setting(key):
		return str(es.get_setting(key))
	return ""


func save_env_password(editor_interface: EditorInterface, env_id: int, pwd: String) -> void:
	if editor_interface == null or env_id <= 0:
		return
	var key := "curator/save_pwd_env_" + str(env_id)
	var es := editor_interface.get_editor_settings()
	es.set_setting(key, pwd)


func scan_environment(env_root: LivingEnvironment) -> Array:
	var out: Array = []
	_scan_environment_r(env_root, out, 0)
	return out


func _scan_environment_r(n: LivingItem, accumulator: Array, level: int) -> void:
	var is_locked = n.has_meta("_edit_lock_") and n.get_meta("_edit_lock_")
	accumulator.append({
		"name": n.name,
		"visible": n.is_visible_in_tree(),
		"locked": is_locked,
		"nesting_level": level,
		"instance_id": n.get_instance_id(),
		"node_path": n.get_path(),
		"thumbnail_path": n.thumbnail_path,
		"type": n.get_script().get_global_name() if n.get_script() != null else n.get_class(),
	})
	for c in n.get_children():
		if c is LivingItem:
			# Slideshow sources: hide from inventory (slideshow is one object).
			if n is LivingSlideShowObject:
				continue
			_scan_environment_r(c, accumulator, level + 1)
