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
const TEMPLATE_ENV_SCENE := "res://addons/living_platform_plugin/scenes/living_environment_root.tscn"
const CURATED_SCENES_DIR := "res://curated_scenes"

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
var offset_x: SpinBox
var offset_z: SpinBox
var place_btn: Button

# Inventory list + preview + status label
var item_list: ItemList
var preview: TextureRect
var scene_status: Label

# Scene Setup Buttons
var player_tick = Label
var lights_tick: Label
var floor_tick: Label
var env_tick: Label
var ensure_player_btn: Button
var ensure_floor_btn: Button
var ensure_lights_btn: Button
var spacing_edit: SpinBox
var cols_edit: SpinBox

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
var _had_scene: bool = false


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
	_bind_undo_redo_refresh()

func _bind_undo_redo_refresh() -> void:
	if undo_redo == null:
		return

	# Godot 4.x: il segnale più comune è version_changed
	if undo_redo.has_signal("version_changed"):
		if not undo_redo.version_changed.is_connected(_on_undo_redo_version_changed):
			undo_redo.version_changed.connect(_on_undo_redo_version_changed)
		return

	# fallback: alcune versioni espongono "history_changed"
	if undo_redo.has_signal("history_changed"):
		if not undo_redo.history_changed.is_connected(_on_undo_redo_version_changed):
			undo_redo.history_changed.connect(_on_undo_redo_version_changed)
		return

func _on_undo_redo_version_changed() -> void:
	# Debounce: evita spam quando trascini slider ecc.
	_request_env_refresh()

func _on_tree_changed(n: Node) -> void:

	# 1) interessa solo se c'è un env aperto
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	# 2) ignora tutto ciò che NON è LivingItem (così tagli via nodi editor/gizmo/HTTPRequest ecc.)
	if not (n is LivingItem):
		return

	# 4) aggiorna solo se il nodo è env o sta sotto env
	if n != env and not env.is_ancestor_of(n):
		return

	_request_env_refresh()

func _request_env_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_do_env_refresh")

func _do_env_refresh() -> void:
	print("Performing deferred environment refresh at: ", Time.get_ticks_msec())
	_refresh_queued = false

	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	_update_setup_status(env)
	inventory_ctrl.set_snapshot(pipeline.scan_environment(env), editor_interface)
		# ✅ ascolta rinomini (titoli che arrivano async)
	_bind_rename_watchers(env)

func _bind_rename_watchers(env: LivingEnvironment) -> void:
	for row in pipeline.scan_environment(env):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var iid := int(row.get("instance_id", 0))
		if iid == 0:
			continue
		var obj := instance_from_id(iid)
		if obj == null or not (obj is Node):
			continue
		var n := obj as Node
		if not (n is LivingItem):
			continue

		# connetti una sola volta
		if not n.renamed.is_connected(_on_any_livingitem_renamed):
			n.renamed.connect(_on_any_livingitem_renamed)

func _on_any_livingitem_renamed() -> void:
	_request_env_refresh()

