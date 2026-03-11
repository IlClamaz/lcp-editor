@tool
extends VBoxContainer

const TEMPLATE_ENV_SCENE := "res://addons/living_platform_plugin/scenes/living_environment_root.tscn"
const CURATED_SCENES_DIR := "res://curated_scenes"

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
	
	# Ascolta gli eventi del save dal Controller
	scene_ctrl.save_upload_finished.connect(_on_ctrl_upload_finished)
	scene_ctrl.save_fetch_finished.connect(_on_ctrl_fetch_finished)
	scene_ctrl.save_download_finished.connect(_on_ctrl_download_finished)
	
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
			# Visto che la rebuild fallisce al 99% per mancate risposte API
			ui.instantiate_progress_lbl.text = "Errore di rete"
			_do_ui_refresh() # aggiorna stato UI (abilita bottoni, mostra sanity warning, ecc)
			return
		await get_tree().process_frame

		env.instantiate_all_media() # avvia download media (se ci sono), quando finisce chiama callback su dl 
		_is_instantiating = false # Sblocco la UI
		_error_state = false
		ui.instantiate_progress_lbl.text = "Completato"
		_do_ui_refresh() # aggiorna stato UI 
	)

	inst.failed.connect(func(msg):
		_is_instantiating = false
		_error_state = true
		if "404" in str(msg) or "HTTP" in str(msg):
			ui.instantiate_progress_lbl.text = "Errore di rete"
		else:
			ui.instantiate_progress_lbl.text = "Errore"
		_do_ui_refresh() # aggiorna stato UI 
		push_warning(msg)
	)

	dl.progress_changed.connect(func(pct, done, total): 
		# Se il totale è 0 (tutto in cache o nessun media), evitiamo di scrivere "0% (0/0)"
		if total == 0:
			return
			
		# Se ci sono download in corso, mostriamo il progresso
		if done < total:
			ui.instantiate_progress_lbl.text = "%d%% (%d/%d)" % [pct, done, total]
		else:
			# Se ha finito di scaricare tutto, mostriamo Completato!
			ui.instantiate_progress_lbl.text = "Completato"
	)

	_on_fetch_envs_pressed()


func _process(_delta: float) -> void:
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	var has_scene := (sr != null)

	if sr != _last_scene_root or has_scene != _had_scene:  # controllo se scena cambiata (o da null a non null o viceversa)
		_last_scene_root = sr
		_had_scene = has_scene

		var env := scene_ctrl.get_environment(editor_interface)
		if env != null:
			if not _error_state:
				ui.instantiate_progress_lbl.text = "Completato"
			else:
				# Evita di sovrascrivere un "Errore di rete" già settato dai callback
				if ui.instantiate_progress_lbl.text not in ["Errore di rete", "Errore"]:
					ui.instantiate_progress_lbl.text = "Errore"
			
			# Cerchiamo a quale "indice" (posizione nella tendina) corrisponde l'ID dell'ambiente
			var option_index = ui.root_item_id.get_item_index(env.item_id)
			if option_index != -1:
				ui.root_item_id.select(option_index) # Selezioniamo quell'elemento
			else:
				# Se l'ID non è in lista, selezioniamo il placeholder (che sarà all'indice 0)
				if ui.root_item_id.item_count > 0:
					ui.root_item_id.select(0) 
		else:
			ui.instantiate_progress_lbl.text = ""
			# Se non c'è l'ambiente, torniamo al placeholder
			if ui.root_item_id.item_count > 0:
				ui.root_item_id.select(0)

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

	ui.fetch_envs_btn.pressed.connect(_on_fetch_envs_pressed)

	# Aggiorna i bottoni immediatamente quando l'utente sceglie un ambiente diverso dalla tendina
	ui.root_item_id.item_selected.connect(func(_idx: int):
		_do_ui_refresh()
	)

	# Instantiate
	ui.refresh_scene_btn.pressed.connect(_on_refresh_scene_pressed)

	# Salvataggio
	ui.save_upload_btn.pressed.connect(_on_save_upload_pressed)
	ui.save_fetch_btn.pressed.connect(_on_save_fetch_pressed)
	ui.save_download_btn.pressed.connect(_on_save_download_pressed)

	# --- EVENTI DEL TREE ---
	# Al click su un elemento della lista
	ui.item_list.item_selected.connect(func():
		# SE LO SCUDO E' ATTIVO, IGNORIAMO IL CLICK PER EVITARE IL FLICKERING
		if _is_syncing_selection:
			return

		var env := scene_ctrl.get_environment(editor_interface)
		inventory_ctrl.on_item_selected(env != null) # seleziono effettivamente e aggiorno preview

		_do_ui_refresh() # aggiorna stato bottoni
		
		if env != null:
			var node := inventory_ctrl._resolve_item_node_from_selection(env)
			if node != null:
				_sync_transform_fields_from_node(node) # aggiorna campi X/Z del nodo selezionato

				# Alziamo lo scudo mentre modifichiamo la selezione dell'editor
				_is_syncing_selection = true
				hooks.set_suppress_selection(true)
				var ed_sel := editor_interface.get_selection()
				
				# Deselezioniamo solo se non è già l'unico oggetto selezionato
				var current_sel = ed_sel.get_selected_nodes()
				if current_sel.size() != 1 or current_sel[0] != node:
					ed_sel.clear()
					ed_sel.add_node(node) # seleziono nodo in editor
					
				hooks.set_suppress_selection(false)
				_is_syncing_selection = false
	)
	
	# Quando vengono cliccati i pulsantini sulle righe (Occhio o Lucchetto)
	ui.item_list.button_clicked.connect(_on_tree_button_clicked)
	# --------------------------------------

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
	
	# Alziamo lo scudo mentre ricostruiamo la lista, altrimenti genererebbe finti click
	_is_syncing_selection = true 
	inventory_ctrl.set_snapshot(snap, env, editor_interface)
	_error_state = not inventory_ctrl.render_list()
	_is_syncing_selection = false
	
	hooks.bind_rename_watchers_from_snapshot(snap)

