@tool
extends MeshInstance3D
class_name LivingVideo

#
# References to the hand crafted children in the hierarchy
## The surface used to render the video
@onready var viewport = $"VideoPlayer-SubViewport"
## The controls to play/pause/stop
@onready var player: VideoStreamPlayer = $"VideoPlayer-SubViewport/VideoStreamPlayer"
## The node containing the control buttons. We reposition them according to the video size.
@onready var controls_panel = $"Controls"

## The path to the video to play. Set this before inserting the node in the scene, so that the first frame will be used to show the panel in the scene.
@export var video_path: String = ""

# --- Parameter to curve the screen, set by LivingElement ---
# Positives Values (> 0) = Concave
# Negative Values (< 0) = Convex
var curve_degrees: float = 0.0 :
	set(v):
		curve_degrees = v
		if is_inside_tree() and viewport != null:
			_update_geometries()

@export var pixel_size: float = 0.01 

# Test button to play the video referenced by the parent media
@export_tool_button("Play Video") var play_video_btn = play_video
@export_tool_button("Toggle Pause") var toggle_pause_btn = toggle_pause
@export_tool_button("Stop Video") var stop_video_btn = stop_video

## This is needed to intercept collisions for ray casting
var face_collision_shape: CollisionShape3D = null
## This is needed to trigger collisions with the walking camera
var trigger_collision_shape: CollisionShape3D = null

## Minimum depth of the trigger for a video
const TRIGGER_MIN_DEPTH: float = 5.0
## Number of segments for the curved plane mesh generation
const CURVE_SEGMENTS: int = 32 


## Number of render frames to wait while the video player starts rendering a video frame on the viewport
const VIDEO_INIT_FRAMES_DELAY = 10
## Se to true only when the video preview is completely correctly initialized.
var _is_video_initialized = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	if not Engine.is_editor_hint() or player.stream != null:
		print("LivingVideo Ready. Stream Info. Type: ", typeof(player.stream), "\tStream: ", player.stream)

	# Setup of geometries
	if face_collision_shape == null:
		# front face collision
		var static_body = StaticBody3D.new()
		static_body.collision_layer = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
		static_body.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
		add_child(static_body)
		
		face_collision_shape = CollisionShape3D.new()
		face_collision_shape.name = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE
		static_body.add_child(face_collision_shape)

		# Trigger area
		var trigger_body = StaticBody3D.new()
		trigger_body.name = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_NODE
		trigger_body.collision_layer = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
		trigger_body.collision_mask = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
		trigger_collision_shape = CollisionShape3D.new()
		trigger_collision_shape.shape = BoxShape3D.new()
		trigger_body.add_child(trigger_collision_shape)
		add_child(trigger_body)

	_update_geometries()

	# Only now start decoding  few frames of the video to set the correct resolution and show a preview.
	#
	# Claude said: _enter_tree() fires top-down — the parent node enters the tree before its children do.
	# So player (the VideoStreamPlayer inside the SubViewport) is not yet in the tree when player.play() is called, triggering !is_inside_tree() in video_stream_player.cpp.
	# Fix: call_deferred() postpones _init_video_stream() to the end of the current frame, by which point all children have entered the tree and player.is_inside_tree() is true.
	_init_video_stream.call_deferred()


func _enter_tree():
	# print("VIDEO ENTER TREE. Ready: ", self.is_node_ready(), " IN TREE: ", self.is_inside_tree())

	# Tries to re-initialize the video if it failed during the ready()
	# But only if the node is "already ready"
	if self.is_node_ready():
		if not _is_video_initialized:
			print("VIDEO Calling init.")
			_init_video_stream.call_deferred()



#
# Public video control API
#

## Toggle the paused status
func toggle_pause() -> void:
	player.paused = ! player.paused

## Returns true if the player is paused
func is_paused() -> bool:
	return player.paused

## Play again the current video stream
func play_video() -> void:
	player.play()

## Stop the playback of the current video stream
func stop_video() -> void:
	player.stop()
	
## Move the playback point to the given value, expressed in percentage from 0% to 100%.
func seek_video(pct: float) -> void:
	var pct_0_1: float = clampf(pct, 0.0, 100.0) / 100.0
	var new_position: float = player.get_stream_length() * pct_0_1
	player.stream_position = new_position



