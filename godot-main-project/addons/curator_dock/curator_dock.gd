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

# Per-scena (LivingScene)
var scene_omeka_url: LineEdit
var apply_scene_url_btn: Button

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


# -------------------------
# Controllers (logica modulare)
# -------------------------
# Nota: sono RefCounted helper; non sono nodi in scena.
var scene_ctrl := CuratorSceneController.new()
var pipeline := CuratorPipeline.new()
var layout_ctrl := CuratorLayoutController.new()
var inventory_ctrl := CuratorInventoryController.new(pipeline, scene_ctrl)

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
	# Aggiorna lo stato UI in base alla scena corrente
	_update_scene_dependent_ui(true)


func _process(_delta: float) -> void:
	# Poll leggero: controlla se il root della scena editata è cambiato.
	# Se cambia (es. hai aperto un'altra scena), aggiorna abilitazioni e campi.
	var sr := scene_ctrl.edited_scene_root(editor_interface)
	if sr != _last_scene_root:
		_last_scene_root = sr
		_update_scene_dependent_ui(true)


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
	global_title.text = "Globale"
	global_title.add_theme_font_size_override("font_size", 16)
	add_child(global_title)

	var g_row := HBoxContainer.new()
	add_child(g_row)

	var g_lbl := Label.new()
	g_lbl.text = "Omeka URL (default):"
	g_row.add_child(g_lbl)

	global_omeka_url = LineEdit.new()
	global_omeka_url.placeholder_text = "https://omekas.livingculture.it"
	global_omeka_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Quando cambia il testo, salviamo il default globale in EditorSettings.
	# Nota: questo è "globale" per l'editor, non per la scena.
	global_omeka_url.text_changed.connect(func(t: String):
		scene_ctrl.save_global_default_url(editor_interface, t)
	)
	g_row.add_child(global_omeka_url)

	add_child(HSeparator.new())

	# ===== SCENE =====
	var scene_title := Label.new()
	scene_title.text = "Scena corrente (LivingScene)"
	scene_title.add_theme_font_size_override("font_size", 16)
	add_child(scene_title)

	# Label di stato: mostra se c'è scena aperta e se è LivingScene
	scene_status = Label.new()
	scene_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(scene_status)

	var s_row := HBoxContainer.new()
	add_child(s_row)

	var s_lbl := Label.new()
	s_lbl.text = "Omeka URL (scena):"
	s_row.add_child(s_lbl)

	scene_omeka_url = LineEdit.new()
	scene_omeka_url.placeholder_text = "deriva da LivingScene.OMEKA_BASE_URL"
	scene_omeka_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s_row.add_child(scene_omeka_url)

	# Applica = scrive scene_omeka_url dentro LivingScene.OMEKA_BASE_URL
	apply_scene_url_btn = Button.new()
	apply_scene_url_btn.text = "Applica"
	apply_scene_url_btn.pressed.connect(_on_apply_scene_url_pressed)
	s_row.add_child(apply_scene_url_btn)

	add_child(HSeparator.new())

	# ===== ROOT =====
	var root_title := Label.new()
	root_title.text = "Radice DB (LivingElement root)"
	root_title.add_theme_font_size_override("font_size", 16)
	add_child(root_title)

	var r_row := HBoxContainer.new()
	add_child(r_row)

	var r_lbl := Label.new()
	r_lbl.text = "Root item_id:"
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
	place_btn.text = "Piazza come figlio del root"
	place_btn.disabled = true
	place_btn.pressed.connect(_on_place_pressed)
	right.add_child(place_btn)