# ------------------------------------------------------------
# REFRESH. gestisce il refresh della UI (ma non della lista)
# ------------------------------------------------------------
func _do_ui_refresh() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	var is_environment := (env != null)

	if not is_environment or env.item_id <= 0:  
		inventory_ctrl.clear_ui()
		# Non serve forzare i disabled qui, lo facciamo in modo unificato in fondo!

	var selected_id = ui.root_item_id.get_selected_id() if ui.root_item_id != null else -1
	ui.refresh_scene_btn.disabled = _is_instantiating or selected_id <= 0

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
		
	# --- FIX LOGICA PULSANTI SANITY ---
	var has_player := false
	var has_lights := false
	var has_floor := false
	
	if is_environment:
		has_player = setup_ctrl.has_player(env)
		has_lights = setup_ctrl.has_lights(env)
		has_floor = setup_ctrl.has_floor(env)

	var env_loaded := is_environment and int(env.item_id) > 0 and not _error_state and not _is_instantiating
	ui.sanity_player.text = "Camera: %s" % ("✔" if has_player else "❌")
	ui.sanity_lights.text = "Luci: %s" % ("✔" if has_lights else "❌")
	ui.sanity_floor.text = "Pavimento: %s" % ("✔" if has_floor else "❌")
	ui.sanity_env.text = "Ambiente: %s" % ("✔" if env_loaded else "❌")

	# --- STATO BOTTONI SALVATAGGIO  ---
	ui.save_upload_btn.disabled = (not is_environment) or _is_instantiating
	ui.save_fetch_btn.disabled = (not is_environment) or _is_instantiating
	ui.save_download_btn.disabled = (not is_environment) or _is_instantiating

	# disabilita se la scena è vuota, OPPURE se l'oggetto c'è già!
	ui.ensure_player_btn.disabled = (not is_environment) or has_player
	ui.ensure_floor_btn.disabled = (not is_environment) or has_floor
	ui.ensure_lights_btn.disabled = (not is_environment) or has_lights

# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------

# Fetching Environments
func _on_fetch_envs_pressed() -> void:
	var base_url = ui.global_omeka_url.text.strip_edges()
	if base_url == "":
		push_error("Inserisci prima l'URL di OmekaS")
		return

	# --- FIX: AZZERAMENTO ERRORI IN UI ---
	# Svuotiamo eventuali stati d'errore quando si avvia un refresh della lista
	_error_state = false
	ui.instantiate_progress_lbl.text = ""
	_do_ui_refresh()

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
	ui.root_item_id.clear()
	ui.root_item_id.add_item("Scansione database in corso...", 0)
	ui.root_item_id.disabled = true
	
	# Usiamo il bottone per mostrare il progresso!
	ui.fetch_envs_btn.disabled = true
	ui.fetch_envs_btn.text = "🔄 Pag. 1..."

	# Avviamo la richiesta della prima pagina
	_request_page(_current_page)

