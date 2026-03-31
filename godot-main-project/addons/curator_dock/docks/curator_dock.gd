@tool
extends VBoxContainer

const TEMPLATE_ENV_SCENE := "res://addons/living_platform_plugin/scenes/living_environment_root.tscn"
const CURATED_SCENES_DIR := "res://curated_scenes"
const MEDIA_CACHE_DIR := "res://downloaded_living_media"

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager

# controllers
var scene_ctrl := CuratorSceneController.new()
var inventory_ctrl := CuratorInventoryController.new()
var setup_ctrl := CuratorSetupController.new()

# helpers
var inst := CuratorEnvironmentInstantiator.new()
var dl := CuratorDownloadProgress.new()
var ui_builder := CuratorDockUIBuilder.new()
var hooks := CuratorEditorHooks.new()
var ui: CuratorDockUIBuilder.CuratorDockUI

var _last_scene_root: Node = null
var _had_scene := false
var _is_instantiating := false
var _error_state := false  # Env dependent, si basa sullo stato della lista e viene messo a false quando la lista renderizza correttamente
var _env_list_request: HTTPRequest
var _current_page: int = 1
var _valid_items_found: int = 0
var _base_api_url: String = ""
var _is_syncing_selection := false
var _pending_post_open_env_id: int = 0
var _pending_post_open_sync: bool = false


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
	
	# wire UI events
	_wire_ui()

	# bind inventory UI
	var icon := get_theme_icon("ImportFail", "EditorIcons")
	inventory_ctrl.bind_ui(ui.components_list, ui.preview, icon)

	# load global URL + apply to env if exists
	ui.global_omeka_url.text = scene_ctrl.load_global_default_url(editor_interface)
	scene_ctrl.apply_global_url_to_current_scene(editor_interface, ui.global_omeka_url.text)
	
	# Ascolta gli eventi di "fine" save (upload/fetch/download) dal Controller
	scene_ctrl.save_upload_finished.connect(_on_ctrl_upload_finished)
	scene_ctrl.save_fetch_finished.connect(_on_ctrl_fetch_finished)

	# Ascolta il flusso per il prefetch
	scene_ctrl.workflow_progress.connect(func(msg: String):
		ui.status_bar.text = msg
	)
	scene_ctrl.workflow_finished.connect(_on_workflow_finished)

	# HOOKS dell'editor, ascoltiamo quando cambia lo scene tree...
	hooks.bind(editor_interface, undo_redo, scene_ctrl, self)
	hooks.selected_node_transformed.connect(_on_selected_node_transformed) # rotation tracking
	hooks.refresh_requested.connect(_do_env_refresh) # refresh da editor hooks (es. tree changed, rename, ecc)
	hooks.editor_env_selection_changed.connect(_on_editor_env_selection_changed) # quando cambia selezione da scena
	
	_do_ui_refresh() # In questo modo quando avvio Godot, se c'è già una scena aperta, mostra subito lo stato corretto
	_do_env_refresh() # In questo modo quando avvio Godot, se c'è già una scena aperta, mostra subito lo stato corretto

	var initial_env = scene_ctrl.get_environment(editor_interface)
	var has_initial_env = (initial_env != null)
	ui_builder.set_collapsible_state(ui.db_section_btn, ui.db_section_content, not has_initial_env)
	ui_builder.set_collapsible_state(ui.env_section_btn, ui.env_section_content, has_initial_env)

	# CREATE SCENE
	inst.configure(editor_interface, scene_ctrl, setup_ctrl, TEMPLATE_ENV_SCENE, CURATED_SCENES_DIR)
	inst.rebuild_finished.connect(func(success, env): # callback quando l'instanziazione è finita (success=true se tutto ok, false se Error durante build)
		# segnala a dl che il build è terminato (così può chiudere quando pending==0)
		dl.mark_build_finished(success)

		if not success:
			_is_instantiating = false
			_error_state = true  # metto stato di Error (così se refresha mostra sanity warning)
			# Visto che la rebuild fallisce al 99% per mancate risposte API
			ui.status_bar.text = "Connection Error"
			_do_ui_refresh() # aggiorna stato UI (abilita bottoni, mostra sanity warning, ecc)
			return
		# Rebuild già gestisce fetch/download/istanziazione media: evitare doppio pass.
		_is_instantiating = false # Sblocco la UI
		_error_state = false
		ui.status_bar.text = "Completed"
		_do_ui_refresh() # aggiorna stato UI 
	)

	# Ascoltiamo la fine del popup dell'auto-layout
	inst.auto_layout_finished.connect(func(executed: bool):
		# Se l'utente ha fatto l'autolayout, ha reso tutto visibile. 
		# Aggiorniamo la lista a sinistra per far riaccendere gli occhietti!
		if executed:
			_do_env_refresh()
			
		# Un colpo di refresh all'inspector layout fa sempre bene
		_do_ui_refresh()
	)

	inst.failed.connect(func(msg):
		_is_instantiating = false
		_error_state = true
		if "404" in str(msg) or "HTTP" in str(msg):
			ui.status_bar.text = "Connection Error"
		else:
			ui.status_bar.text = "Error"
		_do_ui_refresh() # aggiorna stato UI 
		push_warning(msg)
	)

	dl.progress_changed.connect(func(pct, done, total): 
		if total == 0:
			return
			
		# --- FASE 1: DOWNLOAD ---
		if done < total:
			ui.status_bar.text = "Download: %d%% (%d/%d)" % [pct, done, total]
		else:
			var current_txt = ui.status_bar.text
	)

	_on_fetch_env_pressed() # Così all'avvio, carico gli envs senza dover fare "aggiorna lista"


func _process(_delta: float) -> void:
	_do_status_bar_refresh()  # Aggiorniamo costantemente lo status attuale
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	var has_scene := (sr != null)


	#...Cosa succede al cambio scena??
	if sr != _last_scene_root or has_scene != _had_scene:  # controllo se scena cambiata [cite: 6]
		_last_scene_root = sr
		_had_scene = has_scene
		
		var env := scene_ctrl.get_environment(editor_interface)
		
		# Se la nuova scena aperta non è vuota...
		if env != null:
			ui_builder.set_collapsible_state(ui.db_section_btn, ui.db_section_content, false)
			ui_builder.set_collapsible_state(ui.env_section_btn, ui.env_section_content, true)
			var saved_pwd = scene_ctrl.load_env_password(editor_interface, env.item_id)
			env.nextsave_pwd = saved_pwd
			ui.save_pwd_edit.text = saved_pwd
			
			# SELEZIONA L'AMBIENTE APERTO NELLA TENDINA E CARICA LE SCENE
			if ui.env_list != null:
				var option_index = ui.env_list.get_item_index(env.item_id)
				if option_index != -1 and ui.env_list.get_selected_id() != env.item_id:
					ui.env_list.select(option_index)
					_load_pwd_for_selected_env()
					_on_scene_fetch_pressed()
			
			if not _is_instantiating:
				if not _error_state:
					if ui.status_bar.text.strip_edges() == "":
						ui.status_bar.text = "Completed"
				else:
					if ui.status_bar.text not in ["Connection Error", "Error"]:
						ui.status_bar.text = "Error"
		else: 
			# Altrimenti, scena vuota -> Torna all'indice 0
			ui_builder.set_collapsible_state(ui.db_section_btn, ui.db_section_content, true)
			ui_builder.set_collapsible_state(ui.env_section_btn, ui.env_section_content, false)
			if ui.env_list != null and ui.env_list.item_count > 0:
				ui.env_list.select(0)  
				
			if ui.scene_list != null:
				ui.scene_list.clear()
				ui.scene_list.add_item("Firstly select an environment...", 0)
				ui.scene_list.set_item_disabled(0, true)
				ui.scene_list.select(0)
				
			ui.status_bar.text = ""
			_load_pwd_for_selected_env()

		hooks.clear_editor_selection()
		if ui != null and ui.components_list != null:
			inventory_ctrl.on_clear_selection()
		_sync_transform_fields_from_node(null)

		_do_ui_refresh()
		_do_env_refresh()

