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
var inst := CuratorEnvironmentInstantiator.new()
var dl := CuratorDownloadProgress.new()
var ui_builder := CuratorDockUIBuilder.new()
var hooks := CuratorEditorHooks.new()
var ui: CuratorDockUIBuilder.CuratorDockUI

var _last_scene_root: Node = null
var _had_scene := false
var _is_instantiating := false
var _error_state := false  # Env dependent, si basa sullo stato della lista e viene messo a false quando la lista renderizza correttamente

func _ready() -> void:

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	# build UI
	ui = ui_builder.build(content)

	# bind inventory UI
	var icon := get_theme_icon("ImportFail", "EditorIcons")
	inventory_ctrl.bind_ui(ui.item_list, ui.preview, icon)

	# load global URL + apply to env if exists
	ui.global_omeka_url.text = scene_ctrl.load_global_default_url(editor_interface)
	scene_ctrl.apply_global_url_to_current_scene(editor_interface, undo_redo, ui.global_omeka_url.text)

	# wire UI events
	_wire_ui()

	# hooks
	hooks.bind(editor_interface, undo_redo, scene_ctrl, self)
	
	hooks.selected_node_transformed.connect(_on_selected_node_transformed) # rotation tracking (un po' più pesante, vediamo se serve davvero)
	hooks.refresh_requested.connect(_do_env_refresh)
	hooks.editor_env_selection_changed.connect(_on_editor_env_selection_changed)
	_update_scene_dependent_ui(true)
	_do_env_refresh()

	inst.configure(editor_interface, undo_redo, scene_ctrl, setup_ctrl, TEMPLATE_ENV_SCENE, CURATED_SCENES_DIR)

	inst.rebuild_finished.connect(func(success, env):
		# segnala a dl che il build è terminato (così può chiudere quando pending==0)
		dl.mark_build_finished(success)

		if not success:
			_set_instantiating_ui(false)
			_error_state = true
			ui.instantiate_progress_lbl.text = "Errore"
			return
		await get_tree().process_frame
		env.instantiate_all_media()
		_set_instantiating_ui(false) # Sblocco la UI
		_error_state = false
	)

	inst.failed.connect(func(msg):
		_set_instantiating_ui(false)
		_error_state = true
		push_warning(msg)
		)

	dl.progress_changed.connect(func(pct, done, total):
		ui.instantiate_progress_lbl.text = "%d%% (%d/%d)" % [pct, done, total]
		)


func _process(_delta: float) -> void:
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	var has_scene := (sr != null)

	if sr != _last_scene_root or has_scene != _had_scene:
		_last_scene_root = sr
		_had_scene = has_scene

		# ✅ reset selezione editor + lista
		hooks.clear_editor_selection()
		if ui != null and ui.item_list != null:
			inventory_ctrl.on_clear_selection()

		_update_scene_dependent_ui(true)
		hooks.request_refresh()

func _reset_selection_and_offsets_for_scene_change() -> void:
	if ui == null:
		return
	if ui.item_list:
		inventory_ctrl.on_clear_selection()
	inventory_ctrl.on_item_selected(-1, scene_ctrl.get_environment(editor_interface) != null)
	_sync_transform_fields_from_node(null) # mette 0/0


