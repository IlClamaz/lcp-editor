@tool
extends LivingEvent
class_name CrowdEvent


# Target runtime node that will execute crowd-specific logic.
var crowd: LivingCrowd = null


func bind_crowd(target: LivingCrowd) -> CrowdEvent:
	crowd = target
	return self


func _on_environment_shown(env: LivingItem) -> void:
	_call_crowd("on_living_event_environment_shown", [env])


func _on_process() -> void:
	_call_crowd("on_living_event_process", [])


func _on_user_click() -> void:
	_call_crowd("on_living_event_user_click", [])


func _on_triggered(source: Variant = null) -> void:
	_call_crowd("on_living_event_triggered", [source])


func generate_preview() -> void:
	_call_crowd("on_living_event_generate_preview", [])


func _call_crowd(method_name: String, args: Array) -> void:
	if crowd == null:
		return
	if not is_instance_valid(crowd):
		return
	if not crowd.has_method(method_name):
		return
	crowd.callv(method_name, args)