# Qua colleghiamo le funzioni ai vari bottoni/campi
func _wire_ui() -> void:
	# Se si cambia il testo dell'URL globale, salvo e applico a scena (se c'è)
	ui.global_omeka_url.text_changed.connect(func(t: String):
		scene_ctrl.save_global_default_url(editor_interface, t)
		scene_ctrl.apply_global_url_to_current_scene(editor_interface, t)
	)

	ui.fetch_env_btn.pressed.connect(_on_fetch_env_pressed)

	# Aggiorna i bottoni immediatamente quando l'utente sceglie un ambiente diverso dalla tendina
	ui.env_list.item_selected.connect(func(_idx: int):
		_load_pwd_for_selected_env()
		var selected_env_id := int(ui.env_list.get_selected_id())
		if selected_env_id > 0:
			# Scarica le scene in automatico
			_on_scene_fetch_pressed()
		else:
			# Ripristina il placeholder se seleziona "Select an environment..."
			if ui.scene_list != null:
				ui.scene_list.clear()
				ui.scene_list.add_item("Firstly select an environment...", 0)
				ui.scene_list.set_item_disabled(0, true)
		_do_ui_refresh()
	)

	ui.scene_list.item_selected.connect(func(idx: int):
		var meta = ui.scene_list.get_item_metadata(idx)
		
		# In ogni caso aggiorniamo la UI (abilita il tasto download se valido)
		_do_ui_refresh()
	)


	# Salvataggio
	ui.save_btn.pressed.connect(_on_save_pressed)
	ui.scene_fetch_btn.pressed.connect(_on_scene_fetch_pressed)
	ui.download_btn.pressed.connect(_on_download_pressed)
	
	
	# Restore Saved Components
	ui.restore_components_btn.pressed.connect(_on_restore_components_pressed)
	
	# --- EVENTI DELLA LISTA DI COMPONENTS ---
	# Al click su un elemento della lista
	ui.components_list.item_selected.connect(func():
		if _is_syncing_selection:
			return

		var env := scene_ctrl.get_environment(editor_interface)
		inventory_ctrl.on_item_selected(env != null)

		_do_ui_refresh() 
		
		if env != null:
			var node := inventory_ctrl._resolve_item_node_from_selection(env)
			if node != null:
				_sync_transform_fields_from_node(node) 

				var is_vis = node.visible if "visible" in node else true
				var is_loc = node.has_meta("_edit_lock_") and node.get_meta("_edit_lock_")

				_is_syncing_selection = true
				hooks.set_suppress_selection(true)
				var ed_sel := editor_interface.get_selection()
				
				# SE INVISIBILE O BLOCCATO: Non selezionarlo nel 3D, così non appare il gizmo!
				if not is_vis or is_loc:
					ed_sel.clear()
				else:
					# Altrimenti lo selezioniamo normalmente
					var current_sel = ed_sel.get_selected_nodes()
					if current_sel.size() != 1 or current_sel[0] != node:
						ed_sel.clear()
						ed_sel.add_node(node) 
					
				hooks.set_suppress_selection(false)
				_is_syncing_selection = false
	)
	
	# --- FINE EVENTI DELLA COMPONENTS LIST ---

	# LAYOUT COLUMN

	# State Icons 
	ui.visibility_cb.toggled.connect(_toggle_node_visibility)
	ui.lock_cb.toggled.connect(_toggle_node_lock)
	ui.face_vis_cb.toggled.connect(_toggle_face_visibility)

	# Appearance
	ui.curvature_spin.value_changed.connect(_on_curvature_changed)

	# Transforms
	ui.pos_x.value_changed.connect(_on_position_changed.unbind(1))
	ui.pos_y.value_changed.connect(_on_position_changed.unbind(1))
	ui.pos_z.value_changed.connect(_on_position_changed.unbind(1))

	ui.rot_x.value_changed.connect(_on_rotation_changed.unbind(1))
	ui.rot_y.value_changed.connect(_on_rotation_changed.unbind(1))
	ui.rot_z.value_changed.connect(_on_rotation_changed.unbind(1))

	ui.scale_x.value_changed.connect(_on_scale_changed.bind(Vector3.AXIS_X))
	ui.scale_y.value_changed.connect(_on_scale_changed.bind(Vector3.AXIS_Y))
	ui.scale_z.value_changed.connect(_on_scale_changed.bind(Vector3.AXIS_Z))

	ui.reset_pos_btn.pressed.connect(_on_reset_position_pressed)
	ui.reset_rot_btn.pressed.connect(_on_reset_rotation_pressed)
	ui.reset_scale_btn.pressed.connect(_on_reset_scale_pressed)	


# ------------------------------------------------------------
# REFRESH. gestisce il refresh della components list. La UI è refreshata in _do_ui_refresh
# ------------------------------------------------------------
func _do_env_refresh() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return 

	# nel caso ci sia un ambiente, scansiono, renderizzo la lista, aggiorno stato ui e ricollego watcher rename
	var snap := scene_ctrl.scan_environment(env)
	
	# Alziamo lo scudo mentre ricostruiamo la lista, altrimenti genererebbe finti click
	_is_syncing_selection = true 
	inventory_ctrl.set_snapshot(snap, env, editor_interface)
	var render_ok := inventory_ctrl.render_list()
	# Durante build/sync la lista può essere transitoriamente incompleta:
	# non trasformare questo in Error globale della status bar.
	if not _is_instantiating:
		_error_state = not render_ok
	_is_syncing_selection = false
	
	hooks.bind_rename_watchers_from_snapshot(snap)
	_do_ui_refresh() # Aggiorna stato UI (serve anche per undo)


