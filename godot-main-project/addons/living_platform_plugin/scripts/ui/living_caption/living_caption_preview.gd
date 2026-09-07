@tool
extends Node3D

class_name LivingCaptionPreview

## Editor-only visualization of short/long caption poses.
## Created under the medium like LivingVisitPoint: no owner, not packed in .tscn.
## Pose comes from CaptionManager.compute_*_caption_abs_position.

const NODE_NAME := "LivingCaptionPreview"
const SHORT_NODE_NAME := "PreviewShortCaption"
const LONG_NODE_NAME := "PreviewLongCaption"
const SHORT_PLACEHOLDER := "(short caption)"
const LONG_PLACEHOLDER := "(long caption)"


static func sync_on_medium(medium: Node3D, host: LivingVisitableObject, enabled: bool) -> void:
	if not Engine.is_editor_hint():
		return

	if medium == null:
		return

	var existing := medium.get_node_or_null(NODE_NAME) as LivingCaptionPreview
	if not enabled:
		if existing != null:
			existing.queue_free()
		return

	if not medium.is_inside_tree() or host == null:
		return

	var preview := existing
	if preview == null:
		preview = LivingCaptionPreview.new()
		preview.name = NODE_NAME
		medium.add_child(preview)
		# Intentionally no owner — same pattern as LivingVisitPoint.

	preview._refresh_from_host(host)


func _ready() -> void:
	top_level = true
	set_process(Engine.is_editor_hint())
	if Engine.is_editor_hint():
		_ensure_captions()
		_follow_host_poses()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return
	_follow_host_poses()


func _refresh_from_host(host: LivingVisitableObject) -> void:
	_ensure_captions()
	_apply_texts(host)
	_follow_host_poses()


func _ensure_captions() -> void:
	if not is_inside_tree():
		return

	var short_hud := get_node_or_null(SHORT_NODE_NAME) as LivingCaptionHud
	if short_hud == null:
		short_hud = LivingCaptionHud.new(false)
		short_hud.name = SHORT_NODE_NAME
		short_hud.top_level = true
		add_child(short_hud)
		short_hud.set_font_size(CaptionManager.HUD_FONT_SIZE)
		short_hud.set_font_depth(CaptionManager.HUD_FONT_DEPTH)
		short_hud.set_text_color(CaptionManager.CAPTION_FONT_COLOR)
		var hud_scale := CaptionManager.HUD_SCALE
		short_hud.scale = Vector3(hud_scale, hud_scale, hud_scale)

	var long_caption := get_node_or_null(LONG_NODE_NAME) as LivingCaptionLong
	if long_caption == null:
		var catalog := ""
		var host := _get_host()
		if host != null:
			catalog = str(host.catalog_description)
		long_caption = LivingCaptionLong.new(false, catalog)
		long_caption.name = LONG_NODE_NAME
		long_caption.top_level = true
		add_child(long_caption)
		long_caption.set_text_color(CaptionManager.CAPTION_FONT_COLOR)


func _apply_texts(host: LivingVisitableObject) -> void:
	if host == null:
		return
	var short_hud := get_node_or_null(SHORT_NODE_NAME) as LivingCaptionHud
	if short_hud != null:
		short_hud.set_text(_preview_short_text(host))
	var long_caption := get_node_or_null(LONG_NODE_NAME) as LivingCaptionLong
	if long_caption != null:
		long_caption.set_text(_preview_long_text(host))


func _follow_host_poses() -> void:
	if not is_inside_tree():
		return
	var host := _get_host()
	if host == null or not host.is_inside_tree():
		return

	var short_hud := get_node_or_null(SHORT_NODE_NAME) as LivingCaptionHud
	if short_hud != null:
		var short_loc: Array = CaptionManager.compute_short_caption_abs_position(host)
		short_hud.global_position = short_loc[0]
		short_hud.global_rotation_degrees = Vector3(0.0, short_loc[1], 0.0)

	var long_caption := get_node_or_null(LONG_NODE_NAME) as LivingCaptionLong
	if long_caption != null:
		var long_loc: Array = CaptionManager.compute_long_caption_abs_position(host)
		long_caption.global_position = long_loc[0]
		long_caption.global_rotation_degrees = Vector3(0.0, long_loc[1], 0.0)


func _get_host() -> LivingVisitableObject:
	var medium := get_parent() as Node3D
	if medium == null:
		return null
	return medium.get_parent() as LivingVisitableObject


static func _preview_short_text(host: LivingVisitableObject) -> String:
	var text := str(host.short_description).strip_edges()
	if text.is_empty():
		return SHORT_PLACEHOLDER
	return text


static func _preview_long_text(host: LivingVisitableObject) -> String:
	var text := str(host.long_description).strip_edges()
	if text.is_empty():
		return LONG_PLACEHOLDER
	return text
