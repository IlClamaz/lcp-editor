@tool
extends RefCounted
class_name OmekaTreePrefetcher

# Prefetches a full Omeka item tree (environment → areas → components) into memory.
# Does not create scene nodes. Used as Fase 0 before typed instantiation.
# Omeka JSON field names live in LivingConstants; this class maps them to friendly meta.

signal progress(fetched: int, queued: int)

var _query: OmekaQueryService


func _init(query: OmekaQueryService = null) -> void:
	_query = query if query != null else OmekaQueryService.new()


# Walks the Omeka graph BFS from root_id following components + areas.
# If target_item_set_id is -1, it auto-detects from the root environment:
# - If root belongs to an item-set, only children belonging to that same item-set are kept.
# - If root has NO item-set (None), only children with NO item-set are kept.
# Returns:
# { "ok": bool, "tree": Dictionary, "root_id": int, "error": String?, "tree_partial": Dictionary? }
# tree[id] = parse_item_metadata(...)  — friendly fields only, no raw Omeka JSON
func prefetch_tree(host: Node, base_url: String, root_id: int, target_item_set_id: int = -1) -> Dictionary:
	if host == null:
		return {"ok": false, "error": "Invalid host", "root_id": root_id, "tree": {}}
	if root_id <= 0:
		return {"ok": false, "error": "Invalid root id", "root_id": root_id, "tree": {}}

	var tree: Dictionary = {}
	var queue: Array[int] = [root_id]
	var queued_seen: Dictionary = {root_id: true}
	var active_target_set_id: int = target_item_set_id

	while not queue.is_empty():
		var item_id: int = queue.pop_front()
		if tree.has(item_id):
			continue

		progress.emit(tree.size(), queue.size())

		var result := await _query.get_item_by_id(host, base_url, item_id)
		if not result.get("ok", false):
			var err := str(result.get("error", "Failed to fetch item %d" % item_id))
			return {
				"ok": false,
				"error": "Item %d: %s" % [item_id, err],
				"root_id": root_id,
				"tree": {},
				"tree_partial": tree.duplicate(true),
			}

		var item_dict: Dictionary = result.get("item", {})

		# Determine active item-set filter from root environment if not explicitly specified
		if item_id == root_id:
			if target_item_set_id < 0:
				var root_sets := _extract_item_set_ids(item_dict)
				if root_sets.is_empty():
					active_target_set_id = 0 # None (no item set)
				else:
					active_target_set_id = root_sets[0]
			print(
				"OmekaTreePrefetcher: Root environment %d active item-set filter: %s"
				% [root_id, "None (no item set)" if active_target_set_id == 0 else ("ItemSet %d" % active_target_set_id)]
			)
		else:
			# Child item (component or area): verify item-set match
			var child_sets := _extract_item_set_ids(item_dict)
			var matches_filter := false

			if active_target_set_id > 0:
				matches_filter = child_sets.has(active_target_set_id)
			else:
				# active_target_set_id == 0 (None): must NOT belong to any item-set
				matches_filter = child_sets.is_empty()

			if not matches_filter:
				var item_title: String = str(item_dict.get("o:title", "Item %d" % item_id))
				if active_target_set_id > 0:
					print(
						"OmekaTreePrefetcher: Skipping child '%s' (id %d) — not in item-set %d (has %s)."
						% [item_title, item_id, active_target_set_id, str(child_sets)]
					)
				else:
					print(
						"OmekaTreePrefetcher: Skipping child '%s' (id %d) — has item-sets %s, but environment is in None."
						% [item_title, item_id, str(child_sets)]
					)
				continue

		var meta := parse_item_metadata(item_dict)
		tree[item_id] = meta

		for child_id in meta[LivingConstants.OMEKA_META_COMPONENTS]:
			_enqueue_if_needed(child_id, queue, queued_seen)
		for area_id in meta[LivingConstants.OMEKA_META_AREAS]:
			_enqueue_if_needed(area_id, queue, queued_seen)

		progress.emit(tree.size(), queue.size())

	# Post-processing: remove filtered-out children from parent components and areas arrays
	for id in tree.keys():
		var m: Dictionary = tree[id]
		var valid_components: Array[int] = []
		for cid in m.get(LivingConstants.OMEKA_META_COMPONENTS, []):
			if tree.has(cid):
				valid_components.append(cid)
		m[LivingConstants.OMEKA_META_COMPONENTS] = valid_components

		var valid_areas: Array[int] = []
		for aid in m.get(LivingConstants.OMEKA_META_AREAS, []):
			if tree.has(aid):
				valid_areas.append(aid)
		m[LivingConstants.OMEKA_META_AREAS] = valid_areas

	return {"ok": true, "tree": tree, "root_id": root_id}


