@tool
extends RefCounted
class_name CuratorOmekaCatalog

## Omeka catalog reads: environment list + dynamic property tables.
## No UI.

var environments_service := OmekaEnvironmentsService.new()
var dynamic_properties_service := OmekaDynamicPropertiesTableService.new()


func list_environments(host: Node, base_url: String, item_set_id: int = 0) -> Dictionary:
	return await environments_service.list_environments(host, base_url, item_set_id)


func list_item_sets(host: Node, base_url: String) -> Dictionary:
	return await environments_service.list_item_sets(host, base_url)


func fetch_and_save_dynamic_properties(host: Node, base_url: String, editor_interface: EditorInterface) -> Dictionary:
	if base_url.strip_edges() == "":
		return {"ok": false, "error": "Omeka URL is empty"}

	var fetch_result: Dictionary = await dynamic_properties_service.fetch_all_tables(host, base_url)
	if not fetch_result.get("ok", false):
		return fetch_result

	var properties: Array = fetch_result.get("properties", [])
	dynamic_properties_service.print_properties_to_console(properties)

	var save_result: Dictionary = dynamic_properties_service.save_properties_to_json_file(
		properties,
		LivingConstants.STATE_JSON_PATH
	)
	if not save_result.get("ok", false):
		return save_result

	if editor_interface != null:
		var fs = editor_interface.get_resource_filesystem()
		if fs != null:
			fs.update_file(LivingConstants.STATE_JSON_PATH)

	return {
		"ok": true,
		"count": properties.size(),
		"path": LivingConstants.STATE_JSON_PATH,
	}