# Funzione separata che scarica una pagina specifica
func _request_page(page: int) -> void:
	# Chiediamo 100 elementi alla volta
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

		# Se siamo alla prima pagina, svuotiamo la scritta iniziale "Scansione..."
		if _current_page == 1:
			ui.root_item_id.clear()
			# Aggiungiamo il placeholder con ID 0
			ui.root_item_id.add_item("Seleziona un ambiente o aggiorna la lista...", 0)
			# MAGIA: Lo rendiamo non cliccabile per l'utente!
			ui.root_item_id.set_item_disabled(0, true)

		# Filtriamo gli elementi
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
			
			# Abbiamo trovato un Ambiente!
			var id = int(item.get("o:id", 0))
			var title = item.get("o:title", "Senza Titolo")
			
			if id > 0:
				ui.root_item_id.add_item(str(id) + " - " + title, id)
				_valid_items_found += 1

		# Controlliamo se ci sono altre pagine
		if items_in_page == 100:
			_current_page += 1
			# Aggiorniamo il testo del bottone per dare feedback visivo
			ui.fetch_envs_btn.text = "🔄 Pag. " + str(_current_page) + "..."
			# Richiediamo la pagina successiva
			_request_page(_current_page)
			
		else:
			# --- FINE DELLA SCANSIONE TOTALE! ---
			if _valid_items_found == 0:
				# Invece di fare add_item, cambiamo il testo del placeholder all'indice 0
				ui.root_item_id.set_item_text(0, "Nessun Ambiente trovato")
			
			# Ripristiniamo la UI
			ui.root_item_id.disabled = false
			ui.fetch_envs_btn.disabled = false
			ui.fetch_envs_btn.text = "🔄 Aggiorna Lista"
			print("Scaricamento completato in %d pagine. Totale Ambienti: %d" % [_current_page, _valid_items_found])
			
			# --- AUTO-SELEZIONE DELLA SCENA ATTUALE ---
			# Lo eseguiamo solo quando la lista è definitiva e completa
			var env := scene_ctrl.get_environment(editor_interface)
			if env != null and env.item_id > 0:
				# Cerchiamo l'ID dell'ambiente aperto tra quelli appena scaricati
				for i in range(ui.root_item_id.get_item_count()):
					if ui.root_item_id.get_item_id(i) == env.item_id:
						ui.root_item_id.select(i)
						print("Curator Dock: Allineato automaticamente all'ambiente in scena (ID: %d)" % env.item_id)
						break
			_do_ui_refresh()
	else:
		_finish_with_error("Formato JSON inatteso")

# Helper per ripristinare la UI in caso di errori
func _finish_with_error(msg: String) -> void:
	ui.root_item_id.clear()
	ui.root_item_id.add_item(msg, 0)
	ui.root_item_id.disabled = false
	ui.fetch_envs_btn.disabled = false
	ui.fetch_envs_btn.text = "🔄 Aggiorna Lista"


# Carica da zero (se la scena è vuota) oppure Sincronizza (se la scena esiste)
func _on_refresh_scene_pressed() -> void:
	_is_instantiating = true
	ui.instantiate_progress_lbl.text = "Elaborazione..."
	_do_ui_refresh()
	
	var env := scene_ctrl.get_environment(editor_interface)
	var selected_id = int(ui.root_item_id.get_selected_id())

	# --- SICUREZZA ---
	if selected_id <= 0:
		# Svuotiamo l'errore perché se l'utente è tornato all'ID vuoto non deve essere bloccato in stato d'allarme
		_error_state = false
		_is_instantiating = false
		_do_ui_refresh()
		return
	# ------------------------------
	
	# CASO 1: SCENA VUOTA, RESETTATA o CAMBIO AMBIENTE -> Setup Iniziale
	if env == null or env.item_id == 0 or env.item_id != selected_id:
		
		# Se l'ambiente c'era già ma stiamo caricando un ID diverso, puliamo i vecchi figli
		if env != null:
			for c in env.get_children():
				if c is LivingItem:
					c.queue_free()
		
		# inst.run() si occuperà di configurare la radice col nuovo ID e avviare la scena
		inst.run(selected_id, ui.global_omeka_url.text)
		call_deferred("_start_dl_if_env_ready")
		
	# CASO 2: LA SCENA ESISTE ED È QUELLA GIUSTA -> Sincronizzazione Intelligente
	else:
		dl.reset()
		dl.start(env, self)
		
		env.build_finished.connect(func(success: bool):
			dl.mark_build_finished(success)
			_is_instantiating = false
			_error_state = not success
			
			if success:
				ui.instantiate_progress_lbl.text = "Completato"
			else:
				# --- FIX: ERRORE DI RETE (SINC. AMBIENTE) ---
				var err_msg = env.title if env.title != null else ""
				if "404" in err_msg or "HTTP" in err_msg:
					ui.instantiate_progress_lbl.text = "Errore di rete"
				else:
					ui.instantiate_progress_lbl.text = "Errore"
					
			_do_ui_refresh()
			_do_env_refresh()
		, CONNECT_ONE_SHOT)
		
		# Sincronizzazione non distruttiva
		env.fetch_omeka_info()