# ------------------------------------------------------------
# REFRESH: gestisce il refresh della UI (ma non della lista)
# ------------------------------------------------------------
func _do_ui_refresh() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	
	var has_valid_open_env := (env != null) and int(env.item_id) > 0
	var has_selection := ui.components_list != null and ui.components_list.get_selected() != null
	var can_transform := has_valid_open_env and has_selection and not _is_instantiating and not _error_state
	var disable_inventory := _is_instantiating or not has_valid_open_env
	
	if not has_valid_open_env:  
		inventory_ctrl.clear_ui()
	
	# --- TENDINE E DOWNLOAD ---
	var selected_env_id := 0
	if ui.env_list != null and ui.env_list.item_count > 0:
		selected_env_id = int(ui.env_list.get_selected_id())
		
	var has_valid_dropdown_env := selected_env_id > 0
	
	# Il tasto Fetch (Update) si abilita SOLO se c'è un env selezionato
	ui.scene_fetch_btn.disabled = _is_instantiating or not has_valid_dropdown_env
	
	# Controllo se c'è una scena valida selezionata per il Download o Create
	var has_valid_scene_selected := false
	var is_create_selected := false
	
	if ui.scene_list != null:
		var sel_idx = ui.scene_list.get_selected()
		if sel_idx > 0 and not ui.scene_list.is_item_disabled(sel_idx):
			has_valid_scene_selected = true
			var meta = ui.scene_list.get_item_metadata(sel_idx)
			if typeof(meta) == TYPE_STRING and meta == "CREATE_ACTION":
				is_create_selected = true

	# Il tasto Azione si abilita SOLO se ci sono sia env valido che scena/create valido
	ui.download_btn.disabled = _is_instantiating or not has_valid_dropdown_env or not has_valid_scene_selected
	
	# Cambiamo dinamicamente il testo del bottone
	if is_create_selected:
		ui.download_btn.text = "CREATE"
	else:
		ui.download_btn.text = "DOWNLOAD"

	# Il tasto Download si abilita SOLO se ci sono sia env valido che scena valida
	ui.download_btn.disabled = _is_instantiating or not has_valid_dropdown_env or not has_valid_scene_selected
	
	# Tasti di Upload
	ui.save_btn.disabled = not has_valid_open_env or _is_instantiating
	ui.restore_components_btn.disabled = _is_instantiating or not has_valid_open_env

	if ui.components_list:
		ui.components_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if disable_inventory else Control.MOUSE_FILTER_STOP
		ui.components_list.modulate.a = 0.45 if disable_inventory else 1.0
		
	ui.env_section_content.mouse_filter = Control.MOUSE_FILTER_IGNORE if _is_instantiating else Control.MOUSE_FILTER_STOP
	ui.env_section_content.modulate.a = 0.65 if _is_instantiating else 1.0

	# --- AGGIORNA LAYOUT INSPECTOR IN BASE ALLA SELEZIONE ---
	var is_node_visible = false
	var is_node_locked = false
	var has_valid_target = false

	if can_transform:
		var target := inventory_ctrl._resolve_item_node_from_selection(env)
		if target != null:
			has_valid_target = true
			is_node_visible = target.visible if "visible" in target else true
			is_node_locked = target.has_meta("_edit_lock_") and target.get_meta("_edit_lock_")
			
			ui.visibility_cb.set_block_signals(true)
			ui.lock_cb.set_block_signals(true)
			
			ui.visibility_cb.button_pressed = is_node_visible
			ui.lock_cb.button_pressed = is_node_locked
			
			# AGGIORNAMENTO DELLE ICONE STATO
			var eye_icon = "GuiVisibilityVisible" if is_node_visible else "GuiVisibilityHidden"
			ui.visibility_cb.icon = get_theme_icon(eye_icon, "EditorIcons")
			
			var lock_icon = "Lock" if is_node_locked else "Unlock"
			ui.lock_cb.icon = get_theme_icon(lock_icon, "EditorIcons")
			
			ui.visibility_cb.set_block_signals(false)
			ui.lock_cb.set_block_signals(false)
			
			ui.visibility_cb.disabled = false
			ui.lock_cb.disabled = not is_node_visible
			ui.face_vis_cb.disabled = not is_node_visible

			# --- Gestione Face Visibility and Appearance / LivingElement ---
			var is_face_vis = true
			var has_face_mesh = false
			var is_media_curvable = false
			
			if target is LivingElement: # Imposto gli stati del target solo se è un LivingElement, altrimenti lascio default (es. se è un figlio di un elemento)
				is_face_vis = target.face_visible
				has_face_mesh = target._has_face_in_children()
				is_media_curvable = target._has_2d_in_children()


			if ui.face_vis_cb != null:
				ui.face_vis_cb.set_block_signals(true)
				ui.face_vis_cb.button_pressed = is_face_vis
				ui.face_vis_cb.disabled = not has_face_mesh or not is_node_visible
				var face_icon = "MeshTexture" if is_face_vis else "MeshItem"
				ui.face_vis_cb.icon = get_theme_icon(face_icon, "EditorIcons")
				ui.face_vis_cb.set_block_signals(false)

			if ui.curvature_spin != null:
				ui.appearance_container.visible = is_media_curvable
				if is_media_curvable:
					ui.curvature_spin.set_block_signals(true)
					ui.curvature_spin.value = target.curvature
					ui.curvature_spin.set_block_signals(false)

	# Se non possiamo trasformare (nessuna selezione) o il target è nullo, resettiamo tutto
	if not has_valid_target:
		if ui.visibility_cb: 
			ui.visibility_cb.set_block_signals(true)
			ui.visibility_cb.button_pressed = false
			ui.visibility_cb.disabled = true
			ui.visibility_cb.icon = get_theme_icon("GuiVisibilityVisible", "EditorIcons") # Reset icona
			ui.visibility_cb.set_block_signals(false)
		if ui.lock_cb: 
			ui.lock_cb.set_block_signals(true)
			ui.lock_cb.button_pressed = false
			ui.lock_cb.disabled = true
			ui.lock_cb.icon = get_theme_icon("Unlock", "EditorIcons") # Reset icona
			ui.lock_cb.set_block_signals(false)
		if ui.face_vis_cb: 
			ui.face_vis_cb.set_block_signals(true)
			ui.face_vis_cb.button_pressed = false
			ui.face_vis_cb.disabled = true
			ui.face_vis_cb.icon = get_theme_icon("MeshTexture", "EditorIcons") # Reset icona
			ui.face_vis_cb.set_block_signals(false)
		if ui.appearance_container != null:
			ui.appearance_container.visible = false 

	# --- CAMPI TRASFORMAZIONE ---
	var can_edit_transforms = has_valid_target and is_node_visible and not is_node_locked
	
	if ui.reset_pos_btn: ui.reset_pos_btn.disabled = not can_edit_transforms
	if ui.reset_rot_btn: ui.reset_rot_btn.disabled = not can_edit_transforms
	if ui.reset_scale_btn: ui.reset_scale_btn.disabled = not can_edit_transforms

	if ui.pos_x: ui.pos_x.editable = can_edit_transforms
	if ui.pos_y: ui.pos_y.editable = can_edit_transforms
	if ui.pos_z: ui.pos_z.editable = can_edit_transforms
	if ui.rot_x: ui.rot_x.editable = can_edit_transforms
	if ui.rot_y: ui.rot_y.editable = can_edit_transforms
	if ui.rot_z: ui.rot_z.editable = can_edit_transforms
	if ui.scale_x: ui.scale_x.editable = can_edit_transforms
	if ui.scale_y: ui.scale_y.editable = can_edit_transforms
	if ui.scale_z: ui.scale_z.editable = can_edit_transforms

