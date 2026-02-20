@tool
extends VBoxContainer

# ============================================================
# Curator Dock (UI + orchestrazione)
# ============================================================
# Questo è lo script principale del dock (pannellino) visibile in editor.
#
# Responsabilità principali:
# - Costruire l'interfaccia utente (UI) del dock
# - Abilitare/disabilitare controlli in base allo stato della scena (LivingScene presente?)
# - Delegare la logica a controller modulari:
#     - CuratorSceneController: scene-aware + editor settings + root element
#     - CuratorInventoryController: gestione lista "magazzino" (snapshot DB)
#     - CuratorLayoutController: griglia, reset, auto layout
#     - CuratorPipeline: orchestrazione fetch → instantiate → fetch+download
#
# Nota:
# - Questo file è un Control (VBoxContainer), quindi può usare theme e UI helpers.
# - Qui è il posto giusto per chiamare get_theme_icon() e gestire la grafica.
# ============================================================


# -------------------------
# Editor services
# -------------------------
# Iniettati dal plugin (EditorPlugin) quando crea il dock.
# - editor_interface serve per sapere qual è la scena attualmente editata.
# - undo_redo serve per registrare operazioni (Ctrl+Z / Ctrl+Y).
var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager


# -------------------------
# UI references (widgets creati in _build_ui)
# -------------------------
# Global defaults
var global_omeka_url: LineEdit

# Root LivingElement (per scena)
var root_item_id: SpinBox

# Actions
var refresh_list_btn: Button
var instantiate_scene_btn: Button
var reset_btn: Button
var auto_layout_btn: Button

# Grid placement
var cell_edit: LineEdit
var spacing_edit: SpinBox
var cols_edit: SpinBox
var place_btn: Button

# Inventory list + preview + status label
var item_list: ItemList
var preview: TextureRect
var scene_status: Label

# Scene Setup Buttons
var setup_status: Label
var ensure_all_btn: Button
var ensure_player_btn: Button
var ensure_floor_btn: Button
var ensure_lights_btn: Button

# -------------------------
# Controllers (logica modulare)
# -------------------------
# Nota: sono RefCounted helper; non sono nodi in scena.
var scene_ctrl := CuratorSceneController.new()
var pipeline := CuratorPipeline.new()
var layout_ctrl := CuratorLayoutController.new()
var inventory_ctrl := CuratorInventoryController.new(pipeline, scene_ctrl)
var setup_ctrl := CuratorSetupController.new()

# Cache dello state: usato per capire quando cambia la scena editata,
# e aggiornare la UI solo quando serve.
var _last_scene_root: Node = null
var _refresh_queued := false

func _ready() -> void:
	# Called when the dock enters the scene tree (in editor).
	#
	# Qui teniamo l'idea: passare un'icona di default al controller inventory,
	# perché lui è RefCounted e non può usare get_theme_icon().
	# Dimensione minima del dock (solo UX)
	custom_minimum_size = Vector2(360, 680)
	# Costruisce tutta la UI del pannello
	_build_ui()
	var icon := get_theme_icon("Node3D", "EditorIcons")
	inventory_ctrl.bind_ui(item_list, preview, place_btn, icon)
	# Carica Omeka URL globale (EditorSettings) nel campo globale
	global_omeka_url.text = scene_ctrl.load_global_default_url(editor_interface)
	scene_ctrl.apply_global_url_to_current_scene(editor_interface, undo_redo, global_omeka_url.text)
	
	# Aggiorna lo stato UI in base alla scena corrente
	_update_scene_dependent_ui(true)

	get_tree().node_added.connect(_on_tree_changed)
	get_tree().node_removed.connect(_on_tree_changed)


func _on_tree_changed(n: Node) -> void:
	var env = scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	_request_env_refresh()

	_update_setup_status(env)
	# aggiorna i marker della lista sulla base dei figli di env
	inventory_ctrl.set_snapshot(pipeline.scan_environment(env), editor_interface)

func _request_env_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_do_env_refresh")

