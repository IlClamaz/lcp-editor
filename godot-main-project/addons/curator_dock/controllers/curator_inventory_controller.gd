@tool
extends RefCounted
class_name CuratorInventoryController

var item_list: ItemList
var preview: TextureRect
var default_icon: Texture2D

# Snapshot generato da curator_dock (quando fai Instantiate da DB)
var current_env_snapshot: Array = []

var _last_selected_instance_id: int = 0
var _last_selected_node_path: String = ""

func bind_ui(_item_list: ItemList, _preview: TextureRect, _default_icon: Texture2D) -> void:
	item_list = _item_list
	preview = _preview
	default_icon = _default_icon

func clear_ui() -> void:
	if item_list: item_list.clear()
	if preview: preview.texture = null

# ------------------------------------------------------------
# Snapshot API (chiamata dal dock quando premi Instantiate)
# ------------------------------------------------------------
func set_snapshot(snapshot: Array, env: LivingEnvironment, editor_interface: EditorInterface) -> void:
	current_env_snapshot = snapshot if snapshot != null else []

# ------------------------------------------------------------
# RENDER (da snapshot)
# ------------------------------------------------------------
func render_list(env_root: LivingEnvironment) -> bool:
	# print("render_list called at: ", Time.get_ticks_msec())
	if item_list == null:
		return false

	_capture_current_selection_before_render()

	# ✅ evita accumulo righe tra refresh
	item_list.clear()
	preview.texture = null

	if current_env_snapshot == null or current_env_snapshot.size() <= 1:
		item_list.add_item("⚠ Errore con il database: controlla la connessione, l'ID o l'URL", default_icon)
		return false

	# ✅ set per dedup
	var seen := {}  # Dictionary usato come Set: key -> true

	for row in current_env_snapshot:
		if typeof(row) != TYPE_DICTIONARY:
			continue

		var level := int(row.get("nesting_level", 0))
		if(level == 0): continue
		var nm := str(row.get("name", ""))
		var vis := bool(row.get("visible", true))

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

		var prefix := ("👁️ " if vis else "🚫 ")

		var indent := ""
		if level == 1:
			indent = "└─ "
		elif level == 2:
			indent = "   └─└─ "
		elif level == 3:
			indent = "     └─└─└─ "
		elif level >= 4:
			indent = "       └─└─└─└─ "

		var text := "%s%s%s" % [prefix, indent, nm]
		var thumb_path := str(row.get("thumbnail_path", ""))
		var icon_tex: Texture2D = default_icon
		if thumb_path != "":
			var t := _load_thumbnail_texture(thumb_path)
			if t != null:
				icon_tex = t

		var idx := item_list.add_item(text, icon_tex)

		item_list.set_item_metadata(idx, {
			"name": nm,
			"nesting_level": level,
			"visible": vis,
			"node_path": node_path,
			"instance_id": instance_id,
			"thumbnail_path": thumb_path
		})

	_restore_selection_after_render()
	return true

func _capture_current_selection_before_render() -> void:
	_last_selected_instance_id = 0
	_last_selected_node_path = ""

	if item_list == null:
		return

	var sel := item_list.get_selected_items()
	if sel.is_empty():
		return

	var idx := int(sel[0])
	if idx < 0 or idx >= item_list.item_count:
		return

	var md := item_list.get_item_metadata(idx)
	if typeof(md) != TYPE_DICTIONARY:
		return

	_last_selected_instance_id = int(md.get("instance_id", 0))
	_last_selected_node_path = str(md.get("node_path", ""))

func _restore_selection_after_render() -> void:
	if item_list == null:
		return

	var idx := -1

	# 1) prova con instance_id (più robusto)
	if _last_selected_instance_id != 0:
		idx = find_index_by_instance_id(item_list, _last_selected_instance_id)

	# 2) fallback: match su node_path
	if idx < 0 and _last_selected_node_path != "":
		for i in range(item_list.item_count):
			var md := item_list.get_item_metadata(i)
			if typeof(md) == TYPE_DICTIONARY and str(md.get("node_path", "")) == _last_selected_node_path:
				idx = i
				break

	# 3) se trovato: seleziona e rendi visibile nella lista
	item_list.deselect_all()
	if idx >= 0:
		item_list.select(idx)
		item_list.ensure_current_is_visible()
		preview.texture = _load_thumbnail_texture(str(item_list.get_item_metadata(idx).get("thumbnail_path", "")))

# ------------------------------------------------------------
# Selection (abilita bottone toggle e setta preview)
# ------------------------------------------------------------
func on_item_selected(index: int, has_scene: bool) -> void:

	if not has_scene:
		return

	if item_list == null or index < 0 or index >= item_list.item_count:
		return

	var md := item_list.get_item_metadata(index)
	if typeof(md) != TYPE_DICTIONARY:
		return

	_last_selected_instance_id = int(md.get("instance_id", 0))
	_last_selected_node_path = str(md.get("node_path", ""))
	# Abilitiamo sempre: il dock poi decide cosa fare (toggle visibilità)

	if preview:
		var thumb_path := str(md.get("thumbnail_path", ""))
		var t: Texture2D = null
		if thumb_path != "":
			t = _load_thumbnail_texture(thumb_path)
		preview.texture = t if t != null else default_icon


func clear_last_selection() -> void:
	_last_selected_instance_id = 0
	_last_selected_node_path = ""
	if item_list:
		item_list.deselect_all()

func find_index_by_instance_id(list: ItemList, instance_id: int) -> int:
	if list == null or instance_id == 0:
		return -1

	for i in range(list.item_count):
		var md = list.get_item_metadata(i)
		if typeof(md) == TYPE_DICTIONARY and int(md.get("instance_id", 0)) == instance_id:
			return i

	return -1

var _thumb_cache: Dictionary = {} # path -> Texture2D

func _load_thumbnail_texture(path: String) -> Texture2D:
	if path == "":
		return null

	# cache
	if _thumb_cache.has(path):
		return _thumb_cache[path]

	# se il file non esiste, niente
	if not FileAccess.file_exists(path):
		_thumb_cache[path] = null
		return null

	# Godot: load() funziona con res:// (se thumbnail_path è res://...)
	var tex := load(path)
	if tex != null and tex is Texture2D:
		_thumb_cache[path] = tex
		return tex as Texture2D

	_thumb_cache[path] = null
	return null
