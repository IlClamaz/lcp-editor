@tool
extends RefCounted
class_name OmekaEnvironmentsService

# Fetches the list of participatory environments from Omeka (editor catalog / Update List).

const PARTICIPATORY_FORM_TYPE := "lcp_form:Participatory_item_form"
const PARTICIPATORY_TYPE_KEY := "lcp_form:has_participatory_item_type_f"
const ENVIRONMENT_TYPE_VALUE := "Ambiente"

var _query: OmekaQueryService


func _init(query: OmekaQueryService = null) -> void:
	_query = query if query != null else OmekaQueryService.new()


# Returns { "ok": bool, "items": [{"id": int, "title": String}], "pages": int, "error": String? }
func list_environments(host: Node, base_url: String) -> Dictionary:
	var query_suffix := (
		"property[0][property]=%s&property[0][type]=eq&property[0][text]=%s"
		% [PARTICIPATORY_TYPE_KEY, ENVIRONMENT_TYPE_VALUE]
	)
	var search_result := await _query.search_items(host, base_url, query_suffix)
	if not search_result.get("ok", false):
		return search_result

	var out: Array[Dictionary] = []
	for item in search_result.get("items", []):
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
		"pages": int(search_result.get("pages", 1))
	}


func _is_environment_item(item: Dictionary) -> bool:
	var types = item.get("@type", [])
	if typeof(types) != TYPE_ARRAY or not PARTICIPATORY_FORM_TYPE in types:
		return false

	var part_type_arr = item.get(PARTICIPATORY_TYPE_KEY, [])
	if typeof(part_type_arr) != TYPE_ARRAY or part_type_arr.is_empty():
		return false

	return str(part_type_arr[0].get("@value", "")) == ENVIRONMENT_TYPE_VALUE
