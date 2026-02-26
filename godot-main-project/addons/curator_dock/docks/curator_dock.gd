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

	# HOOKS
	hooks.bind(editor_interface, undo_redo, scene_ctrl, self)
	
	hooks.selected_node_transformed.connect(_on_selected_node_transformed) # rotation tracking
	hooks.refresh_requested.connect(_do_env_refresh) # refresh da editor hooks (es. tree changed, rename, ecc)
	hooks.editor_env_selection_changed.connect(_on_editor_env_selection_changed) # quando cambia selezione da scena
	
	_do_ui_refresh() # In questo modo quando avvio Godot, se c'è già una scena aperta, mostra subito lo stato corretto
	_do_env_refresh() # In questo modo quando avvio Godot, se c'è già una scena aperta, mostra subito lo stato corretto

	# Instanziazione + download
	inst.configure(editor_interface, undo_redo, scene_ctrl, setup_ctrl, TEMPLATE_ENV_SCENE, CURATED_SCENES_DIR)
	inst.rebuild_finished.connect(func(success, env): # callback quando l'instanziazione è finita (success=true se tutto ok, false se errore durante build)
		# segnala a dl che il build è terminato (così può chiudere quando pending==0)
		dl.mark_build_finished(success)

		if not success:
			_is_instantiating = false
			_error_state = true  # metto stato di errore (così se refresha mostra sanity warning)
			ui.instantiate_progress_lbl.text = "Errore"
			_do_ui_refresh() # aggiorna stato UI (abilita bottoni, mostra sanity warning, ecc)
			return
		await get_tree().process_frame

		env.instantiate_all_media() # avvia download media (se ci sono), quando finisce chiama callback su dl 
		_is_instantiating = false # Sblocco la UI
		_error_state = false
		ui.instantiate_progress_lbl.text = "Completato"
		_do_ui_refresh() # aggiorna stato UI (abilita bottoni, mostra sanity
	)

	inst.failed.connect(func(msg):
		_is_instantiating = false
		_error_state = true
		ui.instantiate_progress_lbl.text = "Errore"
		_do_ui_refresh() # aggiorna stato UI (abilita bottoni, mostra sanity warning, ecc)
		push_warning(msg)
	)

	dl.progress_changed.connect(func(pct, done, total): # callback per aggiornare progresso download
		ui.instantiate_progress_lbl.text = "%d%% (%d/%d)" % [pct, done, total]
	)


func _process(_delta: float) -> void:
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	var has_scene := (sr != null)

	if sr != _last_scene_root or has_scene != _had_scene:  # controllo se scena cambiata (o da null a non null o viceversa)
		_last_scene_root = sr
		_had_scene = has_scene

		var env := scene_ctrl.get_environment(editor_interface)
		if env != null:
			ui.instantiate_progress_lbl.text = "Completato" if not _error_state else "Errore"
			ui.root_item_id.value = env.item_id
		else:
			ui.instantiate_progress_lbl.text = ""
			ui.root_item_id.value = 0

		# ✅ reset selezione editor + lista
		hooks.clear_editor_selection()
		if ui != null and ui.item_list != null:
			inventory_ctrl.on_clear_selection()
		_sync_transform_fields_from_node(null) # reset campi trasformazione

		# Aggiorno UI dipendente dalla scena e mostro lo stato attuale
		_do_ui_refresh()
		_do_env_refresh()


