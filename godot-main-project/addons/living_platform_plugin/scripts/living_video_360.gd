extends Node3D
class_name LivingVideo360

## Path to the .mp4 video file
@export var video_path: String = ""
## Sphere radius — keep large so the camera is always inside
@export var sphere_radius: float = 500.0
## Start playback automatically on _ready
@export var autoplay: bool = true
## Loop the video
@export var loop: bool = true

var _player: VideoStreamPlayer
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D

# Flag per sapere se stiamo leggendo il file
var _is_loading: bool = false

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
	_player.play()

	# Aspetta un frame affinché FFmpeg generi la prima immagine
	await get_tree().process_frame

	var tex: Texture2D = _player.get_video_texture()
	if tex == null:
		push_error("LivingVideo360: get_video_texture() returned null")
		return

	_material.albedo_texture = tex

	if not autoplay:
		_player.stop()


func _on_video_finished() -> void:
	if loop:
		_player.play()


# --- Public API ---
func play() -> void:
	_player.play()

func stop() -> void:
	_player.stop()

func toggle_pause() -> void:
	_player.paused = not _player.paused

func is_playing() -> bool:
	return _player.is_playing()

func seek(position_sec: float) -> void:
	_player.stream_position = position_sec
