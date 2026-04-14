@tool
extends RefCounted
class_name OmekaItemService

# Domain service for item metadata used by LivingItem.
# Important: JSON metadata only (no media probe/download here).

var _query_cache: OmekaQueryCache


func _init(query_cache: OmekaQueryCache = null) -> void:
	# Allows dependency injection in tests; defaults to shared cache in production.
	_query_cache = query_cache if query_cache != null else OmekaQueryCache.shared()


# Return shape:
# {
#   "ok": bool,
#   "metadata": Dictionary,
#   "item": Dictionary,
#   "error": String?
# }
func get_item_metadata(host: Node, base_url: String, item_id: int, force_refresh: bool = false) -> Dictionary:
	# Fetches a single item and exposes the normalized metadata contract used by LivingItem.
	var item_result := await _query_cache.get_item_by_id(host, base_url, item_id, force_refresh)
	if not item_result.get("ok", false):
		return item_result

	var item: Dictionary = item_result.get("item", {})
	if typeof(item) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Unexpected JSON Format"}

	return {
		"ok": true,
		"metadata": _normalize_item_metadata(item),
		"item": item
	}


# Optional convenience batch for future usage.
func get_items_metadata(host: Node, base_url: String, item_ids: Array[int], force_refresh: bool = false) -> Dictionary:
	# Best-effort batch helper: failed ids are skipped, valid ones are returned.
	var out: Array[Dictionary] = []
	for item_id in item_ids:
		var result := await get_item_metadata(host, base_url, int(item_id), force_refresh)
		if result.get("ok", false):
			out.append(result.get("metadata", {}))
	return {"ok": true, "items": out}


func _normalize_item_metadata(item: Dictionary) -> Dictionary:
	# Converts raw Omeka payload into a stable app-level metadata shape.
	var components: Array[int] = []
	for comp in item.get("lcp_form:is_composed_of_f", []):
		if typeof(comp) != TYPE_DICTIONARY:
			continue
		var cid := int(comp.get("value_resource_id", 0))
		if cid > 0 and not components.has(cid):
			components.append(cid)

	var areas: Array[int] = []
	for area in item.get("lcp_form:has_participatory_area_f", []):
		if typeof(area) != TYPE_DICTIONARY:
			continue
		var aid := int(area.get("value_resource_id", 0))
		if aid > 0 and not areas.has(aid):
			areas.append(aid)

	var medium_uri := ""
	var has_uri = item.get("lcp_form:has_URI", [])
	if typeof(has_uri) == TYPE_ARRAY and not has_uri.is_empty() and typeof(has_uri[0]) == TYPE_DICTIONARY:
		medium_uri = str(has_uri[0].get("@id", ""))

	var thumbnail_uri := ""
	var thumb_urls = item.get("thumbnail_display_urls", {})
	if typeof(thumb_urls) == TYPE_DICTIONARY:
		thumbnail_uri = str(thumb_urls.get("square", ""))

	return {
		"id": int(item.get("o:id", 0)),
		"title": str(item.get("o:title", "No Title")),
		"modified": str(item.get("o:modified", {}).get("@value", "")),
		"short_description": _extract_literal(item, "lcp_form:has_short_text_f"),
		"long_description": _extract_literal(item, "lcp_form:has_long_text_f"),
		"catalog_description": _extract_literal(item, "lcp_form:has_catalogue_text_f"),
		"resource_class": int(item.get("o:resource_class", {}).get("o:id", 0)),
		"components": components,
		"areas": areas,
		"medium_uri": medium_uri,
		"thumbnail_uri": thumbnail_uri
	}


func _extract_literal(item: Dictionary, key: String) -> String:
	# Omeka literals are stored as arrays of value objects; this returns the first value.
	var values = item.get(key, [])
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return ""
	var first = values[0]
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	return str(first.get("@value", ""))
