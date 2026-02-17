@tool
extends RefCounted
class_name CuratorInventoryController

# ============================================================
# CuratorInventoryController
# ============================================================
# Responsabilità:
# - Gestire la "lista magazzino" nel dock (ItemList + preview + place button)
# - La lista è uno SNAPSHOT del DB, non riflette ciò che è in scena.
# - Per ottenere la lista dei componenti dal DB, oggi usa un LivingElement
#   temporaneo (InventoryTempRoot) e la pipeline di fetch/instantiate.
#
# Nota:
# Questo controller è RefCounted (non è un Control), quindi non può usare
# funzioni di UI theme (es. get_theme_icon). Per questo l'icona viene
# passata dal dock.
# ============================================================


# Array di entry (modello dati della lista).
# Ogni entry è un Dictionary, tipicamente:
#   { "name": String, "item_id": int }
# Questo è lo "snapshot" del DB (deduplicato).
var entries: Array = []


# -------------------------
# Riferimenti UI (passati dal Dock)
# -------------------------
# ItemList: lista visibile nel dock con nome + icona.
var item_list: ItemList
# Preview: box immagine (per ora usa un'icona placeholder).
var preview: TextureRect
# Button: pulsante "Piazza" (abilitato/disabilitato in base allo stato).
var place_btn: Button


# -------------------------
# Dipendenze (servizi / controller)
# -------------------------
# Pipeline: incapsula l'orchestrazione fetch → instantiate → fetch+download.
var pipeline: CuratorPipeline
# Scene controller: trova LivingScene, root LivingElement, ecc.
var scene_ctrl: CuratorSceneController


# -------------------------
# Icona di default per la lista
# -------------------------
# Essendo RefCounted, non posso chiamare get_theme_icon().
# L’icona viene passata dal dock (che è un Control).
var default_icon: Texture2D


func _init(_pipeline: CuratorPipeline, _scene_ctrl: CuratorSceneController) -> void:
	# Costruttore: riceve dipendenze necessarie per lavorare.
	# - pipeline per "idratare" nodi LivingElement
	# - scene_ctrl per ottenere LivingScene dalla EditorInterface
	pipeline = _pipeline
	scene_ctrl = _scene_ctrl


func bind_ui(_item_list: ItemList, _preview: TextureRect, _place_btn: Button, _default_icon: Texture2D) -> void:
	# Collega i nodi UI al controller.
	# Questa funzione viene chiamata una volta dal dock nel _ready().
	item_list = _item_list
	preview = _preview
	place_btn = _place_btn
	default_icon = _default_icon


func clear_ui() -> void:
	# Pulisce l'UI della lista.
	# Utile quando non c'è una scena valida, oppure quando si cambia scena.
	if item_list:
		item_list.clear()
	if preview:
		preview.texture = null
	if place_btn:
		place_btn.disabled = true


func refresh_list_from_root_components(editor_interface: EditorInterface, root_item_id: int) -> void:
	var ls := scene_ctrl.get_living_scene(editor_interface)
	if ls == null:
		push_warning("Serve una scena con LivingScene come root.")
		return
	if root_item_id <= 0:
		push_warning("Imposta un root item_id valido.")
		return

	ls.refresh_all_living_elements()

	var temp_root := LivingElement.new()
	temp_root.name = "InventoryTempRoot"
	temp_root.item_id = root_item_id
	ls.add_child(temp_root)
	temp_root.owner = null

	# IMPORTANT: per la lista basta fetch del root + instantiate_components
	temp_root.fetch_json_success.connect(func():
		temp_root.instantiate_components()
		_build_entries_from_temp_root_and_fetch_titles(temp_root)
	, CONNECT_ONE_SHOT)

	temp_root.fetch_json_error.connect(func(reason: String):
		push_warning("Refresh lista fallito: %s" % reason)
		if is_instance_valid(temp_root): temp_root.queue_free()
	, CONNECT_ONE_SHOT)

	temp_root.fetch_omeka_info()

