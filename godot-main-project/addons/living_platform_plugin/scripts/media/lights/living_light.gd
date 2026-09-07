@tool
extends Light3D
class_name LivingLight


@export var target_item: LivingObject = null

var _highlight_on_energy: float = 1.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_highlight_on_energy = light_energy
	set_highlighted(false)


func set_highlighted(on: bool) -> void:
	light_energy = _highlight_on_energy if on else 0.0
	if target_item is LivingVisitableObject:
		(target_item as LivingVisitableObject).show_caption = on
		(target_item as LivingVisitableObject).show_visit_point = on
