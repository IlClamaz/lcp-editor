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
var ensure_root_btn: Button

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


func _on_tree_changed(_n: Node) -> void:
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return

	# 1) aggiorna setup status (già lo fai)
	_update_setup_status(ls)

	# 2) aggiorna i marker ✅/➕ della lista, se la lista è già popolata
	var desired_id := int(root_item_id.value)
	if desired_id <= 0:
		return

	var root_el := scene_ctrl.find_root_living_element_by_item_id(ls, desired_id)
	# root_el può essere null (root non ancora creato), in tal caso render comunque
	# così tutti risultano ➕
	inventory_ctrl.render_list(root_el)


func _process(_delta: float) -> void:
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	if sr != _last_scene_root:
		_last_scene_root = sr
		_update_scene_dependent_ui(true)

		# ✅ FIX: se la nuova scena è una LivingScene, sincronizza subito l'URL
		scene_ctrl.apply_global_url_to_current_scene(
			editor_interface,
			undo_redo,
			global_omeka_url.text
		)


func _build_ui() -> void:
	# Costruisce l'interfaccia grafica.
	# Questo dock è diviso in:
	# - Globale (url default)
	# - Scena corrente (url scena)
	# - Root DB (root item_id + ensure root)
	# - Azioni (refresh list, instantiate, reset, auto layout)
	# - Lista magazzino + preview + parametri griglia e pulsante "Place"

	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# ===== GLOBAL =====
	var global_title := Label.new()
	global_title.text = "Impostazioni Globali"
	global_title.add_theme_font_size_override("font_size", 16)
	add_child(global_title)

	var g_row := HBoxContainer.new()
	add_child(g_row)

	var g_lbl := Label.new()
	g_lbl.text = "Omeka URL:"
	g_row.add_child(g_lbl)

	global_omeka_url = LineEdit.new()
	global_omeka_url.placeholder_text = "https://omekas.livingculture.it"
	global_omeka_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Quando cambia il testo, salviamo il default globale in EditorSettings.
	# Nota: questo è "globale" per l'editor, non per la scena.
	global_omeka_url.text_changed.connect(func(t: String):
		# 1) salva in EditorSettings (persistente “globale”)
		scene_ctrl.save_global_default_url(editor_interface, t)
		# 2) applica alla LivingScene corrente (se presente)
		scene_ctrl.apply_global_url_to_current_scene(editor_interface, undo_redo, t)
	)

	g_row.add_child(global_omeka_url)

	add_child(HSeparator.new())

	# ===== SCENE =====
	var scene_title := Label.new()
	scene_title.text = "Scena corrente (dev'essere LivingScene)"
	scene_title.add_theme_font_size_override("font_size", 16)
	add_child(scene_title)

	# Label di stato: mostra se c'è scena aperta e se è LivingScene
	scene_status = Label.new()
	scene_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(scene_status)


	add_child(HSeparator.new())

	# ===== SCENE SETUP =====
	var setup_title := Label.new()
	setup_title.text = "Scene Setup"
	setup_title.add_theme_font_size_override("font_size", 16)
	add_child(setup_title)

	setup_status = Label.new()
	setup_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(setup_status)

	var setup_row0 := HBoxContainer.new()
	add_child(setup_row0)

	ensure_all_btn = Button.new()
	ensure_all_btn.text = "Assicura tutto"
	ensure_all_btn.pressed.connect(_on_ensure_all_pressed)
	setup_row0.add_child(ensure_all_btn)

	var setup_row1 := HBoxContainer.new()
	add_child(setup_row1)

	ensure_player_btn = Button.new()
	ensure_player_btn.text = "Assicura Player/Camera"
	ensure_player_btn.pressed.connect(_on_ensure_player_pressed)
	setup_row1.add_child(ensure_player_btn)

	ensure_floor_btn = Button.new()
	ensure_floor_btn.text = "Assicura Floor"
	ensure_floor_btn.pressed.connect(_on_ensure_floor_pressed)
	setup_row1.add_child(ensure_floor_btn)

	ensure_lights_btn = Button.new()
	ensure_lights_btn.text = "Assicura Luci"
	ensure_lights_btn.pressed.connect(_on_ensure_lights_pressed)
	setup_row1.add_child(ensure_lights_btn)

	add_child(HSeparator.new())


	# ===== ROOT =====
	var root_title := Label.new()
	root_title.text = "ID (dal DB) del LivingEnvironment"
	root_title.add_theme_font_size_override("font_size", 16)
	add_child(root_title)

	var r_row := HBoxContainer.new()
	add_child(r_row)

	var r_lbl := Label.new()
	r_lbl.text = "LivingEnvironment ID:"
	r_row.add_child(r_lbl)

	# item_id dell'oggetto Omeka "root": da questo id derivano i components.
	root_item_id = SpinBox.new()
	root_item_id.min_value = 0
	root_item_id.max_value = 999999999
	root_item_id.step = 1
	root_item_id.value = 0
	root_item_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_row.add_child(root_item_id)

	# Crea (se manca) la root LivingElement sotto LivingScene, e imposta item_id.
	ensure_root_btn = Button.new()
	ensure_root_btn.text = "Assicura root LivingElement"
	ensure_root_btn.pressed.connect(_on_ensure_root_pressed)
	add_child(ensure_root_btn)

	add_child(HSeparator.new())

	# ===== ACTIONS =====
	var a_row := HBoxContainer.new()
	add_child(a_row)

	# Refresh magazzino: snapshot DB (non cambia scena)
	refresh_list_btn = Button.new()
	refresh_list_btn.text = "Aggiorna lista (DB)"
	refresh_list_btn.pressed.connect(_on_refresh_list_pressed)
	a_row.add_child(refresh_list_btn)

	# Istanzia scena: lavora sul root reale in scena
	instantiate_scene_btn = Button.new()
	instantiate_scene_btn.text = "Istanzia scena da DB"
	instantiate_scene_btn.pressed.connect(_on_instantiate_scene_from_db_pressed)
	a_row.add_child(instantiate_scene_btn)

	# Reset layout: elimina figli LivingElement del root reale
	reset_btn = Button.new()
	reset_btn.text = "Reset / svuota layout"
	reset_btn.pressed.connect(_on_reset_pressed)
	a_row.add_child(reset_btn)

	# Auto layout: posiziona figli LivingElement in griglia
	auto_layout_btn = Button.new()
	auto_layout_btn.text = "Auto layout"
	auto_layout_btn.pressed.connect(_on_auto_layout_pressed)
	a_row.add_child(auto_layout_btn)

	# ===== LIST + PREVIEW + GRID =====
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	# Lista magazzino
	item_list = ItemList.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.icon_mode = ItemList.ICON_MODE_LEFT
	item_list.fixed_icon_size = Vector2i(64, 64)
	item_list.select_mode = ItemList.SELECT_SINGLE

	# Quando seleziono un item:
	# - delego al controller inventory, che abilita/disabilita "Place" e aggiorna preview
	item_list.item_selected.connect(func(index: int):
		inventory_ctrl.on_item_selected(index, scene_ctrl.get_living_scene(editor_interface) != null)
	)

	# Doppio click / enter: piazza immediatamente
	item_list.item_activated.connect(func(index: int):
		if index >= 0:
			_place_selected_as_child(index, cell_edit.text)
	)
	split.add_child(item_list)

	# Colonna destra: preview + griglia
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(230, 0)
	split.add_child(right)

	var prev_label := Label.new()
	prev_label.text = "Preview:"
	right.add_child(prev_label)

	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(200, 200)
	right.add_child(preview)

	right.add_child(HSeparator.new())

	var grid_title := Label.new()
	grid_title.text = "Piazzamento in griglia"
	right.add_child(grid_title)

	# Campo cella (A1, A4, ecc.)
	var cell_row := HBoxContainer.new()
	right.add_child(cell_row)

	var cell_lbl := Label.new()
	cell_lbl.text = "Cella:"
	cell_row.add_child(cell_lbl)

	cell_edit = LineEdit.new()
	cell_edit.text = "A1"
	cell_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell_row.add_child(cell_edit)

	# Spacing griglia
	var spacing_row := HBoxContainer.new()
	right.add_child(spacing_row)

	var sp_lbl := Label.new()
	sp_lbl.text = "Spacing:"
	spacing_row.add_child(sp_lbl)

	spacing_edit = SpinBox.new()
	spacing_edit.min_value = 0.1
	spacing_edit.max_value = 100.0
	spacing_edit.step = 0.1
	spacing_edit.value = 2.0
	spacing_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacing_row.add_child(spacing_edit)

	# Numero colonne per auto-layout
	var cols_row := HBoxContainer.new()
	right.add_child(cols_row)

	var cols_lbl := Label.new()
	cols_lbl.text = "Cols (auto):"
	cols_row.add_child(cols_lbl)

	cols_edit = SpinBox.new()
	cols_edit.min_value = 1
	cols_edit.max_value = 50
	cols_edit.step = 1
	cols_edit.value = 6
	cols_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols_row.add_child(cols_edit)

	# Pulsante piazza: crea un nuovo LivingElement come figlio del root
	place_btn = Button.new()
	place_btn.text = "Piazza in scena"
	place_btn.disabled = true
	place_btn.pressed.connect(_on_place_pressed)
	right.add_child(place_btn)

