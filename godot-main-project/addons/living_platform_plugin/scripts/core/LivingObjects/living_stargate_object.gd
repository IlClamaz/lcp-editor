@tool
extends LivingObject
class_name LivingStargateObject

# Typed parent for Omeka "Stargate". Curator settings live here and are applied to the LivingStargate child.
# Groups mirror curator dock: APPEARANCE (caption), BEHAVIOR (destinations). Colors stay under Appearance.

@export_group("APPEARANCE")
@export var stargate_caption_text: String = "Stargate to..." :
	set(v):
		stargate_caption_text = v
		if not is_inside_tree():
			return
		apply_stargate_settings()
@export var stargate_caption_scale: float = 3.0 :
	set(v):
		stargate_caption_scale = v
		if not is_inside_tree():
			return
		apply_stargate_settings()
@export var stargate_caption_position_y: float = 1.7 :
	set(v):
		stargate_caption_position_y = v
		if not is_inside_tree():
			return
		apply_stargate_settings()
@export var color_active: Color = Color(1.0, 0.6, 0.0) :
	set(v):
		color_active = v
		if not is_inside_tree():
			return
		apply_stargate_settings()
@export var color_inactive: Color = Color(0.55, 0.55, 0.55) :
	set(v):
		color_inactive = v
		if not is_inside_tree():
			return
		apply_stargate_settings()
@export var color_used: Color = Color(1.0, 0.25, 0.2) :
	set(v):
		color_used = v
		if not is_inside_tree():
			return
		apply_stargate_settings()

@export_group("BEHAVIOR")
@export var target_environment_id: int = 0 :
	set(v):
		target_environment_id = v
		if not is_inside_tree():
			return
		apply_stargate_settings()
@export var use_scene_path: bool = false :
	set(v):
		use_scene_path = v
		if not is_inside_tree():
			return
		apply_stargate_settings()
@export var target_scene_path: String = "" :
	set(v):
		target_scene_path = v
		if not is_inside_tree():
			return
		apply_stargate_settings()


func _ready() -> void:
	super._ready()
	call_deferred("apply_stargate_settings")


func _validate_property(property: Dictionary) -> void:
	var hidden := ["show_caption"]
	if property.name in hidden:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	apply_stargate_settings()


func get_living_stargate_child() -> LivingStargate:
	for child in get_children():
		if child is LivingStargate:
			return child as LivingStargate
	return null


func build_stargate_settings() -> Dictionary:
	return {
		"target_environment_id": target_environment_id,
		"use_scene_path": use_scene_path,
		"target_scene_path": target_scene_path,
		"color_active": color_active,
		"color_inactive": color_inactive,
		"color_used": color_used,
		"stargate_caption_text": stargate_caption_text,
		"stargate_caption_scale": stargate_caption_scale,
		"stargate_caption_position_y": stargate_caption_position_y,
	}


func apply_stargate_settings() -> void:
	var stargate_child := get_living_stargate_child()
	if stargate_child == null:
		return
	stargate_child.apply_settings(build_stargate_settings())