# ------------------------------------------------------------
# REFRESH. gestisce il refresh della status bar, costante in process
# ------------------------------------------------------------
func _do_status_bar_refresh() -> void:
	if ui == null or ui.status_bar == null:
		return

	var raw := ui.status_bar.text.strip_edges()
	var normalized := raw
	var is_error := false

	if normalized == "":
		if ui.status_bar_panel != null:
			ui.status_bar_panel.visible = false
		return

	if normalized == "Completed":
		normalized = "Scene Successfully Loaded"
	elif normalized == "Error":
		normalized = "Operation Failed"
		is_error = true
	elif normalized == "Connection Error":
		normalized = "Connection Error During Operation"
		is_error = true
	elif normalized == "Elaborating...":
		normalized = "Elaborating..."

	if "Error" in normalized.to_lower():
		is_error = true

	# Se il testo è effettivamente cambiato rispetto a prima...
	if normalized != ui.status_bar.text:
		ui.status_bar.text = normalized
		
		# Avviamo il timer se è andato tutto a buon fine ---
		if normalized == "Scene Successfully Loaded":
			_schedule_status_bar_clear()

	if ui.status_bar_panel != null:
		ui.status_bar_panel.visible = true

	if is_error:
		ui.status_bar.add_theme_color_override("font_color", Color(1.0, 0.78, 0.78))
	else:
		ui.status_bar.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))


func _schedule_status_bar_clear() -> void:
	await get_tree().create_timer(3.0).timeout
	
	if not is_instance_valid(ui) or not is_instance_valid(ui.status_bar):
		return
		
	# Controlliamo se la barra dice ANCORA "Scene Successfully Loaded".
	# Questo evita di cancellare la barra se nei 5 secondi di attesa
	# il curatore ha avviato un nuovo download ("Elaborating...")!
	if ui.status_bar.text == "Scene Successfully Loaded":
		ui.status_bar.text = ""
		if is_instance_valid(ui.status_bar_panel):
			ui.status_bar_panel.visible = false








# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------

# ------------------------------------------------------------
# FETCHING env
# ------------------------------------------------------------
func _on_fetch_env_pressed() -> void:
	var base_url = ui.global_omeka_url.text.strip_edges()
	if base_url == "":
		push_error("Inserisci prima l'URL di OmekaS")
		return

	if not base_url.begins_with("http://") and not base_url.begins_with("https://"):
		base_url = "https://" + base_url

	# Svuotiamo eventuali stati d'Error quando si avvia un refresh della lista
	_error_state = false
	ui.status_bar.text = ""

	# Inizializziamo lo stato
	_base_api_url = base_url
	_current_page = 1
	_valid_items_found = 0

	# Prepariamo il nodo HTTPRequest se non esiste
	if _env_list_request == null:
		_env_list_request = HTTPRequest.new()
		add_child(_env_list_request)
		_env_list_request.request_completed.connect(_on_env_list_downloaded)

	# Mettiamo la UI in stato di caricamento assoluto
	ui.env_list.clear()
	ui.env_list.add_item("Querying the database...", 0)
	ui.env_list.disabled = true
	
	# Usiamo il bottone per mostrare il progresso
	ui.fetch_env_btn.disabled = true
	ui.fetch_env_btn.text = "Pag. 1..."

	# Avviamo la richiesta della prima pagina
	_request_page(_current_page)

# Funzione separata che scarica una pagina specifica
func _request_page(page: int) -> void:
	# Chiediamo 100 elementi alla volta
	var api_url = _base_api_url + "/api/items?per_page=100&page=" + str(page)
	print("Downloading page %d..." % page)
	
	# Salviamo il risultato della richiesta
	var err = _env_list_request.request(api_url)
	
	# Se fallisce istantaneamente (es. URL malformato o invalid scheme), sblocchiamo la UI!
	if err != OK:
		_finish_with_error("Invalid URL or Request Error")
	

func _on_env_list_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_finish_with_error("Connection Error (Code: " + str(response_code) + ")")
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_finish_with_error("Error parsing JSON")
		return

	var data = json.get_data()
	if typeof(data) == TYPE_ARRAY:
		var items_in_page = data.size()

		# Se siamo alla prima pagina, prepariamo la tendina
		if _current_page == 1:
			ui.env_list.clear()
			ui.env_list.add_item("Select an Environment...", 0) 
			ui.env_list.set_item_disabled(0, true)

		# Filtriamo gli elementi in base alla tua struttura Omeka S
		for item in data:
			# 1. Controlliamo se è un Participatory Item generico
			var types = item.get("@type", [])
			if typeof(types) != TYPE_ARRAY or not "lcp_form:Participatory_item_form" in types:
				continue
				
			# 2. Controlliamo se la tipologia specifica è "Ambiente"
			var part_type_arr = item.get("lcp_form:has_participatory_item_type_f", [])
			if typeof(part_type_arr) != TYPE_ARRAY or part_type_arr.is_empty():
				continue
				
			var part_type_val = str(part_type_arr[0].get("@value", ""))
			if part_type_val != "Ambiente":
				continue # Se è un'Area o un Oggetto Componente, lo scartiamo
				
			# 3. Estraiamo Titolo e ID
			var title = str(item.get("o:title", "No Title"))
			var env_id = int(item.get("o:id", 0))
			
			if env_id > 0:
				ui.env_list.add_item(title, env_id)
				_valid_items_found += 1

		# Gestione Paginazione (richiede le pagine successive se ce ne sono 100)
		if items_in_page == 100:
			_current_page += 1
			ui.fetch_env_btn.text = "Pag. " + str(_current_page) + "..."
			_request_page(_current_page)
			
		else:
			# --- FINE DELLA SCANSIONE ---
			if _valid_items_found == 0:
				ui.env_list.set_item_text(0, "No Environments Found")
			
			var env := scene_ctrl.get_environment(editor_interface)
			var has_valid_open_env := (env != null) and int(env.item_id) > 0 
			var found_open_env = false
			
			if has_valid_open_env:
				var option_index = ui.env_list.get_item_index(env.item_id)
				if option_index != -1:
					ui.env_list.select(option_index) 
					found_open_env = true
					#_load_pwd_for_selected_env()
					_on_scene_fetch_pressed() 
					
			if not found_open_env:
				# Seleziona indice 0 e formatta lista scene
				if ui.env_list.item_count > 0:
					ui.env_list.select(0)
				if ui.scene_list != null:
					ui.scene_list.clear()
					ui.scene_list.add_item("Firstly select an environment...", 0)
					ui.scene_list.set_item_disabled(0, true)

			# Ripristiniamo la UI
			ui.env_list.disabled = false
			ui.fetch_env_btn.disabled = false
			ui.fetch_env_btn.text = "Update List"
			print("Curator Dock: Found %d Environments in %d pages." % [_valid_items_found, _current_page])
			_do_ui_refresh()
	else:
		_finish_with_error("Unexpected JSON Format")

