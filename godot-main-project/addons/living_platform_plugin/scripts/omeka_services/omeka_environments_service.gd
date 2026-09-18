@tool
extends RefCounted
class_name OmekaEnvironmentsService

# Fetches the list of participatory environments from Omeka (editor catalog / Update List).

var _query: OmekaQueryService


func _init(query: OmekaQueryService = null) -> void:
	_query = query if query != null else OmekaQueryService.new()


# Returns { "ok": bool, "items": [{"id": int, "title": String}], "pages": int, "error": String? }
func list_environments(host: Node, base_url: String, item_set_id: int = 0) -> Dictionary:
	var query_suffix := (
		"property[0][property]=%s&property[0][type]=eq&property[0][text]=%s"
		% [LivingConstants.OMEKA_KEY_PARTICIPATORY_ITEM_TYPE, LivingConstants.PARTICIPATORY_TYPE_AMBIENTE]
	)
	if item_set_id > 0:
		query_suffix += "&item_set_id=%d" % item_set_id
	var search_result := await _query.search_items(host, base_url, query_suffix)
	if not search_result.get("ok", false):
		return search_result

	var out: Array[Dictionary] = []
	for item in search_result.get("items", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if not _is_environment_item(item):
			continue

		var env_id := int(item.get(LivingConstants.OMEKA_KEY_ID, 0))
		if env_id <= 0:
			continue

		var item_sets = item.get("o:item_set", [])
		if item_set_id > 0:
			var has_set := false
			if typeof(item_sets) == TYPE_ARRAY:
				for s in item_sets:
					if typeof(s) == TYPE_DICTIONARY and int(s.get("o:id", s.get("id", 0))) == item_set_id:
						has_set = true
						break
			if not has_set:
				continue
		else:
			# item_set_id == 0 means "None" (must not belong to any item set)
			if typeof(item_sets) == TYPE_ARRAY and not item_sets.is_empty():
				continue

		out.append({
			"id": env_id,
			"title": str(item.get(LivingConstants.OMEKA_KEY_TITLE, LivingConstants.OMEKA_DEFAULT_ITEM_TITLE))
		})

	return {
		"ok": true,
		"items": out,
		"pages": int(search_result.get("pages", 1))
	}


# Returns { "ok": bool, "items": [{"id": int, "title": String}], "pages": int, "error": String? }
func list_item_sets(host: Node, base_url: String) -> Dictionary:
	var search_result := await _query.search_item_sets(host, base_url)
	if not search_result.get("ok", false):
		return search_result

	var out: Array[Dictionary] = []
	for item in search_result.get("items", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var set_id := int(item.get(LivingConstants.OMEKA_KEY_ID, 0))
		if set_id <= 0:
			continue

		var title: String = ""
		if item.has(LivingConstants.OMEKA_KEY_TITLE) and item[LivingConstants.OMEKA_KEY_TITLE] != null:
			title = str(item[LivingConstants.OMEKA_KEY_TITLE])
		if title.strip_edges() == "":
			var dcterms = item.get("dcterms:title", [])
			if typeof(dcterms) == TYPE_ARRAY and not dcterms.is_empty():
				var first = dcterms[0]
				if typeof(first) == TYPE_DICTIONARY:
					title = str(first.get("@value", ""))
		if title.strip_edges() == "":
			title = LivingConstants.OMEKA_DEFAULT_ITEM_TITLE

		out.append({
			"id": set_id,
			"title": title
		})

	return {
		"ok": true,
		"items": out,
		"pages": int(search_result.get("pages", 1))
	}


func _is_environment_item(item: Dictionary) -> bool:
	var types = item.get("@type", [])
	if typeof(types) != TYPE_ARRAY or not LivingConstants.OMEKA_KEY_PARTICIPATORY_FORM_TYPE in types:
		return false

	var part_type_arr = item.get(LivingConstants.OMEKA_KEY_PARTICIPATORY_ITEM_TYPE, [])
	if typeof(part_type_arr) != TYPE_ARRAY or part_type_arr.is_empty():
		return false

	return str(part_type_arr[0].get(LivingConstants.OMEKA_KEY_AT_VALUE, "")) == LivingConstants.PARTICIPATORY_TYPE_AMBIENTE
