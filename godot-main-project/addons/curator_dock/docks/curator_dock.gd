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
var _error_state := false  
var _env_list_request: HTTPRequest
var _current_page: int = 1
var _valid_items_found: int = 0
var _base_api_url: String = ""

# --- Blocca il loop infinito di selezione ---
var _is_syncing_selection := false
# ----------------------------------------------------------------------

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
	
	hooks.selected_node_transformed.connect(_on_selected_node_transformed) 
	hooks.refresh_requested.connect(_do_env_refresh) 
	hooks.editor_env_selection_changed.connect(_on_editor_env_selection_changed) 
	
	_do_ui_refresh() 
	_do_env_refresh() 

	# Instanziazione + download
	inst.configure(editor_interface, undo_redo, scene_ctrl, setup_ctrl, TEMPLATE_ENV_SCENE, CURATED_SCENES_DIR)
	inst.rebuild_finished.connect(func(success, env): 
		dl.mark_build_finished(success)

		if not success:
			_is_instantiating = false
			_error_state = true  
			ui.instantiate_progress_lbl.text = "Errore"
			_do_ui_refresh() 
			return
		await get_tree().process_frame

		env.instantiate_all_media() 
		_is_instantiating = false 
		_error_state = false
		ui.instantiate_progress_lbl.text = "Completato"
		_do_ui_refresh() 
	)

	inst.failed.connect(func(msg):
		_is_instantiating = false
		_error_state = true
		ui.instantiate_progress_lbl.text = "Errore"
		_do_ui_refresh() 
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

		var env := scene_ctrl.get_environment(editor_interface)
		if env != null:
			ui.instantiate_progress_lbl.text = "Completato" if not _error_state else "Errore"
			
			var option_index = ui.root_item_id.get_item_index(env.item_id)
			if option_index != -1:
				ui.root_item_id.select(option_index) 
			else:
				ui.root_item_id.select(-1) 
		else:
			ui.instantiate_progress_lbl.text = ""
			ui.root_item_id.select(-1)

		hooks.clear_editor_selection()
		if ui != null and ui.item_list != null:
			inventory_ctrl.on_clear_selection()
		_sync_transform_fields_from_node(null) 

		_do_ui_refresh()
		_do_env_refresh()


func _wire_ui() -> void:
	ui.global_omeka_url.text_changed.connect(func(t: String):
		scene_ctrl.save_global_default_url(editor_interface, t)
		scene_ctrl.apply_global_url_to_current_scene(editor_interface, undo_redo, t)
	)

	ui.fetch_envs_btn.pressed.connect(_on_fetch_envs_pressed)
	ui.instantiate_scene_btn.pressed.connect(_on_instantiate_scene_from_db_pressed)

	# --- EVENTI DEL TREE ---
	ui.item_list.item_activated.connect(_on_show_hide_for_selection)


	ui.item_list.item_selected.connect(func():
		# SE LO SCUDO E' ATTIVO, IGNORIAMO IL CLICK PER EVITARE IL FLICKERING
		if _is_syncing_selection:
			return

		var env := scene_ctrl.get_environment(editor_interface)
		inventory_ctrl.on_item_selected(env != null) 

		_do_ui_refresh() 
		
		if env != null:
			var node := inventory_ctrl._resolve_item_node_from_selection(env)
			if node != null:
				_sync_transform_fields_from_node(node) 

				# Alziamo lo scudo mentre modifichiamo la selezione dell'editor
				_is_syncing_selection = true
				hooks.set_suppress_selection(true)
				var ed_sel := editor_interface.get_selection()
				
				# Deselezioniamo solo se non è già l'unico oggetto selezionato
				var current_sel = ed_sel.get_selected_nodes()
				if current_sel.size() != 1 or current_sel[0] != node:
					ed_sel.clear()
					ed_sel.add_node(node) 
					
				hooks.set_suppress_selection(false)
				_is_syncing_selection = false
	)
	
	ui.item_list.button_clicked.connect(_on_tree_button_clicked)
	# --------------------------------------

	ui.auto_layout_btn.pressed.connect(_on_auto_layout_pressed)
	ui.reset_btn.pressed.connect(_on_reset_pressed)
	ui.ensure_player_btn.pressed.connect(_on_ensure_player_pressed)
	ui.ensure_floor_btn.pressed.connect(_on_ensure_floor_pressed)
	ui.ensure_lights_btn.pressed.connect(_on_ensure_lights_pressed)
	ui.rot_reset_btn.pressed.connect(_on_rotation_reset_pressed)
	ui.place_btn.pressed.connect(_on_place_pressed)


func _do_env_refresh() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return 

	var snap := scene_ctrl.scan_environment(env)
	
	# Alziamo lo scudo mentre ricostruiamo la lista, altrimenti genererebbe finti click
	_is_syncing_selection = true 
	inventory_ctrl.set_snapshot(snap, env, editor_interface)
	_error_state = not inventory_ctrl.render_list()
	_is_syncing_selection = false
	
	hooks.bind_rename_watchers_from_snapshot(snap)


func _do_ui_refresh() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	var is_environment := (env != null)

	if not is_environment: 
		ui.instantiate_progress_lbl.text = ""
		inventory_ctrl.clear_ui()
		ui.sanity_player.text = "Camera: ❌"
		ui.sanity_lights.text = "Luci: ❌"
		ui.sanity_floor.text = "Pavimento: ❌"
		ui.sanity_env.text = "Ambiente: ❌"
		ui.ensure_player_btn.disabled = true
		ui.ensure_floor_btn.disabled = true
		ui.ensure_lights_btn.disabled = true

	ui.instantiate_scene_btn.disabled = _is_instantiating

	if ui.item_list:
		ui.item_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if (_is_instantiating or not is_environment) else Control.MOUSE_FILTER_STOP
		ui.item_list.modulate.a = 0.45 if (_is_instantiating or not is_environment) else 1.0

	# place/rot reset 
	var has_selection = ui.item_list != null and ui.item_list.get_selected() != null
	ui.place_btn.disabled = (not is_environment) or _is_instantiating or _error_state or not has_selection
	ui.rot_reset_btn.disabled = (not is_environment) or _is_instantiating or _error_state or not has_selection

	ui.auto_layout_btn.disabled = true
	if is_environment and not _is_instantiating and has_selection:
		var n := inventory_ctrl._resolve_item_node_from_selection(env)
		ui.auto_layout_btn.disabled = not (n is LivingArea)
	
	ui.reset_btn.disabled = not is_environment or _is_instantiating
		
	var has_player := setup_ctrl.has_player(env)
	var has_lights := setup_ctrl.has_lights(env)
	var has_floor := setup_ctrl.has_floor(env)

	var env_loaded := is_environment and int(env.item_id) > 0 and not _error_state and not _is_instantiating
	ui.sanity_player.text = "Camera: %s" % ("✔" if has_player else "❌")
	ui.sanity_lights.text = "Luci: %s" % ("✔" if has_lights else "❌")
	ui.sanity_floor.text = "Pavimento: %s" % ("✔" if has_floor else "❌")
	ui.sanity_env.text = "Ambiente: %s" % ("✔" if env_loaded else "❌")

	ui.ensure_player_btn.disabled = has_player
	ui.ensure_floor_btn.disabled = has_floor
	ui.ensure_lights_btn.disabled = has_lights


func _on_fetch_envs_pressed() -> void:
	var base_url = ui.global_omeka_url.text.strip_edges()
	if base_url == "":
		push_error("Inserisci prima l'URL di OmekaS")
		return

	_base_api_url = base_url
	_current_page = 1
	_valid_items_found = 0

	if _env_list_request == null:
		_env_list_request = HTTPRequest.new()
		add_child(_env_list_request)
		_env_list_request.request_completed.connect(_on_env_list_downloaded)

	ui.root_item_id.clear()
	ui.root_item_id.add_item("Scansione database in corso...", 0)
	ui.root_item_id.disabled = true
	
	ui.fetch_envs_btn.disabled = true
	ui.fetch_envs_btn.text = "🔄 Pag. 1..."

	_request_page(_current_page)


func _request_page(page: int) -> void:
	var api_url = _base_api_url + "/api/items?per_page=100&page=" + str(page)
	print("Scaricamento pagina %d..." % page)
	_env_list_request.request(api_url)

func _on_env_list_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_finish_with_error("Errore connessione (Cod: " + str(response_code) + ")")
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_finish_with_error("Errore parsing JSON")
		return

	var data = json.get_data()
	if typeof(data) == TYPE_ARRAY:
		var items_in_page = data.size()

		if _current_page == 1:
			ui.root_item_id.clear()

		for item in data:
			if not item.has("lcp_form:has_participatory_item_type_f"):
				continue
				
			var type_array = item["lcp_form:has_participatory_item_type_f"]
			if typeof(type_array) != TYPE_ARRAY or type_array.is_empty():
				continue
				
			var type_dict = type_array[0]
			if typeof(type_dict) != TYPE_DICTIONARY:
				continue
				
			var item_type = str(type_dict.get("@value", ""))
			if item_type != "Ambiente":
				continue
			
			var id = int(item.get("o:id", 0))
			var title = item.get("o:title", "Senza Titolo")
			
			if id > 0:
				ui.root_item_id.add_item(str(id) + " - " + title, id)
				_valid_items_found += 1

		if items_in_page == 100:
			_current_page += 1
			ui.fetch_envs_btn.text = "🔄 Pag. " + str(_current_page) + "..."
			_request_page(_current_page)
			
		else:
			if _valid_items_found == 0:
				ui.root_item_id.add_item("Nessun Ambiente trovato", 0)
			
			ui.root_item_id.disabled = false
			ui.fetch_envs_btn.disabled = false
			ui.fetch_envs_btn.text = "🔄 Aggiorna Lista"
			print("Scaricamento completato in %d pagine. Totale Ambienti: %d" % [_current_page, _valid_items_found])
	else:
		_finish_with_error("Formato JSON inatteso")

func _finish_with_error(msg: String) -> void:
	ui.root_item_id.clear()
	ui.root_item_id.add_item(msg, 0)
	ui.root_item_id.disabled = false
	ui.fetch_envs_btn.disabled = false
	ui.fetch_envs_btn.text = "🔄 Aggiorna Lista"


func _on_instantiate_scene_from_db_pressed() -> void:
	_is_instantiating = true
	ui.instantiate_progress_lbl.text = "0%"
	_do_ui_refresh() 
	
	var selected_id = ui.root_item_id.get_selected_id()
	var desired_env_id := int(selected_id)

	inst.run(desired_env_id, ui.global_omeka_url.text)
	call_deferred("_start_dl_if_env_ready")

func _start_dl_if_env_ready() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		call_deferred("_start_dl_if_env_ready")
		return
	dl.reset()
	dl.start(env, self)

# --- FUNZIONI PER I PULSANTI NEL TREE E VISIBILITA' ---
func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	var md = item.get_metadata(0)
	if typeof(md) != TYPE_DICTIONARY: return
	
	var env = scene_ctrl.get_environment(editor_interface)
	if env == null: return
	
	var target_node: Node = null
	var iid = int(md.get("instance_id", 0))
	if iid != 0:
		target_node = instance_from_id(iid) as Node
	if target_node == null:
		target_node = env.get_node_or_null(md.get("node_path", ""))
		
	if target_node == null: return
	
	if id == 0:
		_toggle_node_visibility(target_node)
	elif id == 1:
		_toggle_node_lock(target_node)
		
	_do_env_refresh()

func _on_show_hide_for_selection() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	
	var n := inventory_ctrl._resolve_item_node_from_selection(env)
	if n == null: return
	
	_toggle_node_visibility(n)
	_do_env_refresh()

func _toggle_node_visibility(n: Node) -> void:
	# Godot gestisce la visibilità tramite la proprietà "visible" 
	# nativa nei nodi Node3D (mondo 3D) e CanvasItem (UI/2D)
	if not (n is Node3D or n is CanvasItem):
		return

	var current_vis = n.visible
	var new_vis = not current_vis

	if undo_redo != null:
		undo_redo.create_action("Toggle visibility")
		undo_redo.add_do_property(n, "visible", new_vis)
		undo_redo.add_undo_property(n, "visible", current_vis)
		undo_redo.commit_action()
	else:
		n.visible = new_vis
		
	# Diciamo a Godot di segnare la scena come "Da salvare" (*)
	# Così quando fai Play, l'Editor esporterà la versione aggiornata!
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()

func _toggle_node_lock(n: Node) -> void:
	var is_locked = n.has_meta("_edit_lock_") and n.get_meta("_edit_lock_")
	
	if is_locked:
		n.remove_meta("_edit_lock_")
	else:
		n.set_meta("_edit_lock_", true)
		
	# Diciamo a Godot che abbiamo modificato la scena, così salverà lo stato del lucchetto!
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
# ------------------------------------------------------------

func _on_place_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return

	var target := inventory_ctrl._resolve_item_node_from_selection(env)
	if target == null:
		push_warning("Nodo non trovato (forse è stato eliminato).")
		_do_ui_refresh() 
		return

	if not (target is Node3D):
		push_warning("Il nodo selezionato non è un Node3D, non posso spostarlo.")
		return

	var n3d := target as Node3D
	var old_pos := n3d.global_position
	var new_pos := Vector3(ui.offset_x.value, old_pos.y, ui.offset_z.value) 

	if undo_redo != null:
		undo_redo.create_action("Move node to X/Z offset")
		undo_redo.add_do_method(n3d, "set_global_position", new_pos)
		undo_redo.add_undo_method(n3d, "set_global_position", old_pos)
		undo_redo.commit_action()
	else:
		n3d.global_position = new_pos


func _on_rotation_reset_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return

	var target := inventory_ctrl._resolve_item_node_from_selection(env)
	if target == null:
		push_warning("Nodo non trovato (forse è stato eliminato).")
		_do_ui_refresh() 
		return

	if not (target is Node3D):
		push_warning("Il nodo selezionato non è un Node3D, non posso ruotarlo.")
		return

	var n3d := target as Node3D

	var old_rot := n3d.global_rotation_degrees
	var new_rot := Vector3(0.0, 0.0, 0.0)

	if undo_redo != null:
		undo_redo.create_action("Reset rotation")
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

func _sync_transform_fields_from_node(n: Node) -> void:
	if ui == null:
		return

	if n == null or not (n is Node3D):
		ui.offset_x.value = 0.0
		ui.offset_z.value = 0.0
		return

	var n3d := n as Node3D
	ui.offset_x.value = n3d.global_position.x
	ui.offset_z.value = n3d.global_position.z

func _on_auto_layout_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return

	var n := inventory_ctrl._resolve_item_node_from_selection(env)
	if n == null or n is not LivingArea:
		return

	layout_ctrl.auto_layout_direct_elements(
		n,
		float(ui.spacing_edit.value),
		int(ui.cols_edit.value),
		undo_redo
	)

func _on_reset_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	layout_ctrl.reset_environment_children(env, undo_redo)
	inventory_ctrl.clear_last_selection()
	_do_ui_refresh() 
	_do_env_refresh()

func _on_ensure_player_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	setup_ctrl.ensure_player(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_do_ui_refresh() 

func _on_ensure_floor_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	setup_ctrl.ensure_floor(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_do_ui_refresh() 

func _on_ensure_lights_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	setup_ctrl.ensure_lights(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_do_ui_refresh() 


func _on_editor_env_selection_changed(n: Node) -> void:
	if ui.item_list == null:
		return

	if n == null:
		_is_syncing_selection = true
		inventory_ctrl.on_clear_selection()
		_do_ui_refresh()
		inventory_ctrl.on_item_selected(scene_ctrl.get_environment(editor_interface) != null)
		_sync_transform_fields_from_node(null) 
		_is_syncing_selection = false
		return

	_sync_transform_fields_from_node(n) 

	# Alziamo lo scudo per impedire all'albero di far esplodere la selezione dell'editor!
	_is_syncing_selection = true
	hooks.set_suppress_selection(true)
	inventory_ctrl._last_selected_instance_id = n.get_instance_id()
	inventory_ctrl._restore_selection_after_render() 
	inventory_ctrl.on_item_selected(true)
	hooks.set_suppress_selection(false)
	_is_syncing_selection = false
		
	_do_ui_refresh() 

func _toast(msg: String, sec: float = 1.2) -> void:
	if not is_inside_tree():
		return

	var d := AcceptDialog.new()
	d.title = ""
	d.dialog_text = msg
	d.exclusive = true
	d.unresizable = true

	d.get_ok_button().visible = false

	add_child(d)
	d.popup_centered()

	var t := Timer.new()
	t.one_shot = true
	t.wait_time = sec
	add_child(t)
	t.timeout.connect(func():
		if is_instance_valid(d):
			d.hide()
			d.queue_free()
		if is_instance_valid(t):
			t.queue_free()
	, CONNECT_ONE_SHOT)
	t.start()
