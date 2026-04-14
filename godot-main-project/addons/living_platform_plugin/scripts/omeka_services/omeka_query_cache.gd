@tool
extends RefCounted
class_name OmekaQueryCache

# Shared Omeka JSON cache used by multiple services.
# This class only handles:
# - HTTP JSON fetch
# - pagination
# - in-memory cache keyed by base_url
# - item lookup by id

const PER_PAGE := 100

static var _shared_instance: OmekaQueryCache

# base_url -> { "items": Array, "pages": int }
var _all_items_cache_by_base := {}
# base_url -> { item_id: item_json }
var _item_cache_by_base := {}


static func shared() -> OmekaQueryCache:
	# Lazy singleton used by all Omeka domain services.
	if _shared_instance == null:
		_shared_instance = OmekaQueryCache.new()
	return _shared_instance


# Clear cache for one base_url, or all if base_url is empty.
func invalidate(base_url: String = "") -> void:
	# Empty input invalidates every cached base URL.
	var normalized := _normalize_base_url(base_url)
	if normalized == "":
		_all_items_cache_by_base.clear()
		_item_cache_by_base.clear()
		return
	_all_items_cache_by_base.erase(normalized)
	_item_cache_by_base.erase(normalized)


# Get full item list from cache or network.
# Return shape:
# { "ok": bool, "items": Array, "pages": int, "error": String? }
func get_all_items(host: Node, base_url: String, force_refresh: bool = false) -> Dictionary:
	# Main entry point for the "all items" snapshot used by higher-level services.
	var normalized := _normalize_base_url(base_url)
	if normalized == "":
		return {"ok": false, "error": "Invalid base URL"}
	if host == null:
		return {"ok": false, "error": "Invalid host"}

	if not force_refresh and _all_items_cache_by_base.has(normalized):
		# Fast path: serve from in-memory cache.
		var cached: Dictionary = _all_items_cache_by_base[normalized]
		return {
			"ok": true,
			"items": cached.get("items", []),
			"pages": int(cached.get("pages", 1))
		}

	var fetch_result := await _fetch_all_items_paginated(host, normalized)
	if not fetch_result.get("ok", false):
		return fetch_result

	var items: Array = fetch_result.get("items", [])
	var pages: int = int(fetch_result.get("pages", 1))
	_all_items_cache_by_base[normalized] = {"items": items, "pages": pages}

	# Pre-fill id cache with items from the list response.
	var id_cache := _get_or_create_item_cache(normalized)
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var iid := int(item.get("o:id", 0))
		if iid > 0:
			id_cache[iid] = item

	return {"ok": true, "items": items, "pages": pages}


# Get single item by id from cache or network.
# Return shape:
# { "ok": bool, "item": Dictionary, "error": String? }
func get_item_by_id(host: Node, base_url: String, item_id: int, force_refresh: bool = false) -> Dictionary:
	# Used by scope walkers and item metadata service for point lookups.
	var normalized := _normalize_base_url(base_url)
	if normalized == "":
		return {"ok": false, "error": "Invalid base URL"}
	if host == null:
		return {"ok": false, "error": "Invalid host"}
	if item_id <= 0:
		return {"ok": false, "error": "Invalid item id"}

	var id_cache := _get_or_create_item_cache(normalized)
	if not force_refresh and id_cache.has(item_id):
		# Fast path: item already cached.
		return {"ok": true, "item": id_cache[item_id]}

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

	id_cache[item_id] = item
	return {"ok": true, "item": item}


func _fetch_all_items_paginated(host: Node, normalized_base_url: String) -> Dictionary:
	# Omeka pagination loop; stops when a page has fewer than PER_PAGE items.
	var page := 1
	var pages := 1
	var all_items: Array = []

	while true:
		var api_url := "%s/api/items?per_page=%d&page=%d" % [normalized_base_url, PER_PAGE, page]
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
	# Normalization guarantees consistent cache keys.
	var normalized := base_url.strip_edges()
	if normalized == "":
		return ""
	if not normalized.begins_with("http://") and not normalized.begins_with("https://"):
		normalized = "https://" + normalized
	return normalized.trim_suffix("/")


func _get_or_create_item_cache(normalized_base_url: String) -> Dictionary:
	# Per-base-url map: item_id -> raw Omeka item dictionary.
	if not _item_cache_by_base.has(normalized_base_url):
		_item_cache_by_base[normalized_base_url] = {}
	return _item_cache_by_base[normalized_base_url]
