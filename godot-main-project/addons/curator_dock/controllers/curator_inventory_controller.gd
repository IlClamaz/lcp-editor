@tool
extends RefCounted
class_name CuratorInventoryController

var item_list: ItemList
var preview: TextureRect
var place_btn: Button
var default_icon: Texture2D

var pipeline: CuratorPipeline
var scene_ctrl: CuratorSceneController

# Snapshot generato ALTROVE (quando fai Instantiate da DB)
var current_env_snapshot: Array = []

func _init(_pipeline: CuratorPipeline, _scene_ctrl: CuratorSceneController) -> void:
	pipeline = _pipeline
	scene_ctrl = _scene_ctrl

func bind_ui(_item_list: ItemList, _preview: TextureRect, _place_btn: Button, _default_icon: Texture2D) -> void:
	item_list = _item_list
	preview = _preview
	place_btn = _place_btn
	default_icon = _default_icon

func clear_ui() -> void:
	if item_list: item_list.clear()
	if preview: preview.texture = null
	if place_btn: place_btn.disabled = true

# ------------------------------------------------------------
# Snapshot API (chiamata dal dock quando premi Instantiate)
# ------------------------------------------------------------
func set_snapshot(snapshot: Array, editor_interface: EditorInterface) -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	current_env_snapshot = snapshot if snapshot != null else []
	render_list(env)

# ------------------------------------------------------------
# RENDER (da snapshot)
# ------------------------------------------------------------
func render_list(env_root: LivingEnvironment) -> void:
	print("render_list called at: ", Time.get_ticks_msec())
	if item_list == null:
		return

	# ✅ evita accumulo righe tra refresh
	item_list.clear()

	if current_env_snapshot == null or current_env_snapshot.size() == 1:
		item_list.add_item("⚠ Errore con il database: controlla la connessione, l'ID o l'URL", default_icon)
		return

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
			indent = "  └─ "
		elif level == 2:
			indent = "    └─ "
		elif level == 3:
			indent = "      └─ "
		elif level >= 4:
			indent = "        └─ "

		var text := "%s%s%s" % [prefix, indent, nm]
		var idx := item_list.add_item(text, default_icon)

		item_list.set_item_metadata(idx, {
			"name": nm,
			"nesting_level": level,
			"visible": vis,
			"node_path": node_path,
			"instance_id": instance_id
		})

# ------------------------------------------------------------
# Selection (abilita bottone toggle e setta preview)
# ------------------------------------------------------------
func on_item_selected(index: int, has_scene: bool) -> void:
	if place_btn == null:
		return

	if not has_scene:
		place_btn.disabled = true
		return

	if item_list == null or index < 0 or index >= item_list.item_count:
		place_btn.disabled = true
		return

	var md := item_list.get_item_metadata(index)
	if typeof(md) != TYPE_DICTIONARY:
		place_btn.disabled = true
		return

	# Abilitiamo sempre: il dock poi decide cosa fare (toggle visibilità)
	place_btn.disabled = false

	if preview:
		preview.texture = default_icon