func _wire_ui() -> void:
	# Se si cambia il testo dell'URL globale, salvo e applico a scena (se c'è)
	ui.global_omeka_url.text_changed.connect(func(t: String):
		scene_ctrl.save_global_default_url(editor_interface, t)
		scene_ctrl.apply_global_url_to_current_scene(editor_interface, undo_redo, t)
	)

	# Instantiate
	ui.instantiate_scene_btn.pressed.connect(_on_instantiate_scene_from_db_pressed)
	# ui.refresh_list_btn.pressed.connect(_on_refresh_list_pressed)

	# Lista
	ui.item_list.item_activated.connect(func(index: int): # Al doppio click toggle visibilità
		if index >= 0:
			_on_show_hide_for_index(index)
	)

	ui.item_list.item_selected.connect(func(index: int):  # Al singolo click setta preview, seleziona in scena e abilita bottoni
		var env := scene_ctrl.get_environment(editor_interface)
		inventory_ctrl.on_item_selected(index, env != null) # seleziono effettivamente e aggiorno preview

		_do_ui_refresh() # aggiorna stato bottoni
		
		if env != null:
			var node := inventory_ctrl._resolve_item_node_from_list_index(env, index)
			if node != null:
				_sync_transform_fields_from_node(node) # aggiorna campi X/Z del nodo selezionato

				hooks.set_suppress_selection(true)
				var ed_sel := editor_interface.get_selection()
				ed_sel.clear()
				ed_sel.add_node(node) # seleziono nodo in editor (senza triggerare refresh ricorsivo)
				hooks.set_suppress_selection(false)
	)

	# Dangerous actions
	ui.auto_layout_btn.pressed.connect(_on_auto_layout_pressed)
	ui.reset_btn.pressed.connect(_on_reset_pressed)

	# Setup buttons
	ui.ensure_player_btn.pressed.connect(_on_ensure_player_pressed)
	ui.ensure_floor_btn.pressed.connect(_on_ensure_floor_pressed)
	ui.ensure_lights_btn.pressed.connect(_on_ensure_lights_pressed)

	# Transformations
	ui.rot_reset_btn.pressed.connect(_on_rotation_reset_pressed)
	ui.place_btn.pressed.connect(_on_place_pressed)

# ------------------------------------------------------------
# REFRESH. gestisce il refresh della lista / snapshot. La UI è refreshata in _do_ui_refresh
# ------------------------------------------------------------
func _do_env_refresh() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return 

	# nel caso ci sia un ambiente, scansiono, renderizzo la lista, aggiorno stato ui e ricollego watcher rename
	var snap := scene_ctrl.scan_environment(env)
	inventory_ctrl.set_snapshot(snap, env, editor_interface)
	_error_state = not inventory_ctrl.render_list()
	hooks.bind_rename_watchers_from_snapshot(snap)

# ------------------------------------------------------------
# REFRESH. gestisce il refresh della UI (ma non della lista)
# ------------------------------------------------------------
func _do_ui_refresh() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	var is_environment := (env != null)

	if not is_environment: # caso di scena vuota o senza ambiente: resetto tutto e mostro sanity warning
		ui.instantiate_progress_lbl.text = ""
		inventory_ctrl.clear_ui()
		ui.sanity_player.text = "Camera: ❌"
		ui.sanity_lights.text = "Luci: ❌"
		ui.sanity_floor.text = "Pavimento: ❌"
		ui.sanity_env.text = "Ambiente: ❌"
		ui.ensure_player_btn.disabled = true
		ui.ensure_floor_btn.disabled = true
		ui.ensure_lights_btn.disabled = true

	# instantiate button
	ui.instantiate_scene_btn.disabled = _is_instantiating

	# lista
	if ui.item_list:
		ui.item_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if (_is_instantiating or not is_environment) else Control.MOUSE_FILTER_STOP
		ui.item_list.modulate.a = 0.45 if (_is_instantiating or not is_environment) else 1.0

	# place/rot reset
	ui.place_btn.disabled = (not is_environment) or _is_instantiating or _error_state or ui.item_list.get_selected_items().is_empty()
	ui.rot_reset_btn.disabled = (not is_environment) or _is_instantiating or _error_state or ui.item_list.get_selected_items().is_empty()

	# auto layout solo se seleziono LivingArea
	ui.auto_layout_btn.disabled = true
	if is_environment and not _is_instantiating:
		var sel := ui.item_list.get_selected_items()
		if not sel.is_empty():
			var n := inventory_ctrl._resolve_item_node_from_list_index(env, int(sel[0]))
			ui.auto_layout_btn.disabled = not (n is LivingArea)
	
	# reset button
	ui.reset_btn.disabled = not is_environment or _is_instantiating
		
	# setup buttons
	var has_player := setup_ctrl.has_player(env)
	var has_lights := setup_ctrl.has_lights(env)
	var has_floor := setup_ctrl.has_floor(env)

	var env_loaded := is_environment and int(env.item_id) > 0 and not _error_state and not _is_instantiating
	ui.sanity_player.text = "Camera: %s" % ("✅" if has_player else "❌")
	ui.sanity_lights.text = "Luci: %s" % ("✅" if has_lights else "❌")
	ui.sanity_floor.text = "Pavimento: %s" % ("✅" if has_floor else "❌")
	ui.sanity_env.text = "Ambiente: %s" % ("✅" if env_loaded else "❌")

	ui.ensure_player_btn.disabled = has_player
	ui.ensure_floor_btn.disabled = has_floor
	ui.ensure_lights_btn.disabled = has_lights

# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------
func _on_instantiate_scene_from_db_pressed() -> void:
	_is_instantiating = true
	ui.instantiate_progress_lbl.text = "0%"
	_do_ui_refresh() # aggiorna stato UI (disabilita bottone, mostra sanity warning, ecc)
	var desired_env_id := int(ui.root_item_id.value)

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

# Show/hide double click sulla lista
func _on_show_hide_for_index(index: int) -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	var n := inventory_ctrl._resolve_item_node_from_list_index(env, index)
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

	_do_env_refresh()


# Place selected node at offset X/Z from current position
func _on_place_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	var sel := ui.item_list.get_selected_items()
	if sel.is_empty():
		return

	var index := int(sel[0])
	var target := inventory_ctrl._resolve_item_node_from_list_index(env, index)
	if target == null:
		push_warning("Nodo non trovato (forse è stato eliminato).")
		_do_ui_refresh() # aggiorna stato UI (disabilita bottoni, mostra sanity warning, ecc)
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


# Reset rotation of selected node
func _on_rotation_reset_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	var sel := ui.item_list.get_selected_items()
	if sel.is_empty():
		return

	var index := int(sel[0])
	var target := inventory_ctrl._resolve_item_node_from_list_index(env, index)
	if target == null:
		push_warning("Nodo non trovato (forse è stato eliminato).")
		_do_ui_refresh() # aggiorna stato UI (disabilita bottoni, mostra sanity warning, ecc)
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

# Auto layout per elementi diretti di un'area
func _on_auto_layout_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	var sel := ui.item_list.get_selected_items()
	if sel.is_empty():
		return

	var idx := int(sel[0])
	var n := inventory_ctrl._resolve_item_node_from_list_index(env, idx)
	if n == null or n is not LivingArea:
		return

	layout_ctrl.auto_layout_direct_elements(
		n,
		float(ui.spacing_edit.value),
		int(ui.cols_edit.value),
		undo_redo
	)

# Reset ambiente: elimina tutti i figli dell'ambiente (con undo) e resetta lista + selezione
func _on_reset_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	layout_ctrl.reset_environment_children(env, undo_redo)
	inventory_ctrl.clear_last_selection()
	_do_ui_refresh() # aggiorna stato UI (disabilita bottoni, mostra sanity warning, ecc)
	_do_env_refresh()

# Setup buttons: assicurano che player/luci/pavimento esistano, con undo, e aggiornano UI 
func _on_ensure_player_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	setup_ctrl.ensure_player(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_do_ui_refresh() # aggiorna stato UI (abilita bottoni, mostra sanity warning, ecc)

func _on_ensure_floor_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	setup_ctrl.ensure_floor(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_do_ui_refresh() # aggiorna stato UI (abilita bottoni, mostra sanity warning, ecc)

func _on_ensure_lights_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	setup_ctrl.ensure_lights(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_do_ui_refresh() # aggiorna stato UI (abilita bottoni, mostra sanity warning, ecc)

# ------------------------------------------------------------
# Fine Actions
# ------------------------------------------------------------

# Hook per aggiornare selezione nella lista quando cambia selezione in editor (o quando viene deselezionato tutto)

func _on_editor_env_selection_changed(n: Node) -> void:
	if ui.item_list == null:
		return

	if n == null:
		inventory_ctrl.on_clear_selection()
		_do_ui_refresh()
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
	_do_ui_refresh() # aggiorna stato bottoni toggle + preview