func _update_scene_dependent_ui(_force: bool = false) -> void:
	# Aggiorna la UI in base allo stato della scena corrente.
	# - Se non c'è scena o non è LivingScene: disabilita quasi tutto.
	# - Se è LivingScene: abilita controlli e sincronizza campi (es. item_id root).
	#
	# Nota: non aggiorna automaticamente la lista DB: quella si aggiorna solo col pulsante.

	var sr := scene_ctrl.edited_scene_root(editor_interface)
	var ls := scene_ctrl.get_living_scene(editor_interface)

	var has_scene := sr != null
	var is_living_scene := ls != null

	# Status label
	scene_status.text = ("Scena aperta: %s" % sr.name) if has_scene else "Nessuna scena aperta."
	if has_scene and not is_living_scene:
		scene_status.text += "\n⚠ Root non è LivingScene. Il dock richiede LivingScene come root."

	# Campo URL scena: mostra valore se LivingScene, altrimenti vuoto
	scene_omeka_url.text = ls.OMEKA_BASE_URL if is_living_scene else ""

	# Enable/disable controlli scena-dipendenti
	scene_omeka_url.editable = is_living_scene
	apply_scene_url_btn.disabled = not is_living_scene
	root_item_id.editable = is_living_scene
	ensure_root_btn.disabled = not is_living_scene

	refresh_list_btn.disabled = not is_living_scene
	instantiate_scene_btn.disabled = not is_living_scene
	reset_btn.disabled = not is_living_scene
	auto_layout_btn.disabled = not is_living_scene

	# ItemList: se non è living scene, ignoriamo input e "sbiadiamo"
	item_list.mouse_filter = Control.MOUSE_FILTER_STOP if is_living_scene else Control.MOUSE_FILTER_IGNORE
	item_list.modulate.a = 1.0 if is_living_scene else 0.45

	# Place button: attivo solo se living scene + una selezione
	place_btn.disabled = (not is_living_scene) or item_list.get_selected_items().is_empty()

	# Se siamo in LivingScene, proviamo a leggere item_id della root già presente
	if is_living_scene:
		var root_el := scene_ctrl.find_root_living_element(ls)
		if root_el != null:
			# Sincronizza UI dal nodo scena (source of truth: scena)
			root_item_id.value = root_el.item_id
	else:
		# Se non abbiamo LivingScene, puliamo la UI "magazzino"
		inventory_ctrl.clear_ui()


func _on_apply_scene_url_pressed() -> void:
	# Applica l'URL scena nel nodo LivingScene.
	# Se il campo è vuoto, il controller usa il default globale come fallback.
	scene_ctrl.apply_scene_url(editor_interface, undo_redo, scene_omeka_url.text, global_omeka_url.text)


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
		scene_omeka_url.text = ls.OMEKA_BASE_URL

	# Crea root se manca, oppure aggiorna item_id se esiste già
	scene_ctrl.ensure_root_living_element(editor_interface, undo_redo, int(root_item_id.value))


func _on_refresh_list_pressed() -> void:
	# Aggiorna la lista magazzino dal DB.
	# Importante: non modifica la scena (usa un root temporaneo sotto il cofano).
	inventory_ctrl.refresh_list_from_root_components(editor_interface, int(root_item_id.value))


func _on_instantiate_scene_from_db_pressed() -> void:
	# Istanzia/aggiorna la scena dal DB:
	# - garantisce URL scena
	# - garantisce root LivingElement
	# - avvia pipeline sul root reale (fetch → instantiate → fetch+download sui figli)
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return

	# URL fallback: se vuoto, usa default globale
	if str(ls.OMEKA_BASE_URL).strip_edges() == "":
		scene_ctrl.apply_scene_url(editor_interface, undo_redo, global_omeka_url.text, global_omeka_url.text)
		scene_omeka_url.text = ls.OMEKA_BASE_URL

	var root_el := scene_ctrl.ensure_root_living_element(editor_interface, undo_redo, int(root_item_id.value))
	if root_el == null:
		return

	# Pipeline sul root reale: crea/aggiorna la struttura "canon" dal DB
	pipeline.hydrate_living_element_tree(root_el)


func _on_reset_pressed() -> void:
	# Reset layout: elimina i figli LivingElement del root reale.
	# Attenzione: è un reset forte (tutti i figli LivingElement).
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return
	var root_el := scene_ctrl.find_root_living_element(ls)
	layout_ctrl.reset_root_children(root_el, undo_redo)


func _on_auto_layout_pressed() -> void:
	# Disposizione automatica dei figli LivingElement del root reale in griglia.
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		return
	var root_el := scene_ctrl.find_root_living_element(ls)
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

	var root_el := scene_ctrl.find_root_living_element(ls)
	if root_el == null:
		push_warning("Root LivingElement non presente. Premi 'Assicura root LivingElement'.")
		return

	# Verifica indice selezionato
	if index < 0 or index >= inventory_ctrl.entries.size():
		return

	# Entry selezionata (Dictionary con: name, item_id)
	var entry = inventory_ctrl.entries[index]
	var new_id := int(entry.item_id)

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

	# Avvia pipeline sul nodo appena creato:
	# fetch → instantiate components → fetch+download sui figli
	pipeline.hydrate_living_element_tree(new_el)