#
# Private methos
#

func _init_video_stream() -> void:

	print("Initializing video player with media video '%s'" % [video_path])

	if not self.is_inside_tree():
		print("Node not in tree. Skipping init ...")
		return

	# Loads a VideoStream resource
	var stream := load(video_path)
	if stream and stream is VideoStreamTheora:
		# print("Stream size info. type: ", typeof(stream_size), stream_size)
		player.stream = stream
		var original_volume = player.volume_db
		player.volume_db = -80.0
		
		print("Video Info. Stream Name: ", player.get_stream_name(), "	Length: ", player.get_stream_length())
		
		player.play()
		
		# wait one frame to decode first frame
		await get_tree().process_frame
		var tex = player.get_video_texture()
		print("Inferred texture playback size: ", tex, " W: ", tex.get_width(), " H: ", tex.get_height())
		
		var w = tex.get_width()
		var h = tex.get_height()
		
		viewport.size = Vector2i(w, h)
		
		_update_geometries()

		# Wait some frames, so that the player is rendering the first frame.
		for i in range (VIDEO_INIT_FRAMES_DELAY):
			await get_tree().process_frame

		# Stop immediately to leave control to the API.
		stop_video()
		player.volume_db = original_volume

		# Setting this will avoid trying to reinitialize the video
		_is_video_initialized = true

	else:
		push_error("Could not load video stream: %s" % video_path)


func _update_geometries():
	if viewport == null: return
	
	var viewport_scaled_size = Vector2(viewport.size) * self.pixel_size
	var w = viewport_scaled_size.x
	var h = viewport_scaled_size.y
	
	if w <= 0 or h <= 0: return

	# 1. Screen space generation
	var screen_mesh = _generate_curved_plane(w, h, curve_degrees)
	self.mesh = screen_mesh
	
	var screen_mat = StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	screen_mat.albedo_texture = viewport.get_texture()
	screen_mat.resource_local_to_scene = true
	self.set_surface_override_material(0, screen_mat)

	if face_collision_shape != null:
		face_collision_shape.shape = screen_mesh.create_trimesh_shape()

	# 2. Trigger Area
	var trigger_depth = max(h / 2.0, TRIGGER_MIN_DEPTH)
	
	if trigger_collision_shape != null and trigger_collision_shape.shape is BoxShape3D:
		trigger_collision_shape.shape.size = Vector3(w, 0.2, trigger_depth)
		trigger_collision_shape.position = Vector3(0, 0, trigger_depth / 2.0)
		trigger_collision_shape.global_position.y = 0.1

	# 3. Control Panel
	if controls_panel != null:
		controls_panel.position.y = -h / 2.0



# Curved Plane Generation based on the curve_degrees parameter. If curve_degrees is 0, it generates a flat plane. 
# Otherwise, it generates a curved plane with the specified curvature.
func _generate_curved_plane(w: float, h: float, curve_deg: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	var is_flat = abs(curve_deg) <= 0.01
	
	var dir = -sign(curve_deg) if curve_deg != 0 else 1.0

	var angle_rad = 0.0
	var radius = 0.0

	if not is_flat:
		angle_rad = deg_to_rad(abs(curve_deg))
		radius = w / angle_rad 

	for i in range(CURVE_SEGMENTS + 1):
		var u = float(i) / CURVE_SEGMENTS
		var x: float
		var z: float
		var normal: Vector3

		if is_flat:
			x = lerp(-w / 2.0, w / 2.0, u)
			z = 0.0
			normal = Vector3(0, 0, 1)
		else:
			var current_angle = lerp(-angle_rad / 2.0, angle_rad / 2.0, u)
			x = sin(current_angle) * radius
			z = (cos(current_angle) * radius - radius) * dir
			normal = Vector3(sin(current_angle) * dir, 0, cos(current_angle)).normalized()

		# 1. Low vertex
		var pos_bottom = Vector3(x, -h / 2.0, z)
		st.set_normal(normal)
		st.set_uv(Vector2(u, 1.0))
		st.add_vertex(pos_bottom)

		# 2. High vertex
		var pos_top = Vector3(x, h / 2.0, z)
		st.set_normal(normal)
		st.set_uv(Vector2(u, 0.0))
		st.add_vertex(pos_top)

	return st.commit()
