@tool
extends VBoxContainer

const TEMPLATE_ENV_SCENE := "res://addons/living_platform_plugin/scenes/living_environment_root.tscn"
const CURATED_SCENES_DIR := "res://curated_scenes"

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager

# controllers
var scene_ctrl := CuratorSceneController.new()
var layout_ctrl := CuratorLayoutController.new()
var inventory_ctrl := CuratorInventoryController.new()
var setup_ctrl := CuratorSetupController.new()

# new helpers
var ui_builder := CuratorDockUIBuilder.new()
var hooks := CuratorEditorHooks.new()
var ui: CuratorDockUIBuilder.CuratorDockUI

var _last_scene_root: Node = null
var _had_scene := false


func _ready() -> void:
	custom_minimum_size = Vector2(360, 680)

	# build UI
	ui = ui_builder.build(self)

	# bind inventory UI
	var icon := get_theme_icon("Node3D", "EditorIcons")
	inventory_ctrl.bind_ui(ui.item_list, ui.preview, ui.place_btn, icon)

	# load global URL + apply to env if exists
	ui.global_omeka_url.text = scene_ctrl.load_global_default_url(editor_interface)
	scene_ctrl.apply_global_url_to_current_scene(editor_interface, undo_redo, ui.global_omeka_url.text)

	# wire UI events
	_wire_ui()

	# hooks
	hooks.bind(editor_interface, undo_redo, scene_ctrl)
	hooks.refresh_requested.connect(_do_env_refresh)

	_update_scene_dependent_ui(true)
	_do_env_refresh()


func _process(_delta: float) -> void:
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	var has_scene := (sr != null)

	if sr != _last_scene_root or has_scene != _had_scene:
		_last_scene_root = sr
		_had_scene = has_scene
		_update_scene_dependent_ui(true)
		hooks.request_refresh()


func _wire_ui() -> void:
	ui.global_omeka_url.text_changed.connect(func(t: String):
		scene_ctrl.save_global_default_url(editor_interface, t)
		scene_ctrl.apply_global_url_to_current_scene(editor_interface, undo_redo, t)
	)

	ui.instantiate_scene_btn.pressed.connect(_on_instantiate_scene_from_db_pressed)
	# ui.refresh_list_btn.pressed.connect(_on_refresh_list_pressed)

	ui.place_btn.pressed.connect(_on_place_pressed)
	ui.item_list.item_activated.connect(func(index: int):
		if index >= 0:
			_on_show_hide_for_index(index)
	)

	ui.item_list.item_selected.connect(func(index: int):
		var env := scene_ctrl.get_environment(editor_interface)
		inventory_ctrl.on_item_selected(index, env != null)

		# seleziona nodo in scena per vedere gizmo
		if env != null:
			var node := _resolve_item_node_from_list_index(index, env)
			if node != null:
				_select_node_in_editor(node)
	)

	ui.auto_layout_btn.pressed.connect(_on_auto_layout_pressed)
	ui.reset_btn.pressed.connect(_on_reset_pressed)

	ui.ensure_player_btn.pressed.connect(_on_ensure_player_pressed)
	ui.ensure_floor_btn.pressed.connect(_on_ensure_floor_pressed)
	ui.ensure_lights_btn.pressed.connect(_on_ensure_lights_pressed)


# ------------------------------------------------------------
# Refresh + sanity
# ------------------------------------------------------------
func _do_env_refresh() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		_update_setup_status(null)
		inventory_ctrl.clear_ui()
		return

	_update_setup_status(env)

	# evita che i segnali tree/rename generino refresh ricorsivi durante il render
	var snap := scan_environment(env)
	inventory_ctrl.set_snapshot(snap, env, editor_interface)
	inventory_ctrl.render_list(env)
	hooks.bind_rename_watchers_from_snapshot(snap)


func _update_setup_status(env: LivingEnvironment) -> void:
	# aggiorna le 4 pillole in UI
	if env == null:
		ui.sanity_player.text = "Camera: ❌"
		ui.sanity_lights.text = "Luci: ❌"
		ui.sanity_floor.text = "Pavimento: ❌"
		ui.sanity_env.text = "Ambiente: ❌"
		ui.ensure_player_btn.disabled = true
		ui.ensure_floor_btn.disabled = true
		ui.ensure_lights_btn.disabled = true
		return

	var has_player := setup_ctrl.has_player(env)
	var has_lights := setup_ctrl.has_lights(env)
	var has_floor := setup_ctrl.has_floor(env)

	var env_loaded := int(env.item_id) > 0
	ui.sanity_player.text = "Camera: %s" % ("✅" if has_player else "❌ (call devs)")
	ui.sanity_lights.text = "Luci: %s" % ("✅" if has_lights else "❌")
	ui.sanity_floor.text = "Pavimento: %s" % ("✅" if has_floor else "❌")
	ui.sanity_env.text = "Ambiente: %s" % ("✅" if env_loaded else "⚠")

	ui.ensure_player_btn.disabled = has_player
	ui.ensure_floor_btn.disabled = has_floor
	ui.ensure_lights_btn.disabled = has_lights


