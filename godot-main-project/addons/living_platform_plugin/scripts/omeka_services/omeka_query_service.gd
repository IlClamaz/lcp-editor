@tool
extends RefCounted
class_name OmekaQueryService

# Low-level Omeka REST client: paginated item search and single-item fetch.

const PER_PAGE := 100


# Fetches one Omeka item by id. Always hits the network.
# Returns { "ok": bool, "item": Dictionary, "error": String? }
func get_item_by_id(host: Node, base_url: String, item_id: int) -> Dictionary:
	var normalized := _normalize_base_url(base_url)
	if normalized == "":
		return {"ok": false, "error": "Invalid base URL"}
	if host == null:
		return {"ok": false, "error": "Invalid host"}
	if item_id <= 0:
		return {"ok": false, "error": "Invalid item id"}

	var item_url := "%s/api/items?pretty_print=1&id=%d" % [normalized, item_id]
	var response := await HTTPDownloader.request_json(host, item_url, 20.0)
	if not response.get("ok", false):
		return {"ok": false, "error": "Connection Error (Code: %s)" % str(response.get("response_code", 0))}

	var data = response.get("json", [])
	if typeof(data) != TYPE_ARRAY or data.is_empty():
		return {"ok": false, "error": "Item not found"}

	var item = data[0]
	if typeof(item) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Unexpected JSON Format"}

	return {"ok": true, "item": item}


# Runs a filtered, paginated GET /api/items search. query_suffix is appended after page params.
# Returns { "ok": bool, "items": Array, "pages": int, "error": String? }
func search_items(host: Node, base_url: String, query_suffix: String) -> Dictionary:
	var normalized := _normalize_base_url(base_url)
	if normalized == "":
		return {"ok": false, "error": "Invalid base URL"}
	if host == null:
		return {"ok": false, "error": "Invalid host"}

	return await _fetch_resources_paginated(host, normalized, "items", query_suffix)


# Runs a filtered, paginated GET /api/item_sets search. query_suffix is appended after page params.
# Returns { "ok": bool, "items": Array, "pages": int, "error": String? }
func search_item_sets(host: Node, base_url: String, query_suffix: String = "") -> Dictionary:
	var normalized := _normalize_base_url(base_url)
	if normalized == "":
		return {"ok": false, "error": "Invalid base URL"}
	if host == null:
		return {"ok": false, "error": "Invalid host"}

	return await _fetch_resources_paginated(host, normalized, "item_sets", query_suffix)


func _fetch_items_paginated(host: Node, normalized_base_url: String, query_suffix: String) -> Dictionary:
	return await _fetch_resources_paginated(host, normalized_base_url, "items", query_suffix)


func _fetch_resources_paginated(host: Node, normalized_base_url: String, resource_endpoint: String, query_suffix: String) -> Dictionary:
	var page := 1
	var pages := 1
	var all_items: Array = []

	while true:
		var api_url := "%s/api/%s?per_page=%d&page=%d" % [normalized_base_url, resource_endpoint, PER_PAGE, page]
		var suffix := query_suffix.strip_edges()
		if suffix != "":
			api_url += "&" + suffix
		var response := await HTTPDownloader.request_json(host, api_url, 25.0)
		if not response.get("ok", false):
			return {
				"ok": false,
				"error": "Connection Error (Code: %s)" % str(response.get("response_code", 0))
			}

		var data = response.get("json", [])
		if typeof(data) != TYPE_ARRAY:
			return {"ok": false, "error": "Unexpected JSON Format"}

		var page_items: Array = data
		all_items.append_array(page_items)
		pages = page

		if page_items.size() < PER_PAGE:
			break
		page += 1

	return {"ok": true, "items": all_items, "pages": pages}


func _normalize_base_url(base_url: String) -> String:
	var normalized := base_url.strip_edges()
	if normalized == "":
		return ""
	if not normalized.begins_with("http://") and not normalized.begins_with("https://"):
		normalized = "https://" + normalized
	return normalized.trim_suffix("/")
