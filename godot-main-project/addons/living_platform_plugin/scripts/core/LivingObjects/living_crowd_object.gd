@tool
extends LivingObject
class_name LivingCrowdObject

# Typed parent for Omeka "Crowd". Curator density lives here and is applied to LivingCrowd.

@export_group("CROWD")
@export_range(1, 40, 1) var density: int = 20 :
	set(v):
		density = clampi(v, 1, 40)
		if not is_inside_tree():
			return
		apply_crowd_settings()


func _ready() -> void:
	super._ready()
	call_deferred("apply_crowd_settings")


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	await get_tree().process_frame
	apply_crowd_settings()


func get_living_crowd_child() -> LivingCrowd:
	for child in get_children():
		if child is LivingCrowd:
			return child as LivingCrowd
	return null


func build_crowd_settings() -> Dictionary:
	return {
		"density": density,
	}


func apply_crowd_settings() -> void:
	var crowd_child := get_living_crowd_child()
	if crowd_child == null:
		return
	crowd_child.apply_settings(build_crowd_settings())