func _do_env_refresh() -> void:
	_refresh_queued = false

	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	_update_setup_status(env)
	inventory_ctrl.set_snapshot(pipeline.scan_environment(env), editor_interface)

func _process(_delta: float) -> void:
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	if sr != _last_scene_root:
		_last_scene_root = sr
		_update_scene_dependent_ui(true)


func _build_ui() -> void:
	# Layout richiesto:
	# URL
	# ID
	# Istanzia ambiente
	# Sanity Check (1 riga orizzontale con tick)
	# --- separatore ---
	# Aggiorna lista
	# Help label
	# Lista || (thumbnail + toggle visibilità + offset X/Z)
	# --- separatore ---
	# (Pulsanti pericolosi) auto layout / distruggi tutto / assicura camera-floor-luci

	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# ------------------------------------------------------------
	# URL
	# ------------------------------------------------------------
	var url_title := Label.new()
	url_title.text = "URL"
	url_title.add_theme_font_size_override("font_size", 16)
	add_child(url_title)

	var url_row := HBoxContainer.new()
	add_child(url_row)

	var url_lbl := Label.new()
	url_lbl.text = "Omeka:"
	url_row.add_child(url_lbl)

	global_omeka_url = LineEdit.new()
	global_omeka_url.placeholder_text = "https://omekas.livingculture.it"
	global_omeka_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	global_omeka_url.text_changed.connect(func(t: String):
		scene_ctrl.save_global_default_url(editor_interface, t)
		scene_ctrl.apply_global_url_to_current_scene(editor_interface, undo_redo, t)
	)
	url_row.add_child(global_omeka_url)

	add_child(HSeparator.new())

	# ------------------------------------------------------------
	# ID + Istanzia ambiente
	# ------------------------------------------------------------
	var id_title := Label.new()
	id_title.text = "ID"
	id_title.add_theme_font_size_override("font_size", 16)
	add_child(id_title)

	var id_row := HBoxContainer.new()
	add_child(id_row)

	var id_lbl := Label.new()
	id_lbl.text = "Environment ID:"
	id_row.add_child(id_lbl)

	root_item_id = SpinBox.new()
	root_item_id.min_value = 0
	root_item_id.max_value = 999999999
	root_item_id.step = 1
	root_item_id.value = 0
	root_item_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(root_item_id)

	instantiate_scene_btn = Button.new()
	instantiate_scene_btn.text = "Istanzia ambiente"
	instantiate_scene_btn.pressed.connect(_on_instantiate_scene_from_db_pressed)
	add_child(instantiate_scene_btn)

	# ------------------------------------------------------------
	# Sanity Check (una riga orizzontale)
	# ------------------------------------------------------------
	var sanity_title := Label.new()
	sanity_title.text = "Sanity Check"
	sanity_title.add_theme_font_size_override("font_size", 16)
	add_child(sanity_title)

	# Usiamo 4 label "a pillola" aggiornate da _update_setup_status(env)
	# (qui le istanziamo; la logica di update resta nella tua _update_setup_status)
	var sanity_row := HBoxContainer.new()
	sanity_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(sanity_row)

	# Riutilizziamo setup_status come container di testo? No: creiamo 4 label.
	# Se nel tuo script già esiste setup_status come Label singola multi-linea,
	# puoi sostituirla con queste 4 label e aggiornare _update_setup_status.
	#
	# Per non rompere troppo, teniamo setup_status ma la trasformiamo in riga:
	# -> setup_status non serve più come label multilinea.
	# Se vuoi, puoi eliminare la vecchia setup_status altrove.
	var player_tick := Label.new()
	player_tick.name = "SanityPlayer"
	player_tick.text = "Player: …"
	sanity_row.add_child(player_tick)

	var lights_tick := Label.new()
	lights_tick.name = "SanityLights"
	lights_tick.text = "Luci: …"
	sanity_row.add_child(lights_tick)

	var floor_tick := Label.new()
	floor_tick.name = "SanityFloor"
	floor_tick.text = "Floor: …"
	sanity_row.add_child(floor_tick)

	var env_tick := Label.new()
	env_tick.name = "SanityEnv"
	env_tick.text = "Ambiente: …"
	sanity_row.add_child(env_tick)

	# Salviamo un riferimento comodo (opzionale). Se vuoi riusare setup_status, puntalo alla row.
	# setup_status = null # non più usato come label multilinea

	add_child(HSeparator.new())

	# ------------------------------------------------------------
	# Aggiorna lista + Help
	# ------------------------------------------------------------
	refresh_list_btn = Button.new()
	refresh_list_btn.text = "Aggiorna lista"
	refresh_list_btn.pressed.connect(_on_refresh_list_pressed)
	add_child(refresh_list_btn)

	var help_lbl := Label.new()
	help_lbl.text = "Help: Click seleziona / Doppio Click visualizza - nascondi"
	help_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help_lbl)

	# ------------------------------------------------------------
	# Lista || Preview + toggle + offset X/Z
	# ------------------------------------------------------------
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	item_list = ItemList.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.icon_mode = ItemList.ICON_MODE_LEFT
	item_list.fixed_icon_size = Vector2i(64, 64)
	item_list.select_mode = ItemList.SELECT_SINGLE

	item_list.item_selected.connect(func(index: int):
		inventory_ctrl.on_item_selected(index, scene_ctrl.get_environment(editor_interface) != null)
	)

	# Doppio click = toggle visibilità (mantieni il tuo handler _on_place_pressed o uno nuovo)
	item_list.item_activated.connect(func(index: int):
		if index >= 0:
			# nel tuo dock: qui dovresti fare toggle visibilità sul nodo selezionato
			# es: _toggle_visibility_for_index(index)
			_on_place_pressed()
	)

	split.add_child(item_list)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(230, 0)
	split.add_child(right)

	var prev_label := Label.new()
	prev_label.text = "Thumbnail"
	right.add_child(prev_label)

	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(200, 200)
	right.add_child(preview)

	right.add_child(HSeparator.new())

	# "POSIZIONA IN SCENA" -> ora è toggle visibilità (come hai detto)
	place_btn = Button.new()
	place_btn.text = "Visualizza / Nascondi"
	place_btn.disabled = true
	place_btn.pressed.connect(_on_place_pressed)
	right.add_child(place_btn)

	# Offset X/Z (distanza orizzontale e verticale dall'origine sul piano XZ)
	var off_title := Label.new()
	off_title.text = "Offset dall'origine (X / Z)"
	right.add_child(off_title)

	var off_row := HBoxContainer.new()
	right.add_child(off_row)

	var x_lbl := Label.new()
	x_lbl.text = "X:"
	off_row.add_child(x_lbl)

	var offset_x := SpinBox.new()
	offset_x.name = "OffsetX"
	offset_x.min_value = -9999
	offset_x.max_value = 9999
	offset_x.step = 0.1
	offset_x.value = 0.0
	offset_x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	off_row.add_child(offset_x)

	var z_lbl := Label.new()
	z_lbl.text = "Z:"
	off_row.add_child(z_lbl)

	var offset_z := SpinBox.new()
	offset_z.name = "OffsetZ"
	offset_z.min_value = -9999
	offset_z.max_value = 9999
	offset_z.step = 0.1
	offset_z.value = 0.0
	offset_z.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	off_row.add_child(offset_z)

	add_child(HSeparator.new())

	# ------------------------------------------------------------
	# Pulsanti "pericolosi"
	# ------------------------------------------------------------
	var danger_title := Label.new()
	danger_title.text = "⚠ Pulsanti pericolosi"
	danger_title.add_theme_font_size_override("font_size", 16)
	add_child(danger_title)

	auto_layout_btn = Button.new()
	auto_layout_btn.text = "Auto Layout (figli diretti selezionato)"
	auto_layout_btn.pressed.connect(_on_auto_layout_pressed)
	add_child(auto_layout_btn)

	reset_btn = Button.new()
	reset_btn.text = "Distruggi tutto (Svuota scena)"
	reset_btn.pressed.connect(_on_reset_pressed)
	add_child(reset_btn)

	var ensure_row := HBoxContainer.new()
	add_child(ensure_row)

	ensure_player_btn = Button.new()
	ensure_player_btn.text = "Assicura Camera"
	ensure_player_btn.pressed.connect(_on_ensure_player_pressed)
	ensure_row.add_child(ensure_player_btn)

	ensure_floor_btn = Button.new()
	ensure_floor_btn.text = "Assicura Pavimento"
	ensure_floor_btn.pressed.connect(_on_ensure_floor_pressed)
	ensure_row.add_child(ensure_floor_btn)

	ensure_lights_btn = Button.new()
	ensure_lights_btn.text = "Assicura Luci"
	ensure_lights_btn.pressed.connect(_on_ensure_lights_pressed)
	ensure_row.add_child(ensure_lights_btn)