# Parses one Omeka item JSON into the friendly meta shape consumed by LivingItem.
# Public so single-item HTTP fallback can reuse the same mapping.
func parse_item_metadata(item_dict: Dictionary) -> Dictionary:
	var components: Array[int] = []
	for comp in item_dict.get(LivingConstants.OMEKA_KEY_COMPONENTS, []):
		if typeof(comp) != TYPE_DICTIONARY:
			continue
		var cid := int(comp.get(LivingConstants.OMEKA_KEY_VALUE_RESOURCE_ID, 0))
		if cid > 0:
			components.append(cid)

	var areas: Array[int] = []
	for a in item_dict.get(LivingConstants.OMEKA_KEY_AREAS, []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var aid := int(a.get(LivingConstants.OMEKA_KEY_VALUE_RESOURCE_ID, 0))
		if aid > 0:
			areas.append(aid)

	var medium_uri := ""
	var uri_field = item_dict.get(LivingConstants.OMEKA_KEY_URI, null)
	if typeof(uri_field) == TYPE_ARRAY and not uri_field.is_empty():
		var mu = uri_field[0].get(LivingConstants.OMEKA_KEY_AT_ID)
		if mu != null:
			medium_uri = str(mu)

	var thumbnail_uri := ""
	var thumbs = item_dict.get(LivingConstants.OMEKA_KEY_THUMBNAIL_DISPLAY_URLS, null)
	if typeof(thumbs) == TYPE_DICTIONARY:
		var tu = thumbs.get(LivingConstants.OMEKA_KEY_THUMBNAIL_SQUARE)
		if tu != null:
			thumbnail_uri = str(tu)

	var resource_class_id := 0
	var resource_class = item_dict.get(LivingConstants.OMEKA_KEY_RESOURCE_CLASS, null)
	if typeof(resource_class) == TYPE_DICTIONARY:
		resource_class_id = int(resource_class.get(LivingConstants.OMEKA_KEY_ID, 0))

	var modified := ""
	var modified_field = item_dict.get(LivingConstants.OMEKA_KEY_MODIFIED, {})
	if typeof(modified_field) == TYPE_DICTIONARY:
		modified = str(modified_field.get(LivingConstants.OMEKA_KEY_AT_VALUE, ""))

	return {
		LivingConstants.OMEKA_META_ITEM_ID: int(item_dict.get(LivingConstants.OMEKA_KEY_ID, 0)),
		LivingConstants.OMEKA_META_TITLE: str(item_dict.get(LivingConstants.OMEKA_KEY_TITLE, LivingConstants.OMEKA_DEFAULT_ITEM_TITLE)),
		LivingConstants.OMEKA_META_MODIFIED: modified,
		LivingConstants.OMEKA_META_SHORT_DESCRIPTION: _get_omeka_text(item_dict, LivingConstants.OMEKA_KEY_SHORT_TEXT),
		LivingConstants.OMEKA_META_LONG_DESCRIPTION: _get_omeka_text(item_dict, LivingConstants.OMEKA_KEY_LONG_TEXT),
		LivingConstants.OMEKA_META_CATALOG_DESCRIPTION: _get_omeka_text(item_dict, LivingConstants.OMEKA_KEY_CATALOGUE_TEXT),
		LivingConstants.OMEKA_META_RESOURCE_CLASS: resource_class_id,
		LivingConstants.OMEKA_META_PARTICIPATORY_ITEM_TYPE: _get_omeka_text(item_dict, LivingConstants.OMEKA_KEY_PARTICIPATORY_ITEM_TYPE),
		LivingConstants.OMEKA_META_COMPONENTS: components,
		LivingConstants.OMEKA_META_AREAS: areas,
		LivingConstants.OMEKA_META_MEDIUM_URI: medium_uri,
		LivingConstants.OMEKA_META_THUMBNAIL_URI: thumbnail_uri,
		"item_sets": _extract_item_set_ids(item_dict),
	}


func _extract_item_set_ids(item_dict: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var raw = item_dict.get("o:item_set", [])
	if typeof(raw) == TYPE_ARRAY:
		for entry in raw:
			if typeof(entry) == TYPE_DICTIONARY:
				var sid := int(entry.get("o:id", entry.get("id", 0)))
				if sid > 0 and not out.has(sid):
					out.append(sid)
	return out


func _enqueue_if_needed(id: int, queue: Array[int], queued_seen: Dictionary) -> void:
	if id <= 0:
		return
	if queued_seen.has(id):
		return
	queued_seen[id] = true
	queue.append(id)


func _get_omeka_text(item_dict: Dictionary, key: String) -> String:
	if not item_dict.has(key):
		return ""
	var arr = item_dict[key]
	if typeof(arr) != TYPE_ARRAY or arr.is_empty() or typeof(arr[0]) != TYPE_DICTIONARY:
		return ""
	return str(arr[0].get(LivingConstants.OMEKA_KEY_AT_VALUE, ""))