func _start_dl_if_env_ready() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		# se serve, riprova 1-2 frame (senza loop infinito)
		call_deferred("_start_dl_if_env_ready")
		return
	dl.reset()
	dl.start(env, self)


# ------------------------------------------------------------
# SAVING ACTIONS
# ------------------------------------------------------------

func _on_save_upload_pressed() -> void:
	ui.save_upload_btn.disabled = true
	ui.save_upload_btn.text = "⬆️ Caricamento in corso..."
	scene_ctrl.upload_scene(editor_interface, ui.save_pwd_edit.text)

func _on_ctrl_upload_finished(success: bool, msg: String) -> void:
	_toast(msg, 3.0)
	if not success:
		push_error("Curator Dock: " + msg)
	ui.save_upload_btn.text = "⬆️ Salva Scena sul Database"
	_do_ui_refresh()


func _on_save_fetch_pressed() -> void:
	ui.save_fetch_btn.disabled = true
	ui.save_fetch_btn.text = "⏳ Cerca..."
	ui.save_scene_list.clear()
	ui.save_scene_list.add_item("Ricerca in corso...", 0)
	ui.save_scene_list.set_item_disabled(0, true)
	scene_ctrl.fetch_remote_scenes(editor_interface, ui.save_pwd_edit.text)

func _on_ctrl_fetch_finished(success: bool, file_list: Array, msg: String) -> void:
	ui.save_fetch_btn.disabled = false
	ui.save_fetch_btn.text = "🔄 Cerca"
	ui.save_scene_list.clear()
	
	if not success:
		ui.save_scene_list.add_item("Errore di connessione", 0)
		ui.save_scene_list.set_item_disabled(0, true)
		_toast(msg, 3.5)
		return
		
	var count = 0
	for f in file_list:
		if typeof(f) == TYPE_DICTIONARY:
			var fname = str(f.get("name", ""))
			if fname.ends_with(".tscn"):
				ui.save_scene_list.add_item(fname, count)
				ui.save_scene_list.set_item_metadata(count, fname)
				count += 1
				
	if count == 0:
		ui.save_scene_list.add_item("Nessuna scena trovata", 0)
		ui.save_scene_list.set_item_disabled(0, true)
	else:
		_toast("Trovate %d scene sul db!" % count, 2.0)


func _on_save_download_pressed() -> void:
	var selected_idx = ui.save_scene_list.get_selected()
	if selected_idx < 0 or ui.save_scene_list.is_item_disabled(selected_idx):
		_toast("Seleziona una scena valida dalla tendina!", 2.0)
		return
		
	var remote_file_name = ui.save_scene_list.get_item_metadata(selected_idx)
	if typeof(remote_file_name) != TYPE_STRING or remote_file_name == "":
		return
		
	ui.save_download_btn.disabled = true
	ui.save_download_btn.text = "⬇️ Download in corso..."
	scene_ctrl.download_scene(editor_interface, remote_file_name, ui.save_pwd_edit.text)

func _on_ctrl_download_finished(success: bool, local_path: String, msg: String) -> void:
	if not success:
		_toast(msg, 3.0)
		ui.save_download_btn.text = "⬇️ Carica Scena Selezionata"
		_do_ui_refresh()
		return

	_toast("Scena scaricata! Sincronizzazione in corso...", 2.0)

	var fs = EditorInterface.get_resource_filesystem()
	
	# Aggiorniamo il file in modo nativo e sicuro
	fs.update_file(local_path)
	
	# Passiamo l'apertura a un processo separato
	call_deferred("_safe_open_scene", fs, local_path)
	
	ui.save_download_btn.text = "⬇️ Carica Scena Selezionata"
	_do_ui_refresh()