func _process(_delta: float) -> void:
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	var has_scene := (sr != null)

	# Transizioni importanti:
	# - root object cambia
	# - oppure passiamo da "avevo una scena" -> "nessuna scena" (sr null)
	if sr != _last_scene_root or has_scene != _had_scene:
		_last_scene_root = sr
		_had_scene = has_scene
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
	player_tick = Label.new()
	player_tick.name = "SanityPlayer"
	player_tick.text = "Player: …"
	sanity_row.add_child(player_tick)

	lights_tick = Label.new()
	lights_tick.name = "SanityLights"
	lights_tick.text = "Luci: …"
	sanity_row.add_child(lights_tick)

	floor_tick = Label.new()
	floor_tick.name = "SanityFloor"
	floor_tick.text = "Floor: …"
	sanity_row.add_child(floor_tick)

	env_tick = Label.new()
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
		var env := scene_ctrl.get_environment(editor_interface)
		var has_env := (env != null)

		inventory_ctrl.on_item_selected(index, has_env)

		if not has_env:
			return

		# risolvi nodo dal metadata (instance_id / node_path)
		var n := _resolve_item_node_from_list_index(index, env)
		if n != null:
			_select_node_in_editor(n)
	)

	# Doppio click = toggle visibilità
	item_list.item_activated.connect(func(index: int):
		if index >= 0:
			# nel tuo dock: qui dovresti fare toggle visibilità sul nodo selezionato
			# es: _toggle_visibility_for_index(index)
			_on_show_hide_for_index(index)
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
	place_btn.text = "Posiziona rispetto all'origine"
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

	offset_x = SpinBox.new()
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

	offset_z = SpinBox.new()
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

	var auto_row := HBoxContainer.new()
	add_child(auto_row)

	auto_layout_btn = Button.new()
	auto_layout_btn.text = "Auto Layout"
	auto_layout_btn.pressed.connect(_on_auto_layout_pressed)
	auto_row.add_child(auto_layout_btn)

	var sp_lbl := Label.new()
	sp_lbl.text = "Spacing:"
	auto_row.add_child(sp_lbl)

	spacing_edit = SpinBox.new()
	spacing_edit.min_value = 0.1
	spacing_edit.max_value = 100.0
	spacing_edit.step = 0.1
	spacing_edit.value = 2.0
	spacing_edit.custom_minimum_size = Vector2(70, 0)
	auto_row.add_child(spacing_edit)

	var cols_lbl := Label.new()
	cols_lbl.text = "Cols:"
	auto_row.add_child(cols_lbl)

	cols_edit = SpinBox.new()
	cols_edit.min_value = 1
	cols_edit.max_value = 50
	cols_edit.step = 1
	cols_edit.value = 6
	cols_edit.custom_minimum_size = Vector2(55, 0)
	auto_row.add_child(cols_edit)


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
	var env := scene_ctrl.get_environment(editor_interface)

	var has_scene := sr != null
	var is_environment := env != null
	var is_empty_scene := (sr == null) # <-- scena nuova/vuota

	instantiate_scene_btn.disabled = not (is_environment or is_empty_scene)

	# Gli altri controlli possono restare scena-dipendenti
	refresh_list_btn.disabled = not is_environment
	reset_btn.disabled = not is_environment
	auto_layout_btn.disabled = not is_environment

	item_list.mouse_filter = Control.MOUSE_FILTER_STOP if is_environment else Control.MOUSE_FILTER_IGNORE
	item_list.modulate.a = 1.0 if is_environment else 0.45
	place_btn.disabled = (not is_environment) or item_list.get_selected_items().is_empty()

	if not is_environment:
		_update_setup_status(env)
		inventory_ctrl.clear_ui()
		# setup buttons (se vuoi) disabilitati quando non c'è env
		if ensure_player_btn: ensure_player_btn.disabled = true
		if ensure_floor_btn: ensure_floor_btn.disabled = true
		if ensure_lights_btn: ensure_lights_btn.disabled = true
		return

	# se env c'è:
	_update_setup_status(env)

func _get_first_root_item_id(ls: LivingScene) -> int:
	for c in ls.get_children():
		if c is LivingElement:
			return int((c as LivingElement).item_id)
	return 0

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
	# Aggiorna i 4 indicatori orizzontali del sanity check:
	# - Player presente
	# - Luci presenti
	# - Floor presente
	# - Ambiente presente / caricato

	if player_tick == null or lights_tick == null or floor_tick == null or env_tick == null:
		# UI non ancora pronta o nomi cambiati
		return

	# Se env manca, settiamo tutti a "mancante"
	if env == null:
		player_tick.text = "Player: ❌"
		lights_tick.text = "Luci: ❌"
		floor_tick.text = "Floor: ❌"
		env_tick.text = "Ambiente: ❌"
		if ensure_player_btn: ensure_player_btn.disabled = true
		if ensure_floor_btn: ensure_floor_btn.disabled = true
		if ensure_lights_btn: ensure_lights_btn.disabled = true
		return

	# Check presenza oggetti scena
	var has_player := setup_ctrl.has_player(env)
	var has_floor := setup_ctrl.has_floor(env)
	var has_lights := setup_ctrl.has_lights(env)

	# Ambiente: presente + "caricato"
	# "presente" = env esiste
	# "caricato" = item_id valido (oppure ha figli LivingItem dopo rebuild)
	var env_present := true
	var env_loaded := int(env.item_id) > 0 and pipeline.scan_environment(env).size() > 1

	# Aggiorna pillole con tick/avvisi
	player_tick.text = "Player: %s" % ("✅" if has_player else "❌ (call devs)" )
	lights_tick.text = "Luci: %s" % ("✅" if has_lights else "❌")
	floor_tick.text = "Floor: %s" % ("✅" if has_floor else "❌")
	env_tick.text = "Ambiente: %s" % ("✅" if (env_present and env_loaded) else "⚠")

	# UX: disabilita i bottoni singoli se già presente
	if ensure_player_btn: ensure_player_btn.disabled = has_player
	if ensure_floor_btn: ensure_floor_btn.disabled = has_floor
	if ensure_lights_btn: ensure_lights_btn.disabled = has_lights


func _on_refresh_list_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	env.refresh_all_living_elements()


func _on_instantiate_scene_from_db_pressed() -> void:
	# Se non siamo già in una LivingEnvironment, creiamo una copia del template
	# e apriamo quella scena (così il template non viene mai modificato).
	var env := scene_ctrl.get_environment(editor_interface)

	if env == null:
		var ok := _create_copy_from_template_and_open()
		if not ok:
			return
		# Dopo open_scene_from_path il root è disponibile dal frame successivo
		call_deferred("_continue_instantiate_after_open")
		return

	# Già su LivingEnvironment: procedi
	_continue_instantiate_on_env(env)


func _continue_instantiate_after_open() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		push_warning("Non riesco a trovare LivingEnvironment dopo l'apertura della copia template.")
		return
	_continue_instantiate_on_env(env)


func _continue_instantiate_on_env(env: LivingEnvironment) -> void:
	# 1) Assicura URL globale su env
	scene_ctrl.apply_global_url_to_current_scene(editor_interface, undo_redo, global_omeka_url.text)

	# 2) Assicura tutto (player/camera, floor, luci…)
	setup_ctrl.ensure_all(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))

	# 3) Allinea item_id environment
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

	# 4) Ricostruisci dal DB
	env.rebuild_environment()
	