func _update_scene_dependent_ui(_force: bool = false) -> void:
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	var env = scene_ctrl.get_environment(editor_interface)
	
	var has_scene := sr != null
	var is_environment := env != null

	# Status label
	if has_scene and not is_environment:
		scene_status.text += "\n⚠ Root non è LivingEnvironment. Il dock richiede LivingEnvironment come root."


	root_item_id.editable = is_environment

	refresh_list_btn.disabled = not is_environment
	instantiate_scene_btn.disabled = not is_environment
	reset_btn.disabled = not is_environment
	auto_layout_btn.disabled = not is_environment

	item_list.mouse_filter = Control.MOUSE_FILTER_STOP if is_environment else Control.MOUSE_FILTER_IGNORE
	item_list.modulate.a = 1.0 if is_environment else 0.45

	place_btn.disabled = (not is_environment) or item_list.get_selected_items().is_empty()

	# --- Scene Setup UI ---
	if not is_environment:
		if ensure_all_btn: ensure_all_btn.disabled = true
		if ensure_player_btn: ensure_player_btn.disabled = true
		if ensure_floor_btn: ensure_floor_btn.disabled = true
		if ensure_lights_btn: ensure_lights_btn.disabled = true
		if setup_status: setup_status.text = "Apri una LivingScene per vedere lo stato del setup."

		inventory_ctrl.clear_ui()
		return

	# Se siamo qui, è LivingScene: abilita i controlli setup
	if ensure_all_btn: ensure_all_btn.disabled = false
	# I singoli NON vanno forzati a true: li gestisce _update_setup_status
	_update_setup_status(env)