func _update_scene_dependent_ui(_force: bool = false) -> void:
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	var ls := scene_ctrl.get_living_scene(editor_interface)

	var has_scene := sr != null
	var is_living_scene := ls != null

	# Status label
	scene_status.text = ("Scena aperta: %s" % sr.name) if has_scene else "Nessuna scena aperta."
	if has_scene and not is_living_scene:
		scene_status.text += "\n⚠ Root non è LivingScene. Il dock richiede LivingScene come root."


	root_item_id.editable = is_living_scene
	ensure_root_btn.disabled = not is_living_scene

	refresh_list_btn.disabled = not is_living_scene
	instantiate_scene_btn.disabled = not is_living_scene
	reset_btn.disabled = not is_living_scene
	auto_layout_btn.disabled = not is_living_scene

	item_list.mouse_filter = Control.MOUSE_FILTER_STOP if is_living_scene else Control.MOUSE_FILTER_IGNORE
	item_list.modulate.a = 1.0 if is_living_scene else 0.45

	place_btn.disabled = (not is_living_scene) or item_list.get_selected_items().is_empty()

	# --- Scene Setup UI ---
	if not is_living_scene:
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
	_update_setup_status(ls)

	# -------------------------
	# MULTI-ROOT behavior
	# -------------------------
	# root_item_id è la "selezione" del root che vuoi gestire.
	# Non lo sovrascriviamo automaticamente.
	#
	# Solo se è ancora 0, proviamo a settare un default (primo root presente).
	if int(root_item_id.value) <= 0:
		var first_root_id := _get_first_root_item_id(ls)
		if first_root_id > 0:
			root_item_id.value = first_root_id
	# Se invece è > 0 ma non esiste, lo lasciamo così:
	# l'utente può premere "Assicura root" per crearlo come sibling.

