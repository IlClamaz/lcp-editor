@tool
extends AudioStreamPlayer3D
class_name LivingAudio

## Runtime path set by the parent during medium instantiation (not saved in clean scenes).
var audio_path: String = ""

var _configured_loop: bool = false


func set_audio_path(path: String) -> void:
	audio_path = path
	if path == "" or not ResourceLoader.exists(path):
		stream = null
		return
	_apply_stream(load(path) as AudioStream)


func apply_settings(settings: Dictionary) -> void:
	if settings.has("autoplay"):
		autoplay = bool(settings["autoplay"])
	if settings.has("volume_db"):
		volume_db = float(settings["volume_db"])
	if settings.has("pitch_scale"):
		pitch_scale = float(settings["pitch_scale"])
	if settings.has("unit_size"):
		unit_size = float(settings["unit_size"])
	if settings.has("max_distance"):
		max_distance = float(settings["max_distance"])
	if settings.has("max_polyphony"):
		max_polyphony = int(settings["max_polyphony"])
	if settings.has("panning_strength"):
		panning_strength = float(settings["panning_strength"])
	if settings.has("bus"):
		bus = StringName(str(settings["bus"]))
	if settings.has("area_mask"):
		area_mask = int(settings["area_mask"])
	if settings.has("attenuation_filter_cutoff_hz"):
		attenuation_filter_cutoff_hz = float(settings["attenuation_filter_cutoff_hz"])
	if settings.has("attenuation_filter_db"):
		attenuation_filter_db = float(settings["attenuation_filter_db"])
	if settings.has("loop"):
		_configured_loop = bool(settings["loop"])
		if stream != null:
			_apply_loop_to_stream(stream)


func _apply_stream(loaded_stream: AudioStream) -> void:
	stream = loaded_stream
	if stream != null:
		_apply_loop_to_stream(stream)


func _apply_loop_to_stream(loaded_stream: AudioStream) -> void:
	if loaded_stream is AudioStreamOggVorbis:
		(loaded_stream as AudioStreamOggVorbis).loop = _configured_loop
	elif loaded_stream is AudioStreamWAV:
		var wav := loaded_stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if _configured_loop else AudioStreamWAV.LOOP_DISABLED