func _get_first_root_item_id(ls: LivingScene) -> int:
	for c in ls.get_children():
		if c is LivingElement:
			return int((c as LivingElement).item_id)
	return 0

func _on_ensure_all_pressed() -> void:
	var env = scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	setup_ctrl.ensure_all(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_update_setup_status(env)

func _on_ensure_player_pressed() -> void:
	var env = scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	setup_ctrl.ensure_player(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_update_setup_status(env)

func _on_ensure_floor_pressed() -> void:
	var env = scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	setup_ctrl.ensure_floor(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_update_setup_status(env)

func _on_ensure_lights_pressed() -> void:
	var env = scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	setup_ctrl.ensure_lights(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_update_setup_status(env)

func _update_setup_status(env: LivingEnvironment) -> void:
	if setup_status == null:
		return

	var p := setup_ctrl.has_player(env)
	var f := setup_ctrl.has_floor(env)
	var l := setup_ctrl.has_lights(env)

	setup_status.text = "Player/Camera: %s\nFloor: %s\nLuci: %s" % [
		("✅ Presente" if p else "⚠ Mancante"),
		("✅ Presente" if f else "⚠ Mancante"),
		("✅ Presente" if l else "⚠ Mancanti")
	]

	# UX: disabilita i bottoni singoli se già presente
	if ensure_player_btn: ensure_player_btn.disabled = p
	if ensure_floor_btn: ensure_floor_btn.disabled = f
	if ensure_lights_btn: ensure_lights_btn.disabled = l
	# "Assicura tutto" resta sempre cliccabile (è idempotente)


func _on_refresh_list_pressed() -> void:
	# Ora la lista deve riflettere Environment -> (Areas + Elements)
	# Passiamo l'ID dell'environment (che hai nello spinbox).
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	var desired_env_id := int(root_item_id.value)
	if desired_env_id <= 0:
		push_warning("Imposta un LivingEnvironment ID valido.")
		return

	# Assicura che l'env abbia l'ID giusto (così fetch usa quello)
	if int(env.item_id) != desired_env_id:
		# meglio allineare prima
		if undo_redo != null:
			undo_redo.create_action("Set LivingEnvironment item_id")
			undo_redo.add_do_property(env, "item_id", desired_env_id)
			undo_redo.add_undo_property(env, "item_id", env.item_id)
			undo_redo.commit_action()
		else:
			env.item_id = desired_env_id

	# Nuova semantica: refresh lista "dal DB" a partire dall'environment id
	inventory_ctrl.refresh_from_scene_only(editor_interface)
	# In più: una volta popolata entries, la UI deve marcare cosa è già in scena
	# inventory_ctrl.render_list(env)


func _on_instantiate_scene_from_db_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)

	# 1) Se non c'è root (scena vuota), apri template con LivingEnvironment root
	if env == null:
		var sr := scene_ctrl.edited_scene_root(editor_interface)
		if sr == null:
			# scena vuota -> apri template
			editor_interface.open_scene_from_path("res://addons/living_platform_plugin/scenes/living_environment_root.tscn")
			# il root sarà disponibile dal frame successivo
			call_deferred("_continue_instantiate_after_scene_open")
			return

		# se esiste root ma non è LivingEnvironment
		push_warning("La scena corrente non ha LivingEnvironment come root.")
		return

	# se siamo qui env è ok
	_continue_instantiate(env)


func _continue_instantiate_after_scene_open() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		push_warning("Impossibile trovare LivingEnvironment dopo apertura template.")
		return
	_continue_instantiate(env)


func _continue_instantiate(env: LivingEnvironment) -> void:
	# 2) Assicura tutto
	setup_ctrl.ensure_all(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))

	# 3) Applica URL globale
	env.OMEKA_BASE_URL = global_omeka_url.text

	# 4) item_id + rebuild
	var desired_env_id := int(root_item_id.value)
	if desired_env_id <= 0:
		push_warning("Imposta un LivingEnvironment ID valido.")
		return

	if int(env.item_id) != desired_env_id:
		if undo_redo != null:
			undo_redo.create_action("Set LivingEnvironment item_id")
			undo_redo.add_do_property(env, "item_id", desired_env_id)
			undo_redo.add_undo_property(env, "item_id", env.item_id)
			undo_redo.commit_action()
		else:
			env.item_id = desired_env_id

	env.rebuild_environment()


func _on_reset_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	# Reset: qui dipende cosa intendi.
	# Versione base: rimuove TUTTI i LivingItem figli dell'environment (areas+elements).
	# Se vuoi solo elementi e non aree, dimmelo e lo restringiamo.
	layout_ctrl.reset_environment_children(env, undo_redo)

	# UI refresh
	# aggiorna lo stato interno del controller inventory
	inventory_ctrl.set_snapshot(pipeline.scan_environment(env), editor_interface)

func _on_auto_layout_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	# Auto-layout: nel nuovo modello ha senso applicarlo ai LivingElement (non alle aree)
	layout_ctrl.auto_layout_environment_elements(
		env,
		float(spacing_edit.value),
		int(cols_edit.value),
		undo_redo
	)

func _on_place_pressed() -> void:
	var sel := item_list.get_selected_items()
	if sel.is_empty():
		return
	_place_selected_as_child(sel[0], cell_edit.text)


func _place_selected_as_child(index: int, cell: String) -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	# TOGGLE VISIBILITY