func _safe_open_scene(fs: EditorFileSystem, path: String) -> void:
	if not is_inside_tree(): return
	var clean_path = path.simplify_path()

	# Aspettiamo che l'editor abbia finito di registrare il file
	while fs.is_scanning():
		await get_tree().process_frame
		if not is_inside_tree(): return
		
	# Diamo un piccolo respiro al sistema
	await get_tree().create_timer(0.4).timeout
	if not is_inside_tree(): return
		
	# Scopriamo quale scena è attualmente aperta e puliamo anche il suo percorso
	var current_root = EditorInterface.get_edited_scene_root()
	var current_path = current_root.scene_file_path.simplify_path() if current_root != null else ""

	if current_path == clean_path:
		# La scena scaricata è quella aperta, ricarichiamola aggiornata
		EditorInterface.reload_scene_from_path(clean_path)
	else:
		# È una scena diversa, la apriamo normalmente in una nuova scheda.
		EditorInterface.open_scene_from_path(clean_path)

# ------------------------------------------------------------
# TREE (LIST) ACTIONS + VISIBILITY
# ------------------------------------------------------------
func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	var md = item.get_metadata(0)
	if typeof(md) != TYPE_DICTIONARY: return
	
	var env = scene_ctrl.get_environment(editor_interface)
	if env == null: return
	
	# Troviamo il nodo associato alla riga
	var target_node: Node = null
	var iid = int(md.get("instance_id", 0))
	if iid != 0:
		target_node = instance_from_id(iid) as Node
	if target_node == null:
		target_node = env.get_node_or_null(md.get("node_path", ""))
		
	if target_node == null: return
	
	# 1. Eseguiamo l'azione di visibilità o blocco
	if id == 0:
		_toggle_node_visibility(target_node)
	elif id == 1:
		_toggle_node_lock(target_node)
		
	# --- RISELEZIONIAMO SOLO SE L'OGGETTO È VISIBILE ---
	if target_node.visible:
		# 2. Selezioniamo automaticamente la riga su cui abbiamo cliccato
		item.select(0)
		
		# Diciamo a Godot di deselezionare e riselezionare 
		# il nodo all'istante per fargli ricalcolare la presenza del lucchetto
		_is_syncing_selection = true
		var ed_sel = editor_interface.get_selection()
		ed_sel.clear()
		ed_sel.add_node(target_node)
		_is_syncing_selection = false
		
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

	# --- DESELEZIONE SE L'OCCHIO È CHIUSO ---
	if new_vis == false:
		# 1. Togliamo la selezione dall'Editor 3D
		var ed_sel := editor_interface.get_selection()
		ed_sel.clear()
		
		# 2. Togliamo la selezione dalla nostra Lista e UI
		_is_syncing_selection = true
		if ui.item_list != null:
			ui.item_list.deselect_all()
		inventory_ctrl.on_clear_selection()
		_do_ui_refresh()
		_is_syncing_selection = false
		
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
		
	# Diciamo a Godot che abbiamo modificato la scena, così salverà lo stato del lucchetto
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
# ------------------------------------------------------------

# Place selected node at offset X/Z from current position
func _on_place_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return

	var target := inventory_ctrl._resolve_item_node_from_selection(env)
	if target == null:
		push_warning("Nodo non trovato (forse è stato eliminato).")
		_do_ui_refresh() # aggiorna stato UI
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
	if env == null: return

	var target := inventory_ctrl._resolve_item_node_from_selection(env)
	if target == null:
		push_warning("Nodo non trovato (forse è stato eliminato).")
		_do_ui_refresh() # aggiorna stato UI 
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

