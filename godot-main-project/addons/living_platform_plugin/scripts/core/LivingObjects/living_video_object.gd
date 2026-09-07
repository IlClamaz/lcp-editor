@tool
extends LivingFlatMediaObject
class_name LivingVideoObject

# Typed parent for Omeka "Video". Flat geometry + shared playback preview controls.

@export_group("BEHAVIOR")
@export var auto_pause_camera_distance: float = 10.0 :
	set(v):
		auto_pause_camera_distance = v
		if not is_inside_tree():
			return
		apply_video_settings()

@export_group("VIDEO PREVIEW")
@export_tool_button("Play Video") var play_video_btn = play_video_preview
@export_tool_button("Toggle Pause") var toggle_pause_btn = toggle_pause_preview
@export_tool_button("Stop Video") var stop_video_btn = stop_video_preview


func _ready() -> void:
	super._ready()
	call_deferred("apply_video_settings")


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	apply_video_settings()


func get_living_video_child() -> LivingVideo:
	for child in get_children():
		if child is LivingVideo:
			return child as LivingVideo
	return null


func build_video_settings() -> Dictionary:
	return {
		"auto_pause_camera_distance": auto_pause_camera_distance,
	}


func apply_video_settings() -> void:
	var video_child := get_living_video_child()
	if video_child == null:
		return
	video_child.apply_settings(build_video_settings())


func play_video_preview() -> void:
	apply_video_settings()
	var video_child := get_living_video_child()
	if video_child == null:
		push_warning("LivingVideoObject: nessun figlio LivingVideo — usa 'Instantiate Media'.")
		return
	video_child.play_video()


func toggle_pause_preview() -> void:
	var video_child := get_living_video_child()
	if video_child == null:
		return
	video_child.toggle_pause()


func stop_video_preview() -> void:
	var video_child := get_living_video_child()
	if video_child == null:
		return
	video_child.stop_video()
