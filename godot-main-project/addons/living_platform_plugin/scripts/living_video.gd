@tool
extends Node3D
class_name LivingVideo

# References to the hand crafted children in the hierarchy
@onready var viewport = $"VideoPlayer-SubViewport"
@onready var player = $"VideoPlayer-SubViewport/VideoStreamPlayer"
@onready var controls_panel = $"Controls"

@export var video_path: String = ""

# --- Parameter to curve the screen ---
# Positives Values (> 0) = Concave
# Negative Values (< 0) = Convex
@export_range(-360.0, 360.0) var curve_degrees: float = 0.0 :
	set(v):
		curve_degrees = v
		if is_inside_tree() and viewport != null:
			_update_geometries()

@export var pixel_size: float = 0.01 

# Test button to play the video referenced by the parent media
@export_tool_button("Play Video") var play_video_btn = play_video
@export_tool_button("Toggle Pause") var toggle_pause_btn = toggle_pause
@export_tool_button("Stop Video") var stop_video_btn = stop_video

## Procedural generated geometries
var screen_instance: MeshInstance3D = null

## This is needed to intercept collisions for ray casting
var face_collision_shape: CollisionShape3D = null
## This is needed to trigger collisions with the walking camera
var trigger_collision_shape: CollisionShape3D = null

## Minimum depth of the trigger for a video
const TRIGGER_MIN_DEPTH: float = 5.0
## Number of segments for the curved plane mesh generation (higher = smoother curvature, but more expensive)
const CURVE_SEGMENTS: int = 32 

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not Engine.is_editor_hint() or player.stream != null:
		print("LivingVideo Ready. Stream Info. Type: ", typeof(player.stream), "    Stream: ", player.stream)

	# Setup of geometries
	if screen_instance == null:
		# The screen on which we are projecting the video texture
		screen_instance = MeshInstance3D.new()

		# front face collision
		var static_body = StaticBody3D.new()
		static_body.collision_layer = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
		static_body.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
		add_child(static_body)
		face_collision_shape = CollisionShape3D.new()
		face_collision_shape.name = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE
		static_body.add_child(face_collision_shape)
		static_body.add_child(screen_instance)

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

	_init_video_stream()


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

		# Wait another frame, so that the player is rendering the first frame
		await get_tree().process_frame

		# Stop immediately to leave control to the API.
		stop_video()
		player.volume_db = original_volume

	else:
		push_error("Could not load video stream: %s" % video_path)


func _update_geometries():
	if viewport == null or screen_instance == null: return
	
	var viewport_scaled_size = Vector2(viewport.size) * self.pixel_size
	var w = viewport_scaled_size.x
	var h = viewport_scaled_size.y
	
	if w <= 0 or h <= 0: return

	# Screen space generation
	var screen_mesh = _generate_curved_plane(w, h, curve_degrees)
	screen_instance.mesh = screen_mesh
	
	var screen_mat = StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	screen_mat.albedo_texture = viewport.get_texture()
	screen_mat.resource_local_to_scene = true
	screen_instance.set_surface_override_material(0, screen_mat)

	face_collision_shape.shape = screen_mesh.create_trimesh_shape()

	# Trigger Area
	var trigger_depth = max(h / 2.0, TRIGGER_MIN_DEPTH)
	
	if trigger_collision_shape.shape is BoxShape3D:
		trigger_collision_shape.shape.size = Vector3(w, 0.2, trigger_depth)
	trigger_collision_shape.position = Vector3(0, 0, trigger_depth / 2.0)
	trigger_collision_shape.global_position.y = 0.1

	# Control Panel
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
