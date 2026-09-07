@tool
extends LivingObject
class_name LivingVideo360Object

# Typed parent for Omeka "Video360". Sphere media + shared playback preview controls.
# Dock has no Appearance/Behavior for Video360; radius stays under APPEARANCE in inspector.

@export_group("APPEARANCE")
@export var sphere_radius: float = 500.0 :
	set(v):
		sphere_radius = max(v, 0.1)
		if not is_inside_tree():
			return
		apply_video360_settings()

@export_group("VIDEO PREVIEW")
@export_tool_button("Play Video") var play_video_btn = play_video_preview
@export_tool_button("Toggle Pause") var toggle_pause_btn = toggle_pause_preview
@export_tool_button("Stop Video") var stop_video_btn = stop_video_preview


func _ready() -> void:
	super._ready()
	call_deferred("apply_video360_settings")


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	apply_video360_settings()


func get_living_video360_child() -> LivingVideo360:
	for child in get_children():
		if child is LivingVideo360:
			return child as LivingVideo360
	return null


func build_video360_settings() -> Dictionary:
	return {
		"sphere_radius": sphere_radius,
	}


func apply_video360_settings() -> void:
	var video_child := get_living_video360_child()
	if video_child == null:
		return
	video_child.apply_settings(build_video360_settings())


func play_video_preview() -> void:
	apply_video360_settings()
	var video_child := get_living_video360_child()
	if video_child == null:
		push_warning("LivingVideo360Object: nessun figlio LivingVideo360 — usa 'Instantiate Media'.")
		return
	video_child.play()


func toggle_pause_preview() -> void:
	var video_child := get_living_video360_child()
	if video_child == null:
		return
	video_child.toggle_pause()


func stop_video_preview() -> void:
	var video_child := get_living_video360_child()
	if video_child == null:
		return
	video_child.stop()