func _build_entries_from_temp_root_and_fetch_titles(temp_root: LivingElement) -> void:
	# Deduplica e crea entries con placeholder
	var seen := {}
	entries.clear()

	# id -> indice entries
	var id_to_entry_index: Dictionary = {}
	# id -> indice item_list (uguale all'ordine di inserimento)
	var id_to_itemlist_index: Dictionary = {}

	# 1) Costruisci entries (placeholder) dai figli creati da instantiate_components()
	for c in temp_root.get_children():
		if c is LivingElement:
			var le := c as LivingElement
			var id := int(le.item_id)
			if seen.has(id):
				continue
			seen[id] = true

			entries.append({ "name": "Item %d" % id, "item_id": id })
			id_to_entry_index[id] = entries.size() - 1

	# 2) Render iniziale con placeholder
	render_list()

	# Se non abbiamo UI o entries vuote, possiamo pulire subito
	if item_list == null or entries.is_empty():
		temp_root.queue_free()
		return

	# 3) Crea una mappa id -> indice in ItemList (coincide con ordine di render_list)
	#    (Dato che render_list inserisce items nello stesso ordine di entries)
	for i in range(entries.size()):
		var id := int(entries[i].item_id)
		id_to_itemlist_index[id] = i

	# 4) Lancia fetch sui figli per ottenere title, e aspetta che finiscano TUTTI
	var pending := entries.size()

	# helper per chiudere e liberare temp_root quando abbiamo finito
	var _done := func():
		pending -= 1
		if pending <= 0:
			# Tutti i titoli hanno risposto (success o error) → ora possiamo distruggere
			if is_instance_valid(temp_root):
				temp_root.queue_free()

	# 5) Per ogni figlio (deduplicato): fetch titolo
	for c in temp_root.get_children():
		if not (c is LivingElement):
			continue

		var le := c as LivingElement
		var id := int(le.item_id)

		# Saltiamo i duplicati (in temp_root possono esserci più nodi con stesso item_id)
		if not id_to_entry_index.has(id):
			continue

		# Connetti segnali UNA VOLTA
		le.fetch_json_success.connect(func():
			var title := str(le.title).strip_edges()
			if title != "":
				# aggiorna entries
				var e_idx := int(id_to_entry_index[id])
				entries[e_idx].name = title

				# aggiorna UI senza rifare render_list()
				if item_list != null and id_to_itemlist_index.has(id):
					var ui_idx := int(id_to_itemlist_index[id])
					item_list.set_item_text(ui_idx, "%s  (#%d)" % [title, id])
			_done.call()
		, CONNECT_ONE_SHOT)

		le.fetch_json_error.connect(func(reason: String):
			push_warning("Fetch title fallito (#%d): %s" % [id, reason])
			_done.call()
		, CONNECT_ONE_SHOT)

		# Avvia fetch (solo titolo; niente download)
		le.fetch_omeka_info()



func _build_entries_from_temp_root(temp_root: LivingElement) -> void:
	# Costruisce entries[] leggendo i figli LivingElement creati dal temp_root.
	# Deduplica: un solo elemento per item_id (uno per "tipo" di componente).

	var seen := {} # dizionario usato come set: item_id -> true
	entries.clear()

	for c in temp_root.get_children():
		if c is LivingElement:
			var le := c as LivingElement
			var id := int(le.item_id)

			# Deduplica per item_id
			if seen.has(id):
				continue
			seen[id] = true

			# Etichetta user-friendly: usa title se presente, altrimenti fallback "Item <id>"
			var label := le.title if str(le.title).strip_edges() != "" else ("Item %d" % id)

			# Salviamo solo i dati minimi necessari per la UI
			entries.append({ "name": label, "item_id": id })

	# Disegna la lista a UI
	render_list()

	# Distrugge il root temporaneo (non ci serve più)
	temp_root.queue_free()


func render_list() -> void:
	# Renderizza entries[] dentro l'ItemList del dock.
	# Non fa fetch, non aggiorna dati: solo UI.

	if item_list == null:
		return

	# Reset UI: pulizia lista, preview e disabilito "place"
	item_list.clear()
	if preview:
		preview.texture = null
	if place_btn:
		place_btn.disabled = true

	# Inserisce tutte le entries in lista
	for e in entries:
		# e è un Dictionary: e.name, e.item_id sono accessibili come proprietà in GDScript
		# Icona placeholder: verrà sostituita da thumbnail reali quando le avremo dal DB
		var idx := item_list.add_item("%s  (#%d)" % [e.name, e.item_id], default_icon)
		item_list.set_item_tooltip(idx, "item_id=%d" % e.item_id)


func on_item_selected(index: int, has_scene: bool) -> void:
	# Callback chiamata dal dock quando cambia selezione in ItemList.
	# has_scene indica se siamo in una scena valida (LivingScene), utile per abilitare/disabilitare "Place".

	# Se manca la UI, non possiamo aggiornare nulla
	if place_btn == null:
		return

	# Se selezione invalida: disabilita "Place"
	if index < 0 or index >= entries.size():
		place_btn.disabled = true
		return

	# Abilita "Place" solo se abbiamo una scena valida
	place_btn.disabled = not has_scene

	# Aggiorna preview (placeholder per ora)
	if preview:
		preview.texture = default_icon
		
		
