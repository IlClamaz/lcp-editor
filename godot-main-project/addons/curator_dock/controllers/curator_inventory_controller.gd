@tool
extends RefCounted
class_name CuratorInventoryController

# --- MODIFICA: Ora usiamo un Tree ---
var components_list: Tree
var preview: TextureRect
var default_icon: Texture2D
const ICON_AREA_PATH := "res://addons/curator_dock/icons/letter-a.png"
const ICON_OBJ_PATH := "res://addons/curator_dock/icons/letter-o.png"

var _icon_area: Texture2D = null
var _icon_elem: Texture2D = null
var _thumb_cache: Dictionary = {} # path -> Texture2D

# Icone native dell'Editor per i bottoni (occhio e lucchetto)
var _icon_vis_on: Texture2D = null
var _icon_vis_off: Texture2D = null
var _icon_lock_on: Texture2D = null
var _icon_lock_off: Texture2D = null

# Snapshot generato da curator_dock (quando fai Instantiate da DB)
var current_env_snapshot: Array = []

var _last_selected_instance_id: int = 0
var _last_selected_node_path: String = ""

func bind_ui(_components_list: Tree, _preview: TextureRect, _default_icon: Texture2D) -> void:
	components_list = _components_list
	preview = _preview
	default_icon = _default_icon
	_ensure_editor_icons()

func clear_ui() -> void:
	if components_list: components_list.clear()
	if preview: preview.texture = null

# Recupera le icone di sistema di Godot per i bottoni
func _ensure_editor_icons() -> void:
	if _icon_vis_on != null: return
	if Engine.is_editor_hint():
		var theme = EditorInterface.get_editor_theme()
		_icon_vis_on = theme.get_icon("GuiVisibilityVisible", "EditorIcons")
		_icon_vis_off = theme.get_icon("GuiVisibilityHidden", "EditorIcons")
		_icon_lock_on = theme.get_icon("Lock", "EditorIcons")
		_icon_lock_off = theme.get_icon("Unlock", "EditorIcons")
	else:
		_icon_vis_on = default_icon
		_icon_vis_off = default_icon
		_icon_lock_on = default_icon
		_icon_lock_off = default_icon

# ------------------------------------------------------------
# Snapshot API (chiamata dal dock quando premi Instantiate)
# ------------------------------------------------------------
func set_snapshot(snapshot: Array, env: LivingEnvironment, editor_interface: EditorInterface) -> void:
	current_env_snapshot = snapshot if snapshot != null else []

# ------------------------------------------------------------
# RENDER (da snapshot)
# ------------------------------------------------------------
func render_list() -> bool:
	if components_list == null:
		return false

	_capture_current_selection_before_render()

	# Svuota il Tree
	components_list.clear()
	preview.texture = null
	
	# Crea la radice invisibile (necessaria per il Tree)
	var root = components_list.create_item()

	if current_env_snapshot == null or current_env_snapshot.size() <= 1: # contiene solo l'env
		var err_item = components_list.create_item(root)
		err_item.set_text(0, "⚠ Errore: controlla la connessione, l'ID o l'URL")
		err_item.set_icon(0, default_icon)
		return false

	# ✅ set per dedup
	var seen := {}  # Dictionary usato come Set: key -> true

	for row in current_env_snapshot:
		if typeof(row) != TYPE_DICTIONARY:
			continue

		var level := int(row.get("nesting_level", 0))
		if level == 0: continue
		var nm := str(row.get("name", ""))
		if nm.contains("Container"):   # DA FIXARE!!!!
			continue
		
		var vis := bool(row.get("visible", true))
		var locked := bool(row.get("locked", false))

		var node_path := str(row.get("node_path", ""))
		var instance_id := int(row.get("instance_id", 0))

		# ✅ chiave univoca (preferisci instance_id)
		var key := ""
		if instance_id != 0:
			key = "iid:%d" % instance_id
		elif node_path != "":
			key = "path:%s" % node_path
		else:
			key = "fallback:%s:%d" % [nm, level]

		if seen.has(key):
			continue
		seen[key] = true

		# Creiamo l'indentazione testuale
		var indent := ""
		if level == 1:
			indent = "└─ "
		elif level == 2:
			indent = "   └─└─ "
		elif level == 3:
			indent = "   └─└─└─ "
		elif level >= 4:
			indent = "     └─└─└─└─ "

		var text := "%s%s" % [indent, nm]
		var thumb_path := str(row.get("thumbnail_path", ""))
		
		var icon_to_use: Texture2D = null

		# 1) prova thumbnail
		var t := _load_thumb(thumb_path)
		if t != null:
			icon_to_use = t
		else:
			# 2) fallback A/E
			var node: Node = null
			if instance_id != 0:
				var obj := instance_from_id(instance_id)
				if obj != null and obj is Node:
					node = obj as Node
			icon_to_use = _get_area_icon() if (node is LivingArea) else _get_elem_icon()
			
		# --- COSTRUZIONE DI UNA RIGA NEL TREE ---
		var list_row = components_list.create_item(root)
		
		# Colonna 0: Nome e Thumbnail
		list_row.set_text(0, text)
		list_row.set_icon(0, icon_to_use if icon_to_use != null else default_icon)
		list_row.set_icon_max_width(0, 64)

		# Colonna 1: Icona Visibilità (Solo indicatore grafico, non cliccabile)
		list_row.set_icon(1, _icon_vis_on if vis else _icon_vis_off)
		
		# Colonna 2: Icona Blocco (Solo indicatore grafico, non cliccabile)
		list_row.set_icon(2, _icon_lock_on if locked else _icon_lock_off)
		
		# Salviamo i metadati
		list_row.set_metadata(0, {
			"name": nm,
			"nesting_level": level,
			"visible": vis,
			"locked": locked,
			"node_path": node_path,
			"instance_id": instance_id,
			"thumbnail_path": thumb_path
		})

		# L'oggetto DEVE rimanere selezionabile per poterlo sbloccare dall'inspector
		list_row.set_selectable(0, true)
		list_row.set_selectable(1, false) # Le icone extra non sono selezionabili individualmente
		list_row.set_selectable(2, false)

	_restore_selection_after_render()
	return true