func _create_copy_from_template_and_open() -> bool:
	if editor_interface == null:
		return false

	# 1) carica template
	var tpl: PackedScene = load(TEMPLATE_ENV_SCENE)
	if tpl == null:
		push_warning("Template non trovato: %s" % TEMPLATE_ENV_SCENE)
		return false

	# 2) istanzia root
	var root := tpl.instantiate()
	if root == null or not (root is LivingEnvironment):
		push_warning("Il template non ha LivingEnvironment come root.")
		return false

	# 3) crea cartella output se manca
	if not DirAccess.dir_exists_absolute(CURATED_SCENES_DIR):
		var derr := DirAccess.make_dir_recursive_absolute(CURATED_SCENES_DIR)
		if derr != OK:
			push_warning("Impossibile creare cartella: %s" % CURATED_SCENES_DIR)
			return false

	# 4) nome file unico (include item_id se già impostato nello spinbox)
	var desired_env_id := int(root_item_id.value)
	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var fname := "env_%s_%s.tscn" % [str(desired_env_id if desired_env_id > 0 else "new"), ts]
	var new_path := "%s/%s" % [CURATED_SCENES_DIR, fname]

	# 5) pack + save
	var ps := PackedScene.new()
	var perr := ps.pack(root)
	if perr != OK:
		push_warning("PackedScene.pack fallito: %s" % perr)
		return false

	var serr := ResourceSaver.save(ps, new_path)
	if serr != OK:
		push_warning("ResourceSaver.save fallito: %s" % serr)
		return false

	# 6) apri la copia
	editor_interface.open_scene_from_path(new_path)
	return true


func _on_reset_pressed() -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return
	# rimuove TUTTI i LivingItem figli dell'environment (areas+elements).
	layout_ctrl.reset_environment_children(env, undo_redo)

	# UI refresh, aggiorna lo stato interno del controller inventory
	inventory_ctrl.set_snapshot(pipeline.scan_environment(env), editor_interface)

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
		float(spacing_edit.value),
		int(cols_edit.value),
		undo_redo
	)

	_request_env_refresh()