func _update_scene_dependent_ui(_force: bool = false) -> void:
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	var env := scene_ctrl.get_environment(editor_interface)

	var is_environment := (env != null)
	var is_empty_scene := (sr == null)

	ui.reset_btn.disabled = not is_environment
	ui.auto_layout_btn.disabled = not is_environment

	ui.item_list.mouse_filter = Control.MOUSE_FILTER_STOP if is_environment else Control.MOUSE_FILTER_IGNORE
	ui.item_list.modulate.a = 1.0 if is_environment else 0.45
	ui.place_btn.disabled = (not is_environment) or ui.item_list.get_selected_items().is_empty()

	if not is_environment:
		ui.ensure_player_btn.disabled = true
		ui.ensure_floor_btn.disabled = true
		ui.ensure_lights_btn.disabled = true
		inventory_ctrl.clear_ui()


# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------
func _on_refresh_list_pressed() -> void:
	# per ora: snapshot solo scena (come stai facendo tu)
	hooks.request_refresh()


func _on_instantiate_scene_from_db_pressed() -> void:
	var desired_env_id := int(ui.root_item_id.value)
	if desired_env_id <= 0:
		push_warning("Imposta prima un LivingEnvironment ID valido (> 0).")
		return

	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		var ok := _create_copy_from_template_and_open()
		if not ok:
			return
		call_deferred("_continue_instantiate_after_open")
		return

	_continue_instantiate_on_env(env)


func _continue_instantiate_after_open() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		push_warning("Non riesco a trovare LivingEnvironment dopo l'apertura della copia template.")
		return
	_continue_instantiate_on_env(env)


func _continue_instantiate_on_env(env: LivingEnvironment) -> void:
	scene_ctrl.apply_global_url_to_current_scene(editor_interface, undo_redo, ui.global_omeka_url.text)

	setup_ctrl.ensure_all(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))

	var desired_env_id := int(ui.root_item_id.value)
	if int(env.item_id) != desired_env_id:
		if undo_redo != null:
			undo_redo.create_action("Set LivingEnvironment item_id")
			undo_redo.add_do_property(env, "item_id", desired_env_id)
			undo_redo.add_undo_property(env, "item_id", env.item_id)
			undo_redo.commit_action()
		else:
			env.item_id = desired_env_id

	# refresh UI quando arriva fetch/rename
	if env.fetch_json_success.is_connected(_on_env_rebuild_done):
		env.fetch_json_success.disconnect(_on_env_rebuild_done)
	env.fetch_json_success.connect(_on_env_rebuild_done.bind(env), CONNECT_ONE_SHOT)

	env.rebuild_environment()


func _on_env_rebuild_done(env: LivingEnvironment) -> void:
	await get_tree().process_frame
	hooks.request_refresh()


func _create_copy_from_template_and_open() -> bool:
	if editor_interface == null:
		return false

	var tpl: PackedScene = load(TEMPLATE_ENV_SCENE)
	if tpl == null:
		push_warning("Template non trovato: %s" % TEMPLATE_ENV_SCENE)
		return false

	var root := tpl.instantiate()
	if root == null or not (root is LivingEnvironment):
		push_warning("Il template non ha LivingEnvironment come root.")
		return false

	if not DirAccess.dir_exists_absolute(CURATED_SCENES_DIR):
		var derr := DirAccess.make_dir_recursive_absolute(CURATED_SCENES_DIR)
		if derr != OK:
			push_warning("Impossibile creare cartella: %s" % CURATED_SCENES_DIR)
			return false

	var desired_env_id := int(ui.root_item_id.value)
	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var fname := "env_%s_%s.tscn" % [str(desired_env_id), ts]
	var new_path := "%s/%s" % [CURATED_SCENES_DIR, fname]

	var ps := PackedScene.new()
	if ps.pack(root) != OK:
		push_warning("PackedScene.pack fallito.")
		return false

	if ResourceSaver.save(ps, new_path) != OK:
		push_warning("ResourceSaver.save fallito: %s" % new_path)
		return false

	editor_interface.open_scene_from_path(new_path)
	return true


func _on_reset_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	layout_ctrl.reset_environment_children(env, undo_redo)
	hooks.request_refresh()


func _on_auto_layout_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	var parent := _get_selected_layout_parent(env)
	if parent == null:
		parent = env

	# sicurezza: consentiamo solo env o area come container finale
	if not (parent is LivingEnvironment or parent is LivingArea):
		parent = env

	layout_ctrl.auto_layout_direct_elements(
		parent,
		float(ui.spacing_edit.value),
		int(ui.cols_edit.value),
		undo_redo
	)

	hooks.request_refresh()