func _get_first_root_item_id(ls: LivingScene) -> int:
	for c in ls.get_children():
		if c is LivingElement:
			return int((c as LivingElement).item_id)
	return 0

func _on_ensure_all_pressed() -> void:
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return
	setup_ctrl.ensure_all(ls, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_update_setup_status(ls)

func _on_ensure_player_pressed() -> void:
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return
	setup_ctrl.ensure_player(ls, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_update_setup_status(ls)

func _on_ensure_floor_pressed() -> void:
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return
	setup_ctrl.ensure_floor(ls, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_update_setup_status(ls)

func _on_ensure_lights_pressed() -> void:
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return
	setup_ctrl.ensure_lights(ls, undo_redo, scene_ctrl.edited_scene_root(editor_interface))
	_update_setup_status(ls)

func _update_setup_status(ls: LivingScene) -> void:
	if setup_status == null:
		return

	var p := setup_ctrl.has_player(ls)
	var f := setup_ctrl.has_floor(ls)
	var l := setup_ctrl.has_lights(ls)

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


func _on_ensure_root_pressed() -> void:
	# Crea o aggiorna la root LivingElement in scena.
	#
	# Prima assicuriamo che la LivingScene abbia un OMEKA_BASE_URL valido:
	# - se vuoto, lo impostiamo al default globale (così i fetch funzionano).
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return
	if str(ls.OMEKA_BASE_URL).strip_edges() == "":
		scene_ctrl.apply_scene_url(editor_interface, undo_redo, global_omeka_url.text, global_omeka_url.text)

	# Crea root se manca, oppure aggiorna item_id se esiste già
	scene_ctrl.ensure_root_living_element(editor_interface, undo_redo, int(root_item_id.value))


func _on_refresh_list_pressed() -> void:
	# Aggiorna la lista magazzino dal DB.
	# Importante: non modifica la scena (usa un root temporaneo sotto il cofano).
	inventory_ctrl.refresh_list_from_root_components(editor_interface, int(root_item_id.value))


func _on_instantiate_scene_from_db_pressed() -> void:
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return

	var desired_id := int(root_item_id.value)
	var root_el := scene_ctrl.ensure_root_living_element(editor_interface, undo_redo, desired_id)
	if root_el == null:
		return

	pipeline.hydrate_root_and_ensure_components(root_el, editor_interface)
	inventory_ctrl.render_list(root_el) # aggiorna UI (icona + place button)


func _on_reset_pressed() -> void:
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return

	var desired_id := int(root_item_id.value)
	var root_el := scene_ctrl.find_root_living_element_by_item_id(ls, desired_id)
	if root_el == null:
		push_warning("Root %d non presente. Premi 'Assicura root LivingElement'." % desired_id)
		return

	layout_ctrl.reset_root_children(root_el, undo_redo)



func _on_auto_layout_pressed() -> void:
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return

	var desired_id := int(root_item_id.value)
	var root_el := scene_ctrl.find_root_living_element_by_item_id(ls, desired_id)
	if root_el == null:
		push_warning("Root %d non presente. Premi 'Assicura root LivingElement'." % desired_id)
		return

	layout_ctrl.auto_layout(root_el, float(spacing_edit.value), int(cols_edit.value), undo_redo)



func _on_place_pressed() -> void:
	# Pulsante "Place": piazza l'elemento selezionato in lista nella cella indicata.
	var sel := item_list.get_selected_items()
	if sel.is_empty():
		return
	_place_selected_as_child(sel[0], cell_edit.text)


func _place_selected_as_child(index: int, cell: String) -> void:
	# Crea un nuovo LivingElement (duplicati ammessi) come figlio del root LivingElement reale,
	# posizionandolo in griglia.
	#
	# Passaggi:
	# - verifica LivingScene e root LivingElement
	# - legge l'item_id dall'entry selezionata nella lista
	# - crea un nuovo LivingElement con lo stesso item_id
	# - calcola posizione con cell_to_local_position
	# - aggiunge il nodo con Undo/Redo (se disponibile)
	# - avvia pipeline sul nuovo nodo (fetch → instantiate → fetch+download)

	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return

	var root_el := scene_ctrl.find_root_living_element_by_item_id(ls, int(root_item_id.value))
	if root_el == null:
		push_warning("Root LivingElement non presente.")
		return

	if index < 0 or index >= inventory_ctrl.entries.size():
		return

	var entry = inventory_ctrl.entries[index]
	var new_id := int(entry.item_id)

	# ✅ no duplicates
	if inventory_ctrl.prevent_duplicates and scene_ctrl.has_direct_child_living_element_with_item_id(root_el, new_id):
		push_warning("Item #%d è già in scena sotto questo root." % new_id)
		inventory_ctrl.render_list(root_el) # aggiorna status
		return

	# Crea nuovo LivingElement (non usiamo istanze dalla lista: la lista è solo DB snapshot)
	var new_el := LivingElement.new()
	new_el.item_id = new_id
	new_el.name = "LivingElement-%d" % new_id

	# Posizionamento locale sul root (piano XZ, Y=0)
	new_el.position = layout_ctrl.cell_to_local_position(cell, float(spacing_edit.value))

	if undo_redo != null:
		# Undo/Redo: aggiunta nodo + owner
		undo_redo.create_action("Place LivingElement #%d in %s" % [new_id, cell])
		undo_redo.add_do_method(root_el, "add_child", new_el)
		undo_redo.add_undo_method(root_el, "remove_child", new_el)

		# owner: necessario per renderlo salvabile/visibile nel SceneTree
		undo_redo.add_do_method(new_el, "set_owner", scene_ctrl.edited_scene_root(editor_interface))
		undo_redo.commit_action()
	else:
		# Fallback senza Undo/Redo
		root_el.add_child(new_el)
		new_el.owner = scene_ctrl.edited_scene_root(editor_interface)

	inventory_ctrl.render_list(root_el)
	# Avvia pipeline sul nodo appena creato:
	# fetch → instantiate components → fetch+download sui figli
	pipeline.hydrate_root_and_ensure_components(new_el, editor_interface)