func _get_selected_layout_parent(env: LivingEnvironment) -> Node:
	# Se in lista è selezionata una LivingArea -> layout su quella area
	# Se è selezionato un LivingElement -> layout sul SUO parent (area o env)
	# Se non c'è selezione -> layout sull'env
	if item_list == null:
		return env

	var sel := item_list.get_selected_items()
	if sel.is_empty():
		return env

	var idx := int(sel[0])
	var n := _resolve_item_node_from_list_index(idx, env) # usa il tuo resolver (instance_id/node_path)
	if n == null:
		return env

	if n is LivingArea:
		return n
	if n is LivingEnvironment:
		return n
	if n is LivingElement:
		# se selezioni un element, auto-layout dei fratelli (figli diretti del parent)
		return n.get_parent()

	return env

func _on_place_pressed() -> void:
	var sel := item_list.get_selected_items()
	if sel.is_empty():
		return

	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	var index := int(sel[0])

	var target := _resolve_item_node_from_list_index(index, env)
	if target == null:
		push_warning("Nodo non trovato (forse è stato eliminato).")
		_request_env_refresh()
		return

	if not (target is Node3D):
		push_warning("Il nodo selezionato non è un Node3D, non posso spostarlo.")
		return

	var n3d := target as Node3D
	var old_pos := n3d.global_position
	var new_pos := Vector3(offset_x.value, old_pos.y, offset_z.value) # manteniamo Y attuale

	if undo_redo != null:
		undo_redo.create_action("Move node to X/Z offset")
		undo_redo.add_do_method(n3d, "set_global_position", new_pos)
		undo_redo.add_undo_method(n3d, "set_global_position", old_pos)
		undo_redo.commit_action()
	else:
		n3d.global_position = new_pos

	_request_env_refresh()


func _on_show_hide_for_index(index: int) -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	var target := _resolve_item_node_from_list_index(index, env)
	if target == null:
		push_warning("Nodo non trovato (forse è stato eliminato).")
		_request_env_refresh()
		return

	# Determina visibilità corrente + toggle
	var current_vis := true
	if target is Node3D:
		current_vis = (target as Node3D).visible
	elif target is CanvasItem:
		current_vis = (target as CanvasItem).visible
	elif target.has_method("is_visible_in_tree"):
		current_vis = bool(target.call("is_visible_in_tree"))
	elif target.has_method("visible"):
		current_vis = bool(target.get("visible"))

	var new_vis := not current_vis

	if undo_redo != null:
		undo_redo.create_action("Toggle visibility")

		if target is Node3D:
			undo_redo.add_do_property(target, "visible", new_vis)
			undo_redo.add_undo_property(target, "visible", current_vis)
		elif target is CanvasItem:
			undo_redo.add_do_property(target, "visible", new_vis)
			undo_redo.add_undo_property(target, "visible", current_vis)
		elif target.has_method("set_visible"):
			undo_redo.add_do_method(target, "set_visible", new_vis)
			undo_redo.add_undo_method(target, "set_visible", current_vis)
		else:
			# fallback generico
			undo_redo.add_do_property(target, "visible", new_vis)
			undo_redo.add_undo_property(target, "visible", current_vis)

		undo_redo.commit_action()
	else:
		if target is Node3D:
			(target as Node3D).visible = new_vis
		elif target is CanvasItem:
			(target as CanvasItem).visible = new_vis
		elif target.has_method("set_visible"):
			target.call("set_visible", new_vis)
		elif target.has_method("set"):
			target.set("visible", new_vis)

	_request_env_refresh()

func _resolve_item_node_from_list_index(index: int, env: LivingEnvironment) -> Node:
	if item_list == null:
		return null
	if index < 0 or index >= item_list.item_count:
		return null

	var md := item_list.get_item_metadata(index)
	if typeof(md) != TYPE_DICTIONARY:
		return null
	print("Metadata for index %d: %s" % [index, str(md)])
	var iid := int(md.get("instance_id", 0))
	if iid != 0:
		var obj := instance_from_id(iid)
		if obj != null and obj is Node:
			return obj as Node

	var p := str(md.get("node_path", ""))
	if p != "":
		# p può essere assoluto o relativo; di solito è tipo "LivingEnvironment/Area/Elem"
		# Se è relativo all'env, risolviamo rispetto a env
		var n := env.get_node_or_null(p)
		if n != null:
			return n
		# fallback: prova come NodePath assoluto
		n = get_tree().root.get_node_or_null(p)
		if n != null:
			return n

	return null

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

	# opzionale: porta focus alla SceneTree dock (non sempre necessario)
	# editor_interface.get_base_control().grab_focus()