# Helper per ripristinare la UI in caso di errori
func _finish_with_error(msg: String) -> void:
	ui.env_list.clear()
	ui.env_list.add_item(msg, 0)
	ui.env_list.disabled = false
	ui.fetch_env_btn.disabled = false
	ui.fetch_env_btn.text = "Update List"


# ------------------------------------------------------------
# SAVING ACTIONS
# ------------------------------------------------------------
func _on_save_pressed() -> void:
	var root_node = scene_ctrl.edited_scene_root(editor_interface)
	if root_node == null:
		_toast("No open scenes to save.", 2.0)
		return
		
	var current_path = root_node.scene_file_path
	var current_name = current_path.get_file()
	
	# Passiamo il nome al nostro traduttore
	var display_name = _to_pretty_name(current_name)
		
	# --- CREIAMO IL POPUP DI SALVATAGGIO ---
	var dialog = ConfirmationDialog.new()
	dialog.title = "Save & Upload"
	
	var vbox = VBoxContainer.new()
	var lbl = Label.new()
	lbl.text = "Type a name for this scene (e.g. Environment Name - Date - Your Initials):"
	vbox.add_child(lbl)
	
	var name_edit = LineEdit.new()
	name_edit.text = display_name # Mostriamo il nome pulito
	name_edit.custom_minimum_size = Vector2(350, 0)
	vbox.add_child(name_edit)
	
	var error_lbl = Label.new()
	error_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	error_lbl.hide()
	vbox.add_child(error_lbl)
	
	dialog.add_child(vbox)
	add_child(dialog)
	
	# Controllo in tempo reale usando la traduzione in file sicuro
	name_edit.text_changed.connect(func(new_text: String):
		var check_name = _to_safe_filename(new_text) # Trasforma "Mio test" in "mio_test.tscn"
		var base_dir = current_path.get_base_dir() if current_path != "" else CURATED_SCENES_DIR
		var check_path = base_dir.path_join(check_name)
		
		if check_path != current_path and FileAccess.file_exists(check_path):
			error_lbl.text = "⚠️ Attention: a scene with this name already exists and will be overwritten"
			error_lbl.show()
		else:
			error_lbl.hide()
	)
	
	# Quando l'utente preme "OK"
	dialog.confirmed.connect(func():
		var safe_name = _to_safe_filename(name_edit.text) # Ripristina underscore e .tscn
			
		var base_dir = current_path.get_base_dir() if current_path != "" else CURATED_SCENES_DIR
		var new_path = base_dir.path_join(safe_name)
		
		var needs_rename = (current_path == "" or new_path != current_path)
		
		dialog.hide()
		_execute_save_and_upload.call_deferred(current_path, new_path, needs_rename)
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	
	name_edit.text_submitted.connect(func(_testo):
		dialog.hide()
		dialog.emit_signal("confirmed")
	)
	
	dialog.popup_centered(Vector2(400, 100))
	
	name_edit.grab_focus()
	# Ora non c'è più il .tscn da schivare, possiamo comodamente selezionare tutto il testo!
	name_edit.select_all()


func _execute_save_and_upload(old_path: String, new_path: String, needs_rename: bool) -> void:
	# Usciamo dal flusso dei segnali UI aspettando un decimo di secondo.
	# Questo permette all'editor di mettersi "a riposo" prima di spawnare la barra di caricamento.
	await get_tree().create_timer(0.1).timeout
	
	ui.save_btn.disabled = true
	ui.save_btn.text = "SAVING..."
	
	if needs_rename:
		# 1. Salvataggio nativo (Ora Godot può mostrare la barra senza esplodere)
		editor_interface.save_scene_as(new_path)
		
		# 2. Diamo a Windows e a Godot tempo per sbloccare il vecchio file
		await get_tree().create_timer(0.5).timeout
		
		# 3. Cancellazione forzata
		if old_path != "" and FileAccess.file_exists(old_path):
			var da = DirAccess.open(old_path.get_base_dir())
			if da:
				da.remove(old_path.get_file())
				
		# 4. Aggiorniamo la vista dell'editor
		EditorInterface.get_resource_filesystem().scan()
		await get_tree().create_timer(0.5).timeout
	else:
		editor_interface.save_scene()
		await get_tree().create_timer(0.5).timeout

	# 5. Eseguiamo l'upload
	scene_ctrl.upload_scene(editor_interface, ui.save_pwd_edit.text)

func _on_ctrl_upload_finished(success: bool, msg: String) -> void:
	_toast(msg, 2.0)
	if not success:
		push_error("Curator Dock: " + msg)
	ui.save_btn.text = "SAVE..."
	ui.save_btn.disabled = false
	# _do_ui_refresh()


func _on_scene_fetch_pressed() -> void:
	var selected_env_id := int(ui.env_list.get_selected_id())
	if selected_env_id <= 0:
		ui.scene_list.clear()
		ui.scene_list.add_item("Firstly select an environment...", 0)
		ui.scene_list.set_item_disabled(0, true)
		_do_ui_refresh() # Bloccherà il tasto download
		return

	ui.scene_fetch_btn.disabled = true
	ui.scene_fetch_btn.text = "Updating..."
	ui.scene_list.clear()
	ui.scene_list.add_item("Looking for scenes...", 0)
	ui.scene_list.set_item_disabled(0, true)
	ui.scene_list.select(0)
	
	scene_ctrl.fetch_remote_scenes_for_env(
		self,
		ui.global_omeka_url.text.strip_edges(),
		selected_env_id,
		ui.save_pwd_edit.text
	)

func _on_ctrl_fetch_finished(success: bool, file_list: Array, msg: String) -> void:
	ui.scene_fetch_btn.disabled = false
	ui.scene_fetch_btn.text = "Update List"
	ui.scene_list.clear()
	
	# Aggiungiamo sempre un placeholder disabilitato come elemento 0
	ui.scene_list.add_item("Select a scene...", 0)
	ui.scene_list.set_item_disabled(0, true)
	
	var count = 1
	
	if not success:
		ui.scene_list.set_item_text(0, "Connection Error or missing password")
		_toast(msg, 3.5)
	else:
		for f in file_list:
			if typeof(f) == TYPE_DICTIONARY:
				var fname = str(f.get("name", ""))
				if fname.ends_with(".tscn"):
					# Rendiamo appealing il nome
					var display_name = _to_pretty_name(fname)
					
					# Mostriamo all'utente il nome leggibile senza .tscn
					ui.scene_list.add_item(display_name, count)
					# Salviamo il VERO nome del file nei metadati per far funzionare il download!
					ui.scene_list.set_item_metadata(count, fname)
					count += 1
					
		if count == 1: 
			ui.scene_list.set_item_text(0, "No scenes found, create one")

	# Opzione CREATE sempre per ultima
	var create_idx = ui.scene_list.item_count
	ui.scene_list.add_item("+", create_idx)
	ui.scene_list.set_item_metadata(create_idx, "CREATE_ACTION")
	
	# Selezioniamo il placeholder e sblocchiamo il controllo
	ui.scene_list.disabled = false
	ui.scene_list.select(0)
	
	# Passiamo la palla al refresh per spegnere il tasto download finché l'utente non fa click su una scena
	_do_ui_refresh()

func _on_download_pressed() -> void:
	var selected_env_id := int(ui.env_list.get_selected_id())
	if selected_env_id <= 0:
		_toast("Select a valid environment first", 2.0)
		return

	var selected_idx = ui.scene_list.get_selected()
	if selected_idx < 0 or ui.scene_list.is_item_disabled(selected_idx):
		_toast("Select a valid scene in the list or create a new one +", 2.0)
		return
		
	var meta = ui.scene_list.get_item_metadata(selected_idx)
	
	# --- BIVIO: CREATE O DOWNLOAD? ---
	if typeof(meta) == TYPE_STRING and meta == "CREATE_ACTION":
		_on_scene_fetch_pressed() # Riportiamo la tendina all'elemento 0
		_on_create_new_scene()
		return

	# Altrimenti, è un vero download
	var remote_file_name = meta
	if typeof(remote_file_name) != TYPE_STRING or remote_file_name == "":
		return
		
	ui.download_btn.disabled = true
	ui.download_btn.text = "Initializing..."
	_is_instantiating = true
	_error_state = false
	
	# Passiamo tutto al Controller
	scene_ctrl.download_and_setup_remote_scene(
		self, 
		editor_interface, 
		ui.global_omeka_url.text.strip_edges(),
		selected_env_id,
		remote_file_name,
		ui.save_pwd_edit.text.strip_edges(),
		dl
	)

func _on_workflow_finished(success: bool, msg: String) -> void:
	_is_instantiating = false
	_error_state = not success
	_toast(msg, 3.0)
	
	ui.download_btn.text = "DOWNLOAD"
	ui.status_bar.text = "Completed" if success else "Error"
	
	if success:
		_mark_sync_completed()
		var env := scene_ctrl.get_environment(editor_interface)
		setup_ctrl.ensure_all(env, scene_ctrl.edited_scene_root(editor_interface))
		
	_do_ui_refresh()
	_do_env_refresh()

# ------------------------------------------------------------
# CREATE NEW SCENE
# ------------------------------------------------------------
func _on_create_new_scene() -> void:
	var env := scene_ctrl.get_environment(editor_interface)

	var selected_idx := ui.env_list.get_selected() if ui.env_list != null else -1
	var selected_env_id := int(ui.env_list.get_selected_id()) if ui.env_list != null else 0
	
	if selected_env_id <= 0 or selected_idx < 0:
		_toast("Firstly select an environment", 2.0)
	else:
		_is_instantiating = true
		_error_state = false
		ui.status_bar.text = "Creating a new scene..."
		
		# Recuperiamo il nome testuale dell'ambiente selezionato dalla tendina
		var env_name = ui.env_list.get_item_text(selected_idx)
		
		dl.reset()
		call_deferred("_start_dl_if_env_ready")
		_do_ui_refresh()
		
		# Passiamo ID, Nome Ambiente, e URL
		inst.run(selected_env_id, env_name, ui.global_omeka_url.text.strip_edges())
		


# ------------------------------------------------------------
# DOWNLOAD COMPOSITION BTN
# ------------------------------------------------------------
# Aggiorna la composition
func _on_restore_components_pressed() -> void:
	# Evita re-entrance (doppio click o trigger concorrenti).
	if _is_instantiating:
		return

	# Se c'era un post-open sync accodato, la richiesta manuale ha priorità.
	_pending_post_open_sync = false

	var env := scene_ctrl.get_environment(editor_interface)

	# Caso di refresh
	_is_instantiating = true
	ui.status_bar.text = "Elaborating..."
	_do_ui_refresh()

	dl.reset()
	dl.start(env, self)

	_bind_env_import_progress(env)

	env.rebuild_completed.connect(func(success: bool):
		dl.mark_build_finished(success)
		_is_instantiating = false
		_error_state = not success

		if success:
			ui.status_bar.text = "Completed"
			_mark_sync_completed()
		else:
			var err_msg = env.title if env.title != null else ""
			if "404" in err_msg or "HTTP" in err_msg:
				ui.status_bar.text = "Connection Error"
			else:
				ui.status_bar.text = "Error"

		_do_ui_refresh()
		_do_env_refresh()
	, CONNECT_ONE_SHOT)

	# Sync completo: deve ripristinare item mancanti e aggiornare media.
	env.rebuild_environment()

func _start_dl_if_env_ready() -> void:
	while _is_instantiating and is_inside_tree():
		var env := scene_ctrl.get_environment(editor_interface)
		if env != null:
			dl.reset()
			dl.start(env, self)
			_bind_env_import_progress(env) 
			return
		await get_tree().process_frame

# ------------------------------------------------------------
# Inspector Layout Actions
# ------------------------------------------------------------
func _toggle_node_visibility(is_visible: bool) -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	var target := inventory_ctrl._resolve_item_node_from_selection(env)
	if target == null: return

	if not (target is Node3D or target is CanvasItem):
		return

	if undo_redo != null:
		undo_redo.create_action("Toggle visibility")
		undo_redo.add_do_property(target, "visible", is_visible)
		undo_redo.add_undo_property(target, "visible", not is_visible)
		undo_redo.commit_action()
	else:
		target.visible = is_visible

	# --- RIMOZIONE GIZMO ---
	if not is_visible:
		# Se lo nascondiamo, sganciamo subito il gizmo dall'editor 3D
		var ed_sel := editor_interface.get_selection()
		ed_sel.clear()
	else:
		# Se lo rendiamo visibile e non è bloccato, riattiviamo il gizmo
		var is_loc = target.has_meta("_edit_lock_") and target.get_meta("_edit_lock_")
		if not is_loc:
			var ed_sel := editor_interface.get_selection()
			ed_sel.clear()
			ed_sel.add_node(target)

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()

	_do_ui_refresh() # Disabilita/abilita le spinbox e i bottoni
	_do_env_refresh() # Aggiorna le icone grigie della lista


func _toggle_node_lock(is_locked: bool) -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	var target := inventory_ctrl._resolve_item_node_from_selection(env)
	if target == null: return
	
	if is_locked:
		target.set_meta("_edit_lock_", true)
		# --- RIMOZIONE GIZMO ---
		var ed_sel := editor_interface.get_selection()
		ed_sel.clear()
	else:
		target.remove_meta("_edit_lock_")
		# --- RIPRISTINO GIZMO ---
		var is_vis = target.visible if "visible" in target else true
		if is_vis:
			var ed_sel := editor_interface.get_selection()
			ed_sel.clear()
			ed_sel.add_node(target)
	
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
		
	_do_ui_refresh() # Disabilita/abilita le spinbox e i bottoni
	_do_env_refresh() # Aggiorna l'icona del lucchetto
# ------------------------------------------------------------

func _toggle_face_visibility(is_visible: bool) -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	var target := inventory_ctrl._resolve_item_node_from_selection(env)
	
	# Solo i LivingElement hanno questa proprietà!
	if target == null or not (target is LivingElement): 
		return

	if undo_redo != null:
		undo_redo.create_action("Toggle Face Visibility")
		undo_redo.add_do_property(target, "face_visible", is_visible)
		undo_redo.add_do_method(target, "apply_face_visibility")
		undo_redo.add_undo_property(target, "face_visible", not is_visible)
		undo_redo.add_undo_method(target, "apply_face_visibility")
		undo_redo.commit_action()
	else:
		target.face_visible = is_visible
		target.apply_face_visibility()

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()

	_do_ui_refresh()


# ==============================================================================
# APPEARANCE FUNCTIONS
# ==============================================================================
func _on_curvature_changed(new_val: float) -> void:
	if _is_syncing_selection: return
	
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	
	var target := inventory_ctrl._resolve_item_node_from_selection(env)
	if target == null or not target._has_2d_in_children(): 
		return

	var old_val = target.curvature
	
	# Evitiamo di registrare cambiamenti nulli
	if is_equal_approx(old_val, new_val): 
		return

	if undo_redo != null:
		undo_redo.create_action("Change Media Curvature")
		undo_redo.add_do_property(target, "curvature", new_val)
		undo_redo.add_undo_property(target, "curvature", old_val)
		undo_redo.commit_action()
	else:
		target.curvature = new_val

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()



# ==============================================================================
# TRANSFORM FUNCTIONS
# ==============================================================================

# POSITION (Applica la posizione digitata su X, Y, Z)
func _on_position_changed() -> void:
	if _is_syncing_selection: return # Evita di registrare l'azione se stiamo solo cliccando l'oggetto
	
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	var target := inventory_ctrl._resolve_item_node_from_selection(env) as Node3D
	if target == null: return

	var old_pos := target.global_position
	var new_pos := Vector3(ui.pos_x.value, ui.pos_y.value, ui.pos_z.value) 

	if undo_redo != null:
		undo_redo.create_action("Change Position")
		undo_redo.add_do_property(target, "global_position", new_pos)
		undo_redo.add_undo_property(target, "global_position", old_pos)
		undo_redo.commit_action()
	else:
		target.global_position = new_pos

# ROTATE (Applica la rotazione digitata su X, Y, Z)
func _on_rotation_changed() -> void:
	if _is_syncing_selection: return
	
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	var target := inventory_ctrl._resolve_item_node_from_selection(env) as Node3D
	if target == null: return

	var old_rot := target.rotation_degrees
	var new_rot := Vector3(ui.rot_x.value, ui.rot_y.value, ui.rot_z.value)

	if undo_redo != null:
		undo_redo.create_action("Change Rotation")
		undo_redo.add_do_property(target, "rotation_degrees", new_rot)
		undo_redo.add_undo_property(target, "rotation_degrees", old_rot)
		undo_redo.commit_action()
	else:
		target.rotation_degrees = new_rot

# SCALE (Unificata: calcola proporzioni e sincronizza gli altri assi)
func _on_scale_changed(new_value: float, modified_axis: int) -> void:
	if _is_syncing_selection: return

	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	var target := inventory_ctrl._resolve_item_node_from_selection(env) as Node3D
	if target == null: return

	var base_size = _get_item_base_size(target)
	var base_val = base_size[modified_axis]

	# Evitiamo divisioni per zero
	if base_val <= 0.0001: return 

	# 1. Calcoliamo il vero moltiplicatore matematico
	var uniform_scale = new_value / base_val
	var new_scale = Vector3(uniform_scale, uniform_scale, uniform_scale)
	var old_scale = target.scale
	
	# 2. Aggiorniamo visivamente gli altri due spinbox per mantenerli proporzionali
	var target_size = base_size * uniform_scale
	_is_syncing_selection = true 
	if modified_axis != Vector3.AXIS_X: ui.scale_x.value = target_size.x
	if modified_axis != Vector3.AXIS_Y: ui.scale_y.value = target_size.y
	if modified_axis != Vector3.AXIS_Z: ui.scale_z.value = target_size.z
	_is_syncing_selection = false

	# 3. Applichiamo al modello fisico
	if undo_redo != null:
		undo_redo.create_action("Scale Object (Uniform)")
		undo_redo.add_do_property(target, "scale", new_scale)
		undo_redo.add_undo_property(target, "scale", old_scale)
		undo_redo.commit_action()
	else:
		target.scale = new_scale
		
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


# ==============================================================================
# RESETS
# ==============================================================================

func _on_reset_position_pressed() -> void:
	if _is_syncing_selection: return
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	var target := inventory_ctrl._resolve_item_node_from_selection(env) as Node3D
	if target == null: return

	var old_pos := target.global_position
	var new_pos := Vector3.ZERO 

	if old_pos.is_equal_approx(new_pos): return

	if undo_redo != null:
		undo_redo.create_action("Reset Position")
		undo_redo.add_do_property(target, "global_position", new_pos)
		undo_redo.add_undo_property(target, "global_position", old_pos)
		undo_redo.commit_action()
	else:
		target.global_position = new_pos
		
	_sync_transform_fields_from_node(target)

func _on_reset_rotation_pressed() -> void:
	if _is_syncing_selection: return
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	var target := inventory_ctrl._resolve_item_node_from_selection(env) as Node3D
	if target == null: return

	var old_rot := target.rotation_degrees
	var new_rot := Vector3.ZERO

	if old_rot.is_equal_approx(new_rot): return

	if undo_redo != null:
		undo_redo.create_action("Reset Rotation")
		undo_redo.add_do_property(target, "rotation_degrees", new_rot)
		undo_redo.add_undo_property(target, "rotation_degrees", old_rot)
		undo_redo.commit_action()
	else:
		target.rotation_degrees = new_rot
		
	_sync_transform_fields_from_node(target)

func _on_reset_scale_pressed() -> void:
	if _is_syncing_selection: return
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	var target := inventory_ctrl._resolve_item_node_from_selection(env) as Node3D
	if target == null: return

	var old_scale := target.scale
	var new_scale := Vector3.ONE 

	if old_scale.is_equal_approx(new_scale): return

	if undo_redo != null:
		undo_redo.create_action("Reset Scale")
		undo_redo.add_do_property(target, "scale", new_scale)
		undo_redo.add_undo_property(target, "scale", old_scale)
		undo_redo.commit_action()
	else:
		target.scale = new_scale
		
	if Engine.is_editor_hint(): EditorInterface.mark_scene_as_unsaved()
	_sync_transform_fields_from_node(target)


# ==============================================================================
# UI SYNCING (Quando clicchi qualcosa nel Viewport)
# ==============================================================================

func _sync_transform_fields_from_node(n: Node) -> void:
	if ui == null: return

	if n == null or not (n is Node3D):
		ui.pos_x.value = 0.0
		ui.pos_y.value = 0.0
		ui.pos_z.value = 0.0
		ui.rot_x.value = 0.0
		ui.rot_y.value = 0.0
		ui.rot_z.value = 0.0
		ui.scale_x.value = 0.0
		ui.scale_y.value = 0.0
		ui.scale_z.value = 0.0
		return

	var n3d := n as Node3D
	var base_size = _get_item_base_size(n3d)
	var current_size_in_meters = base_size * n3d.scale

	_is_syncing_selection = true

	ui.pos_x.value = n3d.global_position.x
	ui.pos_y.value = n3d.global_position.y
	ui.pos_z.value = n3d.global_position.z

	ui.rot_x.value = n3d.rotation_degrees.x
	ui.rot_y.value = n3d.rotation_degrees.y
	ui.rot_z.value = n3d.rotation_degrees.z

	ui.scale_x.value = current_size_in_meters.x
	ui.scale_y.value = current_size_in_meters.y
	ui.scale_z.value = current_size_in_meters.z

	_is_syncing_selection = false


func _on_selected_node_transformed(_node: Node3D, global_pos: Vector3, global_rot_deg: Vector3) -> void:
	if ui == null: return
		
	_is_syncing_selection = true
	
	if not ui.pos_x.has_focus(): ui.pos_x.value = global_pos.x
	if not ui.pos_y.has_focus(): ui.pos_y.value = global_pos.y
	if not ui.pos_z.has_focus(): ui.pos_z.value = global_pos.z
	
	if not ui.rot_x.has_focus(): ui.rot_x.value = global_rot_deg.x
	if not ui.rot_y.has_focus(): ui.rot_y.value = global_rot_deg.y
	if not ui.rot_z.has_focus(): ui.rot_z.value = global_rot_deg.z
	
	var base_size = _get_item_base_size(_node)
	var current_size_in_meters = base_size * _node.scale
	
	if not ui.scale_x.has_focus(): ui.scale_x.value = current_size_in_meters.x
	if not ui.scale_y.has_focus(): ui.scale_y.value = current_size_in_meters.y
	if not ui.scale_z.has_focus(): ui.scale_z.value = current_size_in_meters.z
	
	_is_syncing_selection = false


# ------------------------------------------------------------
# Fine Actions
# ------------------------------------------------------------


# Hook per aggiornare selezione nella lista quando cambia selezione in editor (o quando viene deselezionato tutto)
func _on_editor_env_selection_changed(n: Node) -> void:
	if ui.components_list == null:
		return

	if n == null:
		# --- Evita deselezione se nascondiamo/blocchiamo l'oggetto ---
		var env := scene_ctrl.get_environment(editor_interface)
		if env != null:
			var target := inventory_ctrl._resolve_item_node_from_selection(env)
			if target != null:
				var is_vis = target.visible if "visible" in target else true
				var is_loc = target.has_meta("_edit_lock_") and target.get_meta("_edit_lock_")
				if not is_vis or is_loc:
					return
		
		_is_syncing_selection = true 
		inventory_ctrl.on_clear_selection()
		inventory_ctrl.on_item_selected(scene_ctrl.get_environment(editor_interface) != null)
		_sync_transform_fields_from_node(null)
		_is_syncing_selection = false
		
		_do_ui_refresh()
		return

	_sync_transform_fields_from_node(n)

	# Alziamo ENTRAMBI gli scudi prima di toccare la UI!
	_is_syncing_selection = true
	hooks.set_suppress_selection(true)

	var found = inventory_ctrl.select_by_instance_id(n.get_instance_id())

	if found:
		inventory_ctrl.on_item_selected(true) # Aggiorna preview e metadati interni
	else:
		inventory_ctrl.on_clear_selection()

	# Abbassiamo gli scudi
	hooks.set_suppress_selection(false)
	_is_syncing_selection = false
	
	_do_ui_refresh()

func _toast(msg: String, sec: float = 1.2) -> void:
	# Host: il dock stesso (Control) va bene
	if not is_inside_tree():
		return

	var d := AcceptDialog.new()
	d.title = ""
	d.dialog_text = msg
	d.exclusive = false
	d.unresizable = true

	# Nascondi bottoni (Godot 4.x)
	d.get_ok_button().visible = false

	add_child(d)
	d.popup_centered()

	# Auto close
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


func _load_pwd_for_selected_env() -> void:
	if ui == null or ui.env_list == null:
		return
	var selected_id := int(ui.env_list.get_selected_id())
	if selected_id <= 0:
		ui.save_pwd_edit.text = ""
		return
	ui.save_pwd_edit.text = scene_ctrl.load_env_password(editor_interface, selected_id)


func _mark_sync_completed() -> void:
	return

func _bind_env_import_progress(env: LivingEnvironment) -> void:
	if env == null: return
	var cb = Callable(self, "_on_env_import_progress")
	if not env.import_progress.is_connected(cb):
		env.import_progress.connect(cb)

func _on_env_import_progress(txt: String) -> void:
	if ui != null and ui.status_bar != null:
		ui.status_bar.text = txt

# ==============================================================================
# CALCOLO DIMENSIONI BASE IN METRI
# ==============================================================================
func _get_item_base_size(root: Node3D) -> Vector3:
	# 1. Proviamo a cercare la mesh specifica "Volume" o "volume"
	var aabb = LivingUtils.get_volume_aabb(root)

	# 2. Se non l'ha trovata (dimensione 0), facciamo fallback calcolando tutte le geometrie
	if aabb.size.is_zero_approx():
		aabb = LivingUtils.get_node_aabb(root)

	# 3. Se persino il fallback è a zero (es. è un contenitore vuoto), proteggiamo la matematica
	if aabb.size.is_zero_approx():
		return Vector3.ONE

	return aabb.size


# ------------------------------------------------------------
# UTILS: Nomi File vs Nomi Display
# ------------------------------------------------------------
func _to_pretty_name(file_name: String) -> String:
	if file_name == "":
		return "New Scene"
		
	var base = file_name.get_basename()
	
	# 1. Trasformiamo le "ancore di salvataggio" nei trattini eleganti per la UI
	base = base.replace("_-_", " - ")
	# 2. Sostituiamo gli altri underscore rimasti con semplici spazi
	base = base.replace("_", " ")
	
	# 3. Capitalize intelligente
	var words = base.split(" ")
	for i in range(words.size()):
		if words[i].length() > 0:
			# Se è l'ultimissima parola ed è formata da massimo 3 lettere, 
			# assumiamo che siano le iniziali del curatore!
			if i == words.size() - 1 and words[i].length() <= 3:
				words[i] = words[i].to_upper()
			else:
				words[i] = words[i].substr(0, 1).to_upper() + words[i].substr(1)
			
	return " ".join(words)

func _to_safe_filename(pretty_name: String) -> String:
	var regex = RegEx.new()
	# Teniamo lettere, numeri, spazi e TRATTINI
	regex.compile("[^a-zA-Z0-9_\\s-]")
	var sanitized = regex.sub(pretty_name, "", true)
	
	# Non usiamo to_snake_case() perché altrimenti ci cancellerebbe i trattini!
	var safe = sanitized.strip_edges().to_lower()
	
	# Traduciamo l'estetica in formato salvabile
	safe = safe.replace(" - ", "_-_")
	safe = safe.replace(" ", "_")
	
	# Eliminiamo eventuali doppi underscore generati per sbaglio
	while safe.find("__") != -1:
		safe = safe.replace("__", "_")
		
	if safe == "":
		safe = "new_scene"
	
	if not safe.ends_with(".tscn"):
		safe += ".tscn"
		
	return safe
