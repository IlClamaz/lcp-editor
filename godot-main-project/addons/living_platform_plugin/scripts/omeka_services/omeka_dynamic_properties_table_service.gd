@tool
extends RefCounted
class_name OmekaDynamicPropertiesTableService

# Fetches Omeka items of type lcp_form-event:Table_of_dynamic_properties (state-variable lookup rows).

var _query: OmekaQueryService


func _init(query: OmekaQueryService = null) -> void:
	_query = query if query != null else OmekaQueryService.new()


# Returns all dynamic-property table rows from Omeka (no environment filter).
# Shape: { "ok": bool, "properties": Array[Dictionary], "pages": int, "error": String? }
func fetch_all_tables(host: Node, base_url: String) -> Dictionary:
	if host == null:
		return {"ok": false, "error": "Invalid host"}

	# Rows always link a participatory item via has_item_of_state_variable_f; narrow the search server-side.
	var query_suffix := (
		"property[0][property]=%s&property[0][type]=ex"
		% LivingConstants.OMEKA_KEY_ITEM_OF_STATE_VARIABLE
	)
	var search_result := await _query.search_items(host, base_url, query_suffix)
	if not search_result.get("ok", false):
		return search_result

	var normalized: Array[Dictionary] = []
	for raw_item in search_result.get("items", []):
		if typeof(raw_item) != TYPE_DICTIONARY:
			continue
		if not _is_table_item(raw_item):
			continue
		normalized.append(_normalize_table(raw_item))

	return {
		"ok": true,
		"properties": normalized,
		"pages": int(search_result.get("pages", 1))
	}


# Prints a human-readable summary of normalized property tables to the console.
func print_properties_to_console(properties: Array) -> void:
	print("Omeka dynamic property tables: %d row(s)." % properties.size())
	if properties.is_empty():
		return

	for entry in properties:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var table_id := int(entry.get(LivingConstants.OMEKA_META_DYNAMIC_TABLE_ID, 0))
		var title := str(entry.get(LivingConstants.OMEKA_META_DYNAMIC_TABLE_TITLE, "No Title"))
		var linked_item_id := int(entry.get(LivingConstants.OMEKA_META_ITEM_OF_STATE_VARIABLE_ID, 0))
		var variable_names = entry.get(LivingConstants.OMEKA_META_VARIABLE_NAMES, [])
		print(" - Table #%d | %s" % [table_id, title])
		print("   item_of_state_variable_id=%d | variable_names=%s" % [linked_item_id, str(variable_names)])


# Writes normalized rows to a JSON file under the project (res:// path).
# Returns { "ok": bool, "path": String, "error": String? }
func save_properties_to_json_file(properties: Array, json_path: String = LivingConstants.STATE_JSON_PATH) -> Dictionary:
	var payload := {
		"properties": properties
	}
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"path": json_path,
			"error": "Cannot write file: %s" % json_path
		}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return {"ok": true, "path": json_path}


func _is_table_item(item: Dictionary) -> bool:
	var types = item.get("@type", [])
	return typeof(types) == TYPE_ARRAY and LivingConstants.OMEKA_KEY_DYNAMIC_PROPERTIES_TABLE_TYPE in types


func _normalize_table(item: Dictionary) -> Dictionary:
	return {
		LivingConstants.OMEKA_META_DYNAMIC_TABLE_ID: int(item.get(LivingConstants.OMEKA_KEY_ID, 0)),
		LivingConstants.OMEKA_META_DYNAMIC_TABLE_TITLE: str(item.get(LivingConstants.OMEKA_KEY_TITLE, LivingConstants.OMEKA_DEFAULT_ITEM_TITLE)),
		LivingConstants.OMEKA_META_ITEM_OF_STATE_VARIABLE_ID: _first_resource_id(item, LivingConstants.OMEKA_KEY_ITEM_OF_STATE_VARIABLE),
		LivingConstants.OMEKA_META_VARIABLE_NAMES: _all_literals(item, LivingConstants.OMEKA_KEY_VARIABLE_NAME),
	}


func _first_resource_id(item: Dictionary, key: String) -> int:
	var values = item.get(key, [])
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return 0
	var first = values[0]
	if typeof(first) != TYPE_DICTIONARY:
		return 0
	return int(first.get("value_resource_id", 0))


func _all_literals(item: Dictionary, key: String) -> Array[String]:
	var out: Array[String] = []
	var values = item.get(key, [])
	if typeof(values) != TYPE_ARRAY:
		return out
	for entry in values:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var text := str(entry.get("@value", "")).strip_edges()
		if text != "" and not out.has(text):
			out.append(text)
	return out
