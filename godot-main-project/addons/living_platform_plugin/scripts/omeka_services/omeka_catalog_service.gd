@tool
extends RefCounted
class_name OmekaCatalogService

# Domain service for catalog data.
# Purpose: return the global list of environments (also when no scene is open).

const PARTICIPATORY_FORM_TYPE := "lcp_form:Participatory_item_form"
const PARTICIPATORY_TYPE_KEY := "lcp_form:has_participatory_item_type_f"

var _query_cache: OmekaQueryCache


func _init(query_cache: OmekaQueryCache = null) -> void:
	# Allows dependency injection in tests; defaults to shared cache in production.
	_query_cache = query_cache if query_cache != null else OmekaQueryCache.shared()


# Return shape:
# { "ok": bool, "items": [{"id": int, "title": String}], "pages": int, "error": String? }
func list_environments(host: Node, base_url: String, force_refresh: bool = false) -> Dictionary:
	# Reads the global Omeka catalog and extracts only "Ambiente" items.
	var all_items_result := await _query_cache.get_all_items(host, base_url, force_refresh)
	if not all_items_result.get("ok", false):
		return all_items_result

	var out: Array[Dictionary] = []
	var all_items: Array = all_items_result.get("items", [])
	for item in all_items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if not _is_environment_item(item):
			continue

		var env_id := int(item.get("o:id", 0))
		if env_id <= 0:
			continue

		out.append({
			"id": env_id,
			"title": str(item.get("o:title", "No Title"))
		})

	return {
		"ok": true,
		"items": out,
		"pages": int(all_items_result.get("pages", 1))
	}


func _is_environment_item(item: Dictionary) -> bool:
	# Environment = participatory form + participatory type value "Ambiente".
	var types = item.get("@type", [])
	if typeof(types) != TYPE_ARRAY or not PARTICIPATORY_FORM_TYPE in types:
		return false

	var part_type_arr = item.get(PARTICIPATORY_TYPE_KEY, [])
	if typeof(part_type_arr) != TYPE_ARRAY or part_type_arr.is_empty():
		return false

	return str(part_type_arr[0].get("@value", "")) == "Ambiente"