func _get_selected_layout_parent(env: LivingEnvironment) -> Node:
	if ui.item_list == null:
		return env
	var sel := ui.item_list.get_selected_items()
	if sel.is_empty():
		return env

	var idx := int(sel[0])
	var n := _resolve_item_node_from_list_index(idx, env)
	if n == null:
		return env

	if n is LivingArea or n is LivingEnvironment:
		return n
	if n is LivingElement:
		return n.get_parent()

	return env


func _on_ensure_player_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	setup_ctrl.ensure_player(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	hooks.request_refresh()

func _on_ensure_floor_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	setup_ctrl.ensure_floor(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	hooks.request_refresh()

func _on_ensure_lights_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	setup_ctrl.ensure_lights(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	hooks.request_refresh()


# ------------------------------------------------------------
# Selection + show/hide
# ------------------------------------------------------------
func _on_place_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	var sel := ui.item_list.get_selected_items()
	if sel.is_empty():
		return

	var index := int(sel[0])
	var target := _resolve_item_node_from_list_index(index, env)
	if target == null:
		push_warning("Nodo non trovato (forse è stato eliminato).")
		hooks._request_refresh()
		return

	if not (target is Node3D):
		push_warning("Il nodo selezionato non è un Node3D, non posso spostarlo.")
		return

	var n3d := target as Node3D
	var old_pos := n3d.global_position
	var new_pos := Vector3(ui.offset_x.value, old_pos.y, ui.offset_z.value) # manteniamo Y attuale

	if undo_redo != null:
		undo_redo.create_action("Move node to X/Z offset")
		undo_redo.add_do_method(n3d, "set_global_position", new_pos)
		undo_redo.add_undo_method(n3d, "set_global_position", old_pos)
		undo_redo.commit_action()
	else:
		n3d.global_position = new_pos

	hooks._request_refresh()

func _on_toggle_selected_visibility() -> void:
	var sel := ui.item_list.get_selected_items()
	if sel.is_empty():
		return
	_on_show_hide_for_index(int(sel[0]))

func _on_show_hide_for_index(index: int) -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	var n := _resolve_item_node_from_list_index(index, env)
	if n == null:
		return

	var current_vis := true
	if n is Node3D:
		current_vis = (n as Node3D).visible
	elif n.has_method("is_visible_in_tree"):
		current_vis = bool(n.call("is_visible_in_tree"))

	var new_vis := not current_vis

	if undo_redo != null:
		undo_redo.create_action("Toggle visibility")
		if n is Node3D:
			undo_redo.add_do_property(n, "visible", new_vis)
			undo_redo.add_undo_property(n, "visible", current_vis)
		elif n.has_method("set_visible"):
			undo_redo.add_do_method(n, "set_visible", new_vis)
			undo_redo.add_undo_method(n, "set_visible", current_vis)
		else:
			undo_redo.add_do_property(n, "visible", new_vis)
			undo_redo.add_undo_property(n, "visible", current_vis)
		undo_redo.commit_action()
	else:
		if n is Node3D:
			(n as Node3D).visible = new_vis
		elif n.has_method("set_visible"):
			n.call("set_visible", new_vis)

	hooks.request_refresh()


func _select_node_in_editor(node: Node) -> void:
	if editor_interface == null or node == null:
		return
	if not node.is_inside_tree():
		return
	var ed_sel := editor_interface.get_selection()
	if ed_sel == null:
		return
	ed_sel.clear()
	ed_sel.add_node(node)


func _resolve_item_node_from_list_index(index: int, env: LivingEnvironment) -> Node:
	if ui.item_list == null:
		return null
	if index < 0 or index >= ui.item_list.item_count:
		return null

	var md := ui.item_list.get_item_metadata(index)
	if typeof(md) != TYPE_DICTIONARY:
		return null

	var iid := int(md.get("instance_id", 0))
	if iid != 0:
		var obj := instance_from_id(iid)
		if obj != null and obj is Node:
			return obj as Node

	var p := str(md.get("node_path", ""))
	if p != "":
		var n := env.get_node_or_null(p)
		if n != null:
			return n

	return null

func scan_environment(env_root: LivingEnvironment) -> Array:
	var out: Array = []
	scan_environment_R(env_root, out, 0)
	return out
	
func scan_environment_R(n: LivingItem, accumulator: Array, level: int) -> void:
	accumulator.append({
		"name": n.name,
		"visible": n.is_visible_in_tree(),
		"nesting_level": level,
		"instance_id": n.get_instance_id(),
		"node_path": n.get_path()
		})
	var children = n.get_children()
	for c in children:
		if c is LivingItem:
			scan_environment_R(c, accumulator, level + 1)