# Auto layout per elementi diretti di un'area
func _on_auto_layout_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return

	var n := inventory_ctrl._resolve_item_node_from_selection(env)
	if n == null or not (n is LivingArea):
		push_warning("Seleziona una LivingArea per eseguire l'Auto Layout.")
		return

	# Recuperiamo i valori direttamente dalla nostra UI!
	var spacing := float(ui.spacing_edit.value)
	var ccols := max(int(ui.cols_edit.value), 1)

	# Raccogli solo i LivingElement diretti
	var elems: Array[LivingElement] = []
	for c in n.get_children():
		if c is LivingElement:
			elems.append(c as LivingElement)

	if elems.is_empty():
		print("Nessun LivingElement trovato dentro l'area: %s" % n.name)
		return

	# Layout in griglia XZ, ancorata all'origine locale del parent
	# (0,0,0 è la "cella A1")
	if undo_redo != null:
		undo_redo.create_action("Auto layout LivingElements")
		for i in range(elems.size()):
			var le := elems[i] as Node3D
			
			var col = i % ccols
			var row = i / ccols # In Godot, int / int produce un int (divisione intera perfetta)
			
			var target := Vector3(col * spacing, le.position.y, row * spacing) # Preservo Y locale
			
			# Usiamo add_do_property invece dei metodi per aggiornare bene l'Editor
			undo_redo.add_do_property(le, "position", target)
			undo_redo.add_undo_property(le, "position", le.position)
			
		undo_redo.commit_action()
		print("Auto-layout eseguito su %d elementi (colonne=%d, spazio=%.2f)" % [elems.size(), ccols, spacing])
	else:
		for i in range(elems.size()):
			var le := elems[i] as Node3D
			var col = i % ccols
			var row = i / ccols
			le.position = Vector3(col * spacing, le.position.y, row * spacing)

	# Diciamo a Godot che abbiamo spostato roba e la scena va salvata
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


# Reset ambiente: svuota l'ambiente in modo SICURO per l'Editor
func _on_reset_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return

	# Alziamo gli scudi e puliamo le selezioni per evitare crash dell'Inspector
	_is_syncing_selection = true
	var ed_sel = editor_interface.get_selection()
	ed_sel.clear()
	inventory_ctrl.on_clear_selection()
	if ui.item_list != null:
		ui.item_list.deselect_all()

	# SVUOTIAMO LA SCENA invece di distruggere la radice!
	# Cancelliamo tutti gli oggetti 3D (figli) generati.
	for c in env.get_children():
		if c is LivingItem or c is LivingScene:
			c.get_parent().remove_child(c)
			c.queue_free()

	# Resettiamo l'ID così il sistema lo considera "vergine/vuoto"
	if "item_id" in env:
		env.item_id = 0

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()

	_is_syncing_selection = false
	_do_ui_refresh()
	_do_env_refresh()

# Setup buttons: assicurano che player/luci/pavimento esistano, con undo, e aggiornano UI 
func _on_ensure_player_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	setup_ctrl.ensure_player(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_do_ui_refresh() # aggiorna stato UI 

func _on_ensure_floor_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	setup_ctrl.ensure_floor(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_do_ui_refresh() # aggiorna stato UI 

func _on_ensure_lights_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null: return
	setup_ctrl.ensure_lights(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_do_ui_refresh() # aggiorna stato UI 

# ------------------------------------------------------------
# Fine Actions
# ------------------------------------------------------------

# Hook per aggiornare selezione nella lista quando cambia selezione in editor (o quando viene deselezionato tutto)
func _on_editor_env_selection_changed(n: Node) -> void:
	if ui.item_list == null:
		return

	if n == null:
		_is_syncing_selection = true
		inventory_ctrl.on_clear_selection()
		_do_ui_refresh()
		inventory_ctrl.on_item_selected(scene_ctrl.get_environment(editor_interface) != null)
		_sync_transform_fields_from_node(null) # ✅ reset
		_is_syncing_selection = false
		return

	_sync_transform_fields_from_node(n) # ✅ aggiorna campi X/Y/Z

	# Alziamo lo scudo per impedire all'albero di far esplodere la selezione dell'editor!
	_is_syncing_selection = true
	hooks.set_suppress_selection(true)
	inventory_ctrl._last_selected_instance_id = n.get_instance_id()
	inventory_ctrl._restore_selection_after_render() # Questo forza il Tree a evidenziare la riga giusta
	inventory_ctrl.on_item_selected(true)
	hooks.set_suppress_selection(false)
	_is_syncing_selection = false
		
	_do_ui_refresh() # aggiorna stato bottoni toggle + preview

func _toast(msg: String, sec: float = 1.2) -> void:
	# Host: il dock stesso (Control) va bene
	if not is_inside_tree():
		return

	var d := AcceptDialog.new()
	d.title = ""
	d.dialog_text = msg
	d.exclusive = true
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
