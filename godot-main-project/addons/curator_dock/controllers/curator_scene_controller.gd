@tool
extends RefCounted
class_name CuratorSceneController

const KEY_OMEKA_URL := "curator/omeka_url_default"
var root_living_element_prefix := "LivingRoot-"

func root_name_for_item_id(item_id: int) -> String:
	return "%s%d" % [root_living_element_prefix, item_id]

func get_living_scene(editor_interface: EditorInterface) -> LivingScene:
	if editor_interface == null:
		return null
	var sr := editor_interface.get_edited_scene_root()
	if sr == null:
		return null
	return sr as LivingScene if sr is LivingScene else null

func edited_scene_root(editor_interface: EditorInterface) -> Node:
	return null if editor_interface == null else editor_interface.get_edited_scene_root()

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

# 🔎 trova un root LivingElement specifico per item_id (livello 2)
func find_root_living_element_by_item_id(ls: Node, desired_item_id: int) -> LivingElement:
	if ls == null:
		return null

	# 1) prova per nome deterministico
	var expected_name := root_name_for_item_id(desired_item_id)
	var named := ls.get_node_or_null(expected_name)
	if named != null and named is LivingElement:
		var le := named as LivingElement
		if le.has_meta("curator_temp") and bool(le.get_meta("curator_temp")):
			return null
		return le


	# 2) fallback: cerca per item_id (se qualcuno ha rinominato il nodo a mano)
	for c in ls.get_children():
		if c is LivingElement:
			var le := c as LivingElement

			# ✅ ignora nodi temporanei del dock
			if le.has_meta("curator_temp") and bool(le.get_meta("curator_temp")):
				continue

			# ✅ opzionale ma utile: ignora nodi non-owned (non salvabili, non in SceneTree)
			if le.owner == null:
				continue

			if int(le.item_id) == desired_item_id:
				return le


	return null

# ✅ assicura root: se non esiste, lo crea come "fratello" degli altri root
func ensure_root_living_element(
	editor_interface: EditorInterface,
	undo_redo: EditorUndoRedoManager,
	desired_item_id: int
) -> LivingElement:
	var ls := get_living_scene(editor_interface)
	if ls == null:
		return null

	if desired_item_id <= 0:
		return null

	# Se esiste già quel root (per nome o item_id), restituiscilo senza toccare gli altri
	var existing := find_root_living_element_by_item_id(ls, desired_item_id)
	if existing != null:
		# opzionale: allinea il nome deterministico se non matcha
		var expected_name := root_name_for_item_id(desired_item_id)
		if existing.name != expected_name:
			if undo_redo != null:
				undo_redo.create_action("Rename Root LivingElement")
				undo_redo.add_do_property(existing, "name", expected_name)
				undo_redo.add_undo_property(existing, "name", existing.name)
				undo_redo.commit_action()
			else:
				existing.name = expected_name
		return existing

	# Altrimenti: crea nuovo root come sibling (sempre livello 2)
	var new_root := LivingElement.new()
	new_root.item_id = desired_item_id
	new_root.name = root_name_for_item_id(desired_item_id)

	if undo_redo != null:
		undo_redo.create_action("Create Root LivingElement")
		undo_redo.add_do_method(ls, "add_child", new_root)
		undo_redo.add_undo_method(ls, "remove_child", new_root)
		undo_redo.add_do_method(new_root, "set_owner", edited_scene_root(editor_interface))
		undo_redo.commit_action()
	else:
		ls.add_child(new_root)
		new_root.owner = edited_scene_root(editor_interface)

	return new_root


func apply_global_url_to_current_scene(
	editor_interface: EditorInterface,
	undo_redo: EditorUndoRedoManager,
	url: String
) -> void:
	var ls := get_living_scene(editor_interface)
	if ls == null:
		return

	var new_url := url.strip_edges()
	if new_url == "":
		return

	if undo_redo != null:
		undo_redo.create_action("Set LivingScene Omeka URL")
		undo_redo.add_do_property(ls, "OMEKA_BASE_URL", new_url)
		undo_redo.add_undo_property(ls, "OMEKA_BASE_URL", ls.OMEKA_BASE_URL)
		undo_redo.commit_action()
	else:
		ls.OMEKA_BASE_URL = new_url

func has_direct_child_living_element_with_item_id(parent: Node, item_id: int) -> bool:
	if parent == null:
		return false
	for c in parent.get_children():
		if c is LivingElement and int((c as LivingElement).item_id) == int(item_id):
			return true
	return false