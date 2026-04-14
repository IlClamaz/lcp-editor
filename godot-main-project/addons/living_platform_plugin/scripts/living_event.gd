@tool
extends RefCounted
class_name LivingEvent


var origin_id: int = 0
var originEPD: LivingItem = null
var origin_state: String = ""
var destEPD: LivingItem = null
var dest_state: String = ""


func matches_environment(env: LivingItem) -> bool:
	if env == null:
		return originEPD != null or destEPD != null
	return env == originEPD or env == destEPD


func clicks_origin() -> bool:
	return origin_id > 0 or originEPD != null


func matches_trigger_source(source: Variant) -> bool:
	var source_id := _resolve_source_id(source)
	if source_id <= 0:
		return false

	if origin_id > 0 and origin_id == source_id:
		return true

	if originEPD != null and originEPD.item_id == source_id:
		return true

	if destEPD != null and destEPD.item_id == source_id:
		return true

	return false


func _resolve_source_id(source: Variant) -> int:
	if source is int:
		return int(source)
	if source is LivingPortal:
		return int((source as LivingPortal).target_environment_id)
	if source is LivingItem:
		return int((source as LivingItem).item_id)
	return 0


func _on_environment_shown(_env: LivingItem) -> void:
	pass


func _on_process() -> void:
	pass


func _on_user_click() -> void:
	pass


func _on_triggered(_source: Variant = null) -> void:
	pass


func generate_preview() -> void:
	pass