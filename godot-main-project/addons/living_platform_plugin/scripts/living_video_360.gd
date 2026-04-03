extends Node3D
class_name LivingVideo360

## Path to the equirectangular .ogv video file
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


func _ready() -> void:
	_build_sphere()
	if video_path != "":
		_init_video.call_deferred()


func _build_sphere() -> void:
	# VideoStreamPlayer — audio output but no display on its own
	_player = VideoStreamPlayer.new()
	_player.name = "VideoStreamPlayer"
	add_child(_player)

	# Material — unshaded so lighting doesn't tint the video
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_BACK  # flip_faces handles winding

	# Sphere mesh with inverted faces
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
	# Prevent the engine from frustum-culling the sphere when the camera is inside it
	_mesh_instance.extra_cull_margin = sphere_radius
	add_child(_mesh_instance)


func _init_video() -> void:
	if not is_inside_tree():
		return

	var stream = load(video_path)
	if not (stream is VideoStreamTheora):
		push_error("LivingVideo360: could not load VideoStreamTheora from '%s'" % video_path)
		return

	_player.stream = stream
	_player.play()

	# Wait one frame so the decoder produces the first frame and the texture is valid
	await get_tree().process_frame

	var tex: Texture2D = _player.get_video_texture()
	if tex == null:
		push_error("LivingVideo360: get_video_texture() returned null")
		return

	_material.albedo_texture = tex

	if not autoplay:
		_player.stop()


func _process(_delta: float) -> void:
	# Loop: VideoStreamPlayer has no native loop flag for Theora — restart when finished
	if loop and _player.stream != null:
		if not _player.is_playing() and _player.stream_position > 0.0:
			_player.play()


# --- Public API (mirrors LivingVideo for consistency) ---

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
