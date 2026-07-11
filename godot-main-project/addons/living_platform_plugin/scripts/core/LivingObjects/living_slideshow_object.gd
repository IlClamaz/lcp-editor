@tool
extends LivingFlatMediaObject
class_name LivingSlideShowObject

# Typed parent for Omeka "Slideshow".

@export_group("SLIDESHOW")
@export var loop_slides: bool = true :
	set(v):
		loop_slides = v
		if not is_inside_tree():
			return
		apply_slideshow_settings()
@export var slide_transition_enabled: bool = true :
	set(v):
		slide_transition_enabled = v
		if not is_inside_tree():
			return
		apply_slideshow_settings()
@export_range(0.05, 2.0, 0.01) var slide_transition_duration: float = 0.45 :
	set(v):
		slide_transition_duration = v
		if not is_inside_tree():
			return
		apply_slideshow_settings()
@export_range(0.0, 1.0, 0.01) var slide_transition_fade_min_alpha: float = 0.25 :
	set(v):
		slide_transition_fade_min_alpha = v
		if not is_inside_tree():
			return
		apply_slideshow_settings()
@export var auto_hide_source_elements: bool = true :
	set(v):
		auto_hide_source_elements = v
		if not is_inside_tree():
			return
		apply_slideshow_settings()
@export_range(-5.0, 0.0, 0.01) var controls_offset_y: float = -1.5 :
	set(v):
		controls_offset_y = clampf(v, -5.0, 0.0)
		if not is_inside_tree():
			return
		apply_slideshow_settings()


func _ready() -> void:
	super._ready()
	call_deferred("apply_slideshow_settings")


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	apply_slideshow_settings()


func get_living_slideshow_child() -> LivingSlideShow:
	for child in get_children():
		if child is LivingSlideShow:
			return child as LivingSlideShow
	return null


func build_slideshow_settings() -> Dictionary:
	return {
		"loop_slides": loop_slides,
		"slide_transition_enabled": slide_transition_enabled,
		"slide_transition_duration": slide_transition_duration,
		"slide_transition_fade_min_alpha": slide_transition_fade_min_alpha,
		"auto_hide_source_elements": auto_hide_source_elements,
		"controls_offset_y": controls_offset_y,
	}


func apply_slideshow_settings() -> void:
	var slideshow_child := get_living_slideshow_child()
	if slideshow_child == null:
		return
	slideshow_child.apply_settings(build_slideshow_settings())
