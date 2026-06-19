extends Node3D
class_name LivingVideo360

signal on_video_finished

## Path to the .mp4 video file
@export var video_path: String = ""
## Sphere radius — keep large so the camera is always inside
@export var sphere_radius: float = 500.0
## Start playback automatically on _ready
# @export var autoplay: bool = true
## Loop the video
# @export var loop: bool = false

var _player: VideoStreamPlayer
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D

# Flag per sapere se stiamo leggendo il file
var _is_loading: bool = false
var _play_from_start_when_ready: bool = false
var _play_when_ready: bool = false

func _can_play_in_current_context() -> bool:
	return not Engine.is_editor_hint()

func _ready() -> void:
	_build_sphere()
	if video_path != "":
		_init_video_async()


func _build_sphere() -> void:
	# VideoStreamPlayer nascosto e collegato al loop
	_player = VideoStreamPlayer.new()
	_player.name = "VideoStreamPlayer"
	_player.visible = false
	_player.finished.connect(_on_video_finished) 
	add_child(_player)

	# Materiale blindato per VR (No Nebbia, sRGB forzato, Opaco)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	_material.albedo_texture_force_srgb = true

	var sphere := SphereMesh.new()
	sphere.radius = sphere_radius
	sphere.height = sphere_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	sphere.flip_faces = true
	sphere.surface_set_material(0, _material)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Sphere360Mesh"
	_mesh_instance.mesh = sphere
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.extra_cull_margin = sphere_radius
	add_child(_mesh_instance)


func _init_video_async() -> void:
	if not is_inside_tree():
		return
	
	# Richiede il caricamento del file su un Thread separato (Zero scatti in VR!)
	ResourceLoader.load_threaded_request(video_path)
	_is_loading = true


func _process(_delta: float) -> void:
	# Controlla silenziosamente ogni frame a che punto è il caricamento
	if _is_loading:
		var status = ResourceLoader.load_threaded_get_status(video_path)
		
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			# Il video è pronto! Lo prendiamo e lo applichiamo.
			_is_loading = false
			var stream = ResourceLoader.load_threaded_get(video_path)
			_apply_loaded_video(stream)
			
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_is_loading = false
			push_error("LivingVideo360: Impossibile caricare il video da '%s'" % video_path)


func _apply_loaded_video(stream) -> void:
	_player.stream = stream

	var from_start := _play_from_start_when_ready
	var pending_play := _play_when_ready
	_play_from_start_when_ready = false
	_play_when_ready = false

	var should_continue := from_start or pending_play # or autoplay

	if _can_play_in_current_context():
		if from_start:
			_player.stream_position = 0.0
		_player.paused = false
		_player.play()

	# Aspetta un frame affinché FFmpeg generi la prima immagine
	await get_tree().process_frame

	var tex: Texture2D = _player.get_video_texture()
	if tex == null:
		push_error("LivingVideo360: get_video_texture() returned null")
		return

	_material.albedo_texture = tex

	if not should_continue or not _can_play_in_current_context():
		_player.stop()


func _on_video_finished() -> void:
	on_video_finished.emit()
	# if loop and _can_play_in_current_context():
		# _player.play()


# --- Public API ---

func play() -> void:
	if not _can_play_in_current_context():
		return
	if _player.stream == null:
		_request_play_when_ready(false)
		return
	_player.paused = false
	_player.play()


func play_from_start() -> void:
	if not _can_play_in_current_context():
		return
	if _player.stream == null:
		_request_play_when_ready(true)
		return
	_player.stream_position = 0.0
	_player.paused = false
	_player.play()


func _request_play_when_ready(from_start: bool) -> void:
	if video_path.is_empty():
		push_warning("LivingVideo360: play ignored — video not loaded yet.")
		return
	if from_start:
		_play_from_start_when_ready = true
		_play_when_ready = false
	else:
		if not _play_from_start_when_ready:
			_play_when_ready = true
	if not _is_loading:
		_init_video_async()


func pause() -> void:
	if not _can_play_in_current_context():
		return
	_player.paused = true


func resume() -> void:
	if not _can_play_in_current_context():
		return
	if _player.stream == null:
		_request_play_when_ready(false)
		return
	_player.paused = false
	if not _player.is_playing():
		_player.play()


func stop() -> void:
	_play_from_start_when_ready = false
	_play_when_ready = false
	_player.paused = false
	_player.stop()


func toggle_pause() -> void:
	if _can_play_in_current_context():
		_player.paused = not _player.paused


func is_playing() -> bool:
	return _player.is_playing()


func is_paused() -> bool:
	return _player.paused