func _on_selected_node_transformed(_node: Node3D, global_pos: Vector3, global_rot_deg: Vector3) -> void:
	if ui == null:
		return
	if ui.offset_x.has_focus() or ui.offset_z.has_focus():
		return
	ui.offset_x.value = global_pos.x
	ui.offset_z.value = global_pos.z
	# ui.rot_x.value = global_rot_deg.x
	# ui.rot_y.value = global_rot_deg.y
	# ui.rot_z.value = global_rot_deg.z


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
		_apply_ui_state() # aggiorna stato bottoni toggle + preview
		ui.place_btn.disabled = (env == null) or index < 0 or _error_state
		ui.rot_reset_btn.disabled = (env == null) or index < 0 or _error_state
		
		if env != null:
			var node := _resolve_item_node_from_list_index(index)
			if node != null:
				_sync_transform_fields_from_node(node) # ✅ aggiorna campi X/Y/Z

				hooks.set_suppress_selection(true)
				_select_node_in_editor(node)
				hooks.set_suppress_selection(false)
		)

	ui.auto_layout_btn.pressed.connect(_on_auto_layout_pressed)
	ui.reset_btn.pressed.connect(_on_reset_pressed)

	ui.ensure_player_btn.pressed.connect(_on_ensure_player_pressed)
	ui.ensure_floor_btn.pressed.connect(_on_ensure_floor_pressed)
	ui.ensure_lights_btn.pressed.connect(_on_ensure_lights_pressed)

	ui.rot_reset_btn.pressed.connect(_on_rotation_reset_pressed)


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
	_error_state = not inventory_ctrl.render_list(env)
	_apply_ui_state() ### NON SO SE ABBIA SENSO
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

	var env_loaded := int(env.item_id) > 0 and not _error_state and not _is_instantiating
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

	if not is_environment:
		_sync_transform_fields_from_node(null)

	ui.root_item_id.value = 0 if not is_environment else int(env.item_id)
	ui.instantiate_progress_lbl.text = ""
	
	
	ui.item_list.mouse_filter = Control.MOUSE_FILTER_STOP if is_environment else Control.MOUSE_FILTER_IGNORE
	ui.item_list.modulate.a = 1.0 if is_environment else 0.45

	ui.place_btn.disabled = (not is_environment) or ui.item_list.get_selected_items().is_empty()
	ui.rot_reset_btn.disabled = (not is_environment) or ui.item_list.get_selected_items().is_empty()
	
	

	# auto-layout solo se è un env e ho selezionato un LivingArea (altrimenti potrebbe essere pericoloso, meglio evitare confusione)
	var sel := ui.item_list.get_selected_items()
	var can_auto_layout := false
	if env != null and not sel.is_empty():
		var idx := int(sel[0])
		var n := _resolve_item_node_from_list_index(idx)
		can_auto_layout = n is LivingArea
	ui.auto_layout_btn.disabled = not can_auto_layout

	if not is_environment:
		ui.ensure_player_btn.disabled = true
		ui.ensure_floor_btn.disabled = true
		ui.ensure_lights_btn.disabled = true
		inventory_ctrl.clear_ui()

func _apply_ui_state() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	var is_environment := (env != null)

	# --- sempre aggiornabili ---
	ui.reset_btn.disabled = not is_environment or _is_instantiating
	ui.place_btn.disabled = (not is_environment) or _is_instantiating or ui.item_list.get_selected_items().is_empty()
	ui.rot_reset_btn.disabled = (not is_environment) or _is_instantiating or ui.item_list.get_selected_items().is_empty()

	# lista
	if ui.item_list:
		ui.item_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if (_is_instantiating or not is_environment) else Control.MOUSE_FILTER_STOP
		ui.item_list.modulate.a = 0.45 if (_is_instantiating or not is_environment) else 1.0

	# instantiate button
	ui.instantiate_scene_btn.disabled = _is_instantiating

	# auto layout solo se seleziono LivingArea
	ui.auto_layout_btn.disabled = true
	if is_environment and not _is_instantiating:
		var sel := ui.item_list.get_selected_items()
		if not sel.is_empty():
			var n := _resolve_item_node_from_list_index(int(sel[0]))
			ui.auto_layout_btn.disabled = not (n is LivingArea)

func _set_instantiating_ui(v: bool) -> void:
	_is_instantiating = v
	_apply_ui_state()

	# lista disabilitata + grigia
	if ui.item_list:
		ui.item_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if v else Control.MOUSE_FILTER_STOP
		ui.item_list.modulate.a = 0.45 if v else 1.0

	# bottone istanzia
	if ui.instantiate_scene_btn:
		ui.instantiate_scene_btn.disabled = v

	# bottoni pericolosi
	if ui.reset_btn: ui.reset_btn.disabled = v or ui.reset_btn.disabled
	if ui.auto_layout_btn: ui.auto_layout_btn.disabled = v or ui.auto_layout_btn.disabled

	# move/rot
	if ui.place_btn: ui.place_btn.disabled = v or ui.place_btn.disabled
	if ui.rot_reset_btn: ui.rot_reset_btn.disabled = v or ui.rot_reset_btn.disabled

# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------
# func _on_refresh_list_pressed() -> void:
	# per ora: snapshot solo scena (come stai facendo tu)
	# hooks.request_refresh()


func _on_instantiate_scene_from_db_pressed() -> void:
	_set_instantiating_ui(true)
	ui.instantiate_progress_lbl.text = "0%"
	var desired_env_id := int(ui.root_item_id.value)
	if desired_env_id <= 0:
		_do_env_refresh() # per forzare refresh e mostrare sanity warning
		_set_instantiating_ui(false)
		push_warning("Imposta prima un LivingEnvironment ID valido (> 0).")
		return

	inst.run(desired_env_id, ui.global_omeka_url.text)

	# Avvio progress deferred: al frame successivo l'env c'è (se inst ha aperto la scena)
	call_deferred("_start_dl_if_env_ready")

