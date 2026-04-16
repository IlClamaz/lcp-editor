@tool
extends LivingEvent
class_name AnimatedModelEvent


# Target runtime node that will execute animated-model-specific logic.
var animated_model: Living3DModelAnimated = null


func bind_animated_model(target: Living3DModelAnimated) -> AnimatedModelEvent:
	animated_model = target
	return self


func _on_environment_shown(env: LivingItem) -> void:
	_call_model("on_living_event_environment_shown", [env])


func _on_process() -> void:
	_call_model("on_living_event_process", [])


func _on_user_click() -> void:
	_call_model("on_living_event_user_click", [])


func _on_triggered(source: Variant = null) -> void:
	_call_model("on_living_event_triggered", [source])


func generate_preview() -> void:
	_call_model("on_living_event_generate_preview", [])


func _call_model(method_name: String, args: Array) -> void:
	if animated_model == null:
		return
	if not is_instance_valid(animated_model):
		return
	if not animated_model.has_method(method_name):
		return
	animated_model.callv(method_name, args)
