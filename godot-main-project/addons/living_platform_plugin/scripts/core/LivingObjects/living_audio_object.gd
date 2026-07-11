@tool
extends LivingObject
class_name LivingAudioObject

@export_group("AUDIO")
@export var autoplay: bool = false :
	set(v):
		autoplay = v
		if not is_inside_tree():
			return
		apply_audio_settings()
@export_range(-80.0, 24.0, 0.1) var volume_db: float = 0.0 :
	set(v):
		volume_db = v
		if not is_inside_tree():
			return
		apply_audio_settings()
@export_range(0.01, 4.0, 0.01) var pitch_scale: float = 1.0 :
	set(v):
		pitch_scale = max(v, 0.01)
		if not is_inside_tree():
			return
		apply_audio_settings()
@export_range(0.1, 100.0, 0.1) var unit_size: float = 10.0 :
	set(v):
		unit_size = max(v, 0.1)
		if not is_inside_tree():
			return
		apply_audio_settings()
@export_range(0.0, 4096.0, 0.1) var max_distance: float = 0.0 :
	set(v):
		max_distance = max(v, 0.0)
		if not is_inside_tree():
			return
		apply_audio_settings()
@export_range(1, 32, 1) var max_polyphony: int = 1 :
	set(v):
		max_polyphony = maxi(v, 1)
		if not is_inside_tree():
			return
		apply_audio_settings()
@export_range(0.0, 1.0, 0.01) var panning_strength: float = 1.0 :
	set(v):
		panning_strength = clampf(v, 0.0, 1.0)
		if not is_inside_tree():
			return
		apply_audio_settings()
@export var bus: String = "Master" :
	set(v):
		bus = v
		if not is_inside_tree():
			return
		apply_audio_settings()
@export_flags("Layer 1", "Layer 2", "Layer 3", "Layer 4", "Layer 5", "Layer 6", "Layer 7", "Layer 8", "Layer 9", "Layer 10", "Layer 11", "Layer 12", "Layer 13", "Layer 14", "Layer 15", "Layer 16", "Layer 17", "Layer 18", "Layer 19", "Layer 20") var area_mask: int = 1 :
	set(v):
		area_mask = v
		if not is_inside_tree():
			return
		apply_audio_settings()
@export_range(10.0, 20000.0, 1.0) var attenuation_filter_cutoff_hz: float = 5000.0 :
	set(v):
		attenuation_filter_cutoff_hz = v
		if not is_inside_tree():
			return
		apply_audio_settings()
@export_range(-80.0, 0.0, 0.1) var attenuation_filter_db: float = -24.0 :
	set(v):
		attenuation_filter_db = v
		if not is_inside_tree():
			return
		apply_audio_settings()
@export var loop: bool = false :
	set(v):
		loop = v
		if not is_inside_tree():
			return
		apply_audio_settings()

@export_group("AUDIO PREVIEW")
@export_tool_button("Play Audio") var play_audio_btn = play_audio_preview
@export_tool_button("Stop Audio") var stop_audio_btn = stop_audio_preview


func _ready() -> void:
	super._ready()
	call_deferred("apply_audio_settings")


func _validate_property(property: Dictionary) -> void:
	var hidden := ["triggers_enabled"]
	if property.name in hidden:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	apply_audio_settings()


func get_living_audio_child() -> LivingAudio:
	for child in get_children():
		if child is LivingAudio:
			return child as LivingAudio
	return null


func build_audio_settings() -> Dictionary:
	return {
		"autoplay": autoplay,
		"volume_db": volume_db,
		"pitch_scale": pitch_scale,
		"unit_size": unit_size,
		"max_distance": max_distance,
		"max_polyphony": max_polyphony,
		"panning_strength": panning_strength,
		"bus": bus,
		"area_mask": area_mask,
		"attenuation_filter_cutoff_hz": attenuation_filter_cutoff_hz,
		"attenuation_filter_db": attenuation_filter_db,
		"loop": loop,
	}


func apply_audio_settings() -> void:
	var audio_child := get_living_audio_child()
	if audio_child == null:
		return
	audio_child.apply_settings(build_audio_settings())
	if media_path != "" and audio_child.audio_path != media_path:
		audio_child.set_audio_path(media_path)


func play_audio_preview() -> void:
	apply_audio_settings()
	var audio_child := get_living_audio_child()
	if audio_child == null:
		push_warning("LivingAudioObject: nessun figlio LivingAudio — usa 'Instantiate Media' o aggiungi il figlio.")
		return
	if audio_child.stream == null and media_path != "":
		audio_child.set_audio_path(media_path)
	if audio_child.stream == null:
		push_warning("LivingAudioObject: nessuno stream audio caricato.")
		return
	audio_child.play()


func stop_audio_preview() -> void:
	var audio_child := get_living_audio_child()
	if audio_child != null:
		audio_child.stop()