func _capture_current_selection_before_render() -> void:
	_last_selected_instance_id = 0
	_last_selected_node_path = ""

	if components_list == null:
		return

	var sel = components_list.get_selected()
	if sel == null:
		return

	var md = sel.get_metadata(0)
	if typeof(md) == TYPE_DICTIONARY:
		_last_selected_instance_id = int(md.get("instance_id", 0))
		_last_selected_node_path = str(md.get("node_path", ""))

func _restore_selection_after_render() -> void:
	if components_list == null:
		return
		
	var root = components_list.get_root()
	if root == null:
		return

	var target: TreeItem = null
	var child = root.get_first_child()
	
	# Cerchiamo tra tutti i figli
	while child != null:
		var md = child.get_metadata(0)
		if typeof(md) == TYPE_DICTIONARY:
			# 1) prova con instance_id
			if _last_selected_instance_id != 0 and int(md.get("instance_id", 0)) == _last_selected_instance_id:
				target = child
				break
			# 2) fallback su node path
			elif _last_selected_node_path != "" and str(md.get("node_path", "")) == _last_selected_node_path:
				target = child
				break
		child = child.get_next()

	# 3) se trovato: seleziona e rendi visibile
	components_list.deselect_all()
	if target != null:
		target.select(0)
		components_list.scroll_to_item(target)
		preview.texture = target.get_icon(0)

# ------------------------------------------------------------
# Selection 
# ------------------------------------------------------------
# MODIFICA: il segnale "item_selected" del Tree non passa un index!
func on_item_selected(has_scene: bool) -> void:
	if not has_scene or components_list == null:
		return

	var sel = components_list.get_selected()
	if sel == null:
		return

	var md = sel.get_metadata(0)
	if typeof(md) != TYPE_DICTIONARY:
		return

	_last_selected_instance_id = int(md.get("instance_id", 0))
	_last_selected_node_path = str(md.get("node_path", ""))

	if preview:
		var thumb_path := str(md.get("thumbnail_path", ""))
		var tex := _load_thumb(thumb_path)
		if tex != null:
			preview.texture = tex
		else:
			var node: Node = null
			var iid := int(md.get("instance_id", 0))
			if iid != 0:
				var obj := instance_from_id(iid)
				if obj != null and obj is Node:
					node = obj as Node

			preview.texture = _get_area_icon() if (node is LivingArea) else _get_elem_icon()

func on_clear_selection() -> void:
	if components_list:
		components_list.deselect_all()
	if preview:
		preview.texture = null
	_last_selected_instance_id = 0
	_last_selected_node_path = ""

func _resolve_item_node_from_selection(env: LivingEnvironment) -> Node:
	if env == null or components_list == null:
		return null
		
	var sel = components_list.get_selected()
	if sel == null:
		return null

	var md = sel.get_metadata(0)
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

# ------------------------------------------------------------
# Ricerca e Selezione Esterna
# ------------------------------------------------------------
func select_by_instance_id(target_iid: int) -> bool:
	if components_list == null or target_iid == 0:
		return false

	var root = components_list.get_root()
	if root == null:
		return false

	var child = root.get_first_child()
	while child != null:
		var md = child.get_metadata(0)
		if typeof(md) == TYPE_DICTIONARY and int(md.get("instance_id", 0)) == target_iid:
			# Trovato! Lo selezioniamo graficamente
			components_list.deselect_all()
			child.select(0)
			components_list.scroll_to_item(child)
			return true
		child = child.get_next()

	return false

func _load_thumb(path: String) -> Texture2D:
	if path == "":
		return null
	if _thumb_cache.has(path):
		return _thumb_cache[path]

	if not FileAccess.file_exists(path):
		return null

	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		return null

	var tex := ImageTexture.create_from_image(img)
	_thumb_cache[path] = tex
	return tex

func _get_area_icon() -> Texture2D:
	if _icon_area == null:
		_icon_area = load(ICON_AREA_PATH) as Texture2D
	return _icon_area if _icon_area != null else default_icon

func _get_elem_icon() -> Texture2D:
	if _icon_elem == null:
		_icon_elem = load(ICON_OBJ_PATH) as Texture2D
	return _icon_elem if _icon_elem != null else default_icon