func _start_dl_if_env_ready() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		# se serve, riprova 1-2 frame (senza loop infinito)
		call_deferred("_start_dl_if_env_ready")
		return
	dl.reset()
	dl.start(env, self)


func _on_reset_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	layout_ctrl.reset_environment_children(env, undo_redo)
	inventory_ctrl.clear_last_selection()
	hooks.request_refresh()


func _on_auto_layout_pressed() -> void:
	var sel := ui.item_list.get_selected_items()
	if sel.is_empty():
		return

	var idx := int(sel[0])
	var n := _resolve_item_node_from_list_index(idx)
	if n == null or n is not LivingArea:
		return

	layout_ctrl.auto_layout_direct_elements(
		n,
		float(ui.spacing_edit.value),
		int(ui.cols_edit.value),
		undo_redo
	)

	# hooks.request_refresh()
	
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

func _on_editor_env_selection_changed(n: Node) -> void:
	if ui.item_list == null:
		return

	if n == null:
		inventory_ctrl.on_clear_selection()
		_apply_ui_state()
		inventory_ctrl.on_item_selected(-1, scene_ctrl.get_environment(editor_interface) != null)
		_sync_transform_fields_from_node(null) # ✅ reset
		return

	_sync_transform_fields_from_node(n) # ✅ aggiorna campi X/Y/Z

	var idx = inventory_ctrl.find_index_by_instance_id(ui.item_list, n.get_instance_id())
	if idx >= 0:
		hooks.set_suppress_selection(true)
		inventory_ctrl.on_clear_selection()
		inventory_ctrl.on_item_selected(idx, true)
		ui.item_list.ensure_current_is_visible()
		hooks.set_suppress_selection(false)
		
	else:
		inventory_ctrl.on_clear_selection()
	_apply_ui_state() # aggiorna stato bottoni toggle + preview
# ------------------------------------------------------------
# Place selected node at offset X/Z from current position + Reset rotation
# ------------------------------------------------------------
func _on_place_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	var sel := ui.item_list.get_selected_items()
	if sel.is_empty():
		return

	var index := int(sel[0])
	var target := _resolve_item_node_from_list_index(index)
	if target == null:
		push_warning("Nodo non trovato (forse è stato eliminato).")
		hooks.request_refresh()
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

	# hooks.request_refresh()


func _on_rotation_reset_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	var sel := ui.item_list.get_selected_items()
	if sel.is_empty():
		return

	var index := int(sel[0])
	var target := _resolve_item_node_from_list_index(index)
	if target == null:
		push_warning("Nodo non trovato (forse è stato eliminato).")
		hooks.request_refresh()
		return

	if not (target is Node3D):
		push_warning("Il nodo selezionato non è un Node3D, non posso ruotarlo.")
		return

	var n3d := target as Node3D

	var old_rot := n3d.global_rotation_degrees
	var new_rot := Vector3(0.0, 0.0, 0.0)

	if undo_redo != null:
		undo_redo.create_action("Reset rotation")
		# reset rotazione
		undo_redo.add_do_method(n3d, "set_global_rotation_degrees", new_rot)
		undo_redo.add_undo_method(n3d, "set_global_rotation_degrees", old_rot)
		undo_redo.commit_action()
	else:
		n3d.global_rotation_degrees = new_rot


# ------------------------------------------------------------
# Selection + show/hide
# ------------------------------------------------------------

func _on_toggle_selected_visibility() -> void:
	var sel := ui.item_list.get_selected_items()
	if sel.is_empty():
		return
	_on_show_hide_for_index(int(sel[0]))

func _on_show_hide_for_index(index: int) -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	var n := _resolve_item_node_from_list_index(index)
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

func _sync_transform_fields_from_node(n: Node) -> void:
	if ui == null:
		return

	if n == null or not (n is Node3D):
		ui.offset_x.value = 0.0
		ui.offset_z.value = 0.0
		# ui.rot_x.value = 0.0
		# ui.rot_y.value = 0.0
		# ui.rot_z.value = 0.0
		return

	var n3d := n as Node3D
	ui.offset_x.value = n3d.global_position.x
	ui.offset_z.value = n3d.global_position.z

	# var rd := n3d.rotation_degrees
	# ui.rot_x.value = rd.x
	# ui.rot_y.value = rd.y
	# ui.rot_z.value = rd.z


func _resolve_item_node_from_list_index(index: int) -> Node:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return null

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
		"node_path": n.get_path(),
		"thumbnail_path": n.thumbnail_path
		})
	var children = n.get_children()
	for c in children:
		if c is LivingItem:
			scan_environment_R(c, accumulator, level + 1)
