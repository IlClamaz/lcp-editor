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
var curvature: float = 0.0 :
	set(v):
		curvature = v
		if is_inside_tree() and viewport != null:
			_update_geometries()

var pixel_size: float = 0.01

@export var diagonal: float = 1.0 :
	set(v):
		diagonal = max(v, 0.01)
		if is_inside_tree() and viewport != null:
			_update_geometries()

##  If the camera goes too far away from the video player, we force pausing it.
@export var auto_pause_camera_distance: float = 10.0

# Test button to play the video referenced by the parent media
@export_tool_button("Play Video") var play_video_btn = play_video
@export_tool_button("Toggle Pause") var toggle_pause_btn = toggle_pause
@export_tool_button("Stop Video") var stop_video_btn = stop_video

var background: MeshInstance3D = null
## This is needed to intercept collisions for ray casting
var face_collision_shape: CollisionShape3D = null
## This is needed to trigger collisions with the walking camera
var trigger_collision_shape: CollisionShape3D = null

const BACKGROUND_THICKNESS_PROP: float = 0.01
const BACKGROUND_PADDING: float = 0
## Minimum depth of the trigger for a video
const TRIGGER_MIN_DEPTH: float = 5.0
## Number of segments for the curved plane mesh generation
const CURVE_SEGMENTS: int = 32 


## Number of render frames to wait while the video player starts rendering a video frame on the viewport
const VIDEO_INIT_FRAMES_DELAY = 10
## Se to true only when the video preview is completely correctly initialized.
var _is_video_initialized = false
var _is_video_loading: bool = false
## The horizontal proportion of the control panel with respect to the width of the video
const CONTROL_PANEL_H_PROP = 0.3

## Emitted when the video has been finally initialized
## It means that afew frames have been read, teture size is correct, and video player is paused
signal video_initialized

## Emitted when toggle_pause is invoked
signal pause_toggled


# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	if not Engine.is_editor_hint() or player.stream != null:
		print("LivingVideo Ready. Stream Info. Type: ", typeof(player.stream), "\tStream: ", player.stream)

	# Prepare to listen to when the video finished the playback
	player.finished.connect(_on_video_finished)

	# By default, video control are invisible.
	self.hide_video_control()

	# Setup of geometries
	if face_collision_shape == null:
		background = MeshInstance3D.new()
		
		# front face collision
		var static_body = StaticBody3D.new()
		static_body.collision_layer = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER | 1
		static_body.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
		add_child(static_body)
		
		face_collision_shape = CollisionShape3D.new()
		face_collision_shape.name = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE
		static_body.add_child(background)
		static_body.add_child(face_collision_shape)

		# Trigger area
		var trigger_body := Area3D.new()
		trigger_body.name = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_NODE
		trigger_body.collision_layer = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
		trigger_body.collision_mask = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
		trigger_collision_shape = CollisionShape3D.new()
		trigger_collision_shape.shape = BoxShape3D.new()
		trigger_body.add_child(trigger_collision_shape)
		add_child(trigger_body)

		# Attach event listener to the trigger.
		# It will call two methods when a camera enters the Trigger area
		# We want to switch the controls visibility on and off according to camera proximity.
		trigger_body.area_entered.connect(_on_trigger_area_entered)
		trigger_body.area_exited.connect(_on_trigger_area_exited)

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


## Holds a reference to the scene living camera. Used to check the distance for automatic deactivation.
var _living_camera: LivingCamera = null


func _init_camera_distance_monitor():

	var cameras := get_tree().root.find_children("*", "LivingCamera", true, false)
	if cameras.size() > 0:
		_living_camera = cameras[0] as LivingCamera



func _process(delta: float) -> void:

	if _is_video_loading:
		var status = ResourceLoader.load_threaded_get_status(video_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_is_video_loading = false
			_apply_video_stream(ResourceLoader.load_threaded_get(video_path))
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_is_video_loading = false
			push_error("Could not load video stream: %s" % video_path)
		return

	if Engine.is_editor_hint():
		return

	if _living_camera != null:

		var real_cam = _living_camera.get_real_camera_node()
		if real_cam != null:

			var distance_on_floor = LivingUtils.floor_distance(self.global_position, real_cam.global_position)
			# print(name, " - ", distance_on_floor)

			# If the camera walks too much away from the video, and it is playing, pause it.
			if  distance_on_floor > auto_pause_camera_distance:
				# print("Off camera distance %s for %s --> Pausing video if needed" % [distance_on_floor, self.name])
				if not self.is_paused():
					print("Off camera distance %s for %s --> Pausing video." % [distance_on_floor, self.name])
					self.toggle_pause()

#
# Video COntrol Objects
#

## Show the player control buttons panel
func show_video_control() -> void:
	controls_panel.visible = true


## Hide the player control buttons panel
func hide_video_control() -> void:
	controls_panel.visible = false


func _on_trigger_area_entered(area: Area3D) -> void:

	if area.name == "CameraFeetArea3D":
		show_video_control()


func _on_trigger_area_exited(area: Area3D) -> void:

	if area.name == "CameraFeetArea3D":
		hide_video_control()


## Returns true if the player control buttons panel is visible
func is_video_control_visible() -> bool:
	return controls_panel.visible


#
# Public video control API
#

## Play again the current video stream
func play_video() -> void:
	player.play()


## Plause the video player
func pause() -> void:
	player.paused = true


## Toggle the paused status
func toggle_pause() -> void:
	player.paused = ! player.paused
	self.pause_toggled.emit()


## Returns true if the player is paused
func is_paused() -> bool:
	return player.paused


## Stop the playback of the current video stream
func stop_video() -> void:
	player.stop()


## Move the playback point to the given value, expressed in percentage from 0% to 100%.
func seek_video(pct: float) -> void:
	var pct_0_1: float = clampf(pct, 0.0, 100.0) / 100.0
	var new_position: float = player.get_stream_length() * pct_0_1
	player.stream_position = new_position


# On video finished, it is reset to the preview state.
func _on_video_finished() -> void:
	_init_video_stream()



#
# Private methos
#

func _init_video_stream() -> void:

	print("Initializing video player with media video '%s'" % [video_path])

	if not self.is_inside_tree():
		print("Node not in tree. Skipping init ...")
		return

	if _is_video_loading:
		return

	ResourceLoader.load_threaded_request(video_path)
	_is_video_loading = true


func _apply_video_stream(stream) -> void:
	if stream and stream is VideoStream:
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
		pause()
		player.volume_db = original_volume

		_is_video_initialized = true
		self.video_initialized.emit()

		_init_camera_distance_monitor()
	else:
		push_error("Could not load video stream: %s" % video_path)


func _update_geometries():
	if viewport == null: return
	
	var effective_pixel_size := self.pixel_size
	var native_diagonal_px := Vector2(viewport.size).length()
	if native_diagonal_px > 0.0:
		effective_pixel_size = diagonal / native_diagonal_px
	var viewport_scaled_size = Vector2(viewport.size) * effective_pixel_size
	var w = viewport_scaled_size.x
	var h = viewport_scaled_size.y
	
	if w <= 0 or h <= 0: return

	var is_flat = abs(curvature) <= 0.01

	# 1. Screen space generation
	var screen_mesh = _generate_curved_plane(w, h, curvature, 0.0, 0.0)
	self.mesh = screen_mesh
	
	var screen_mat = StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	screen_mat.albedo_texture = viewport.get_texture()
	screen_mat.resource_local_to_scene = true
	self.set_surface_override_material(0, screen_mat)

	# 2. Gestione Background (Solido 3D Concentrico)
	var background_w = w + BACKGROUND_PADDING * 2
	var background_h = h + BACKGROUND_PADDING * 2
	var background_depth = background_w * BACKGROUND_THICKNESS_PROP
	
	if is_flat:
		var box = BoxMesh.new()
		box.size = Vector3(background_w, background_h, background_depth)
		background.mesh = box
		background.position = Vector3(0, 0, -1.01 * background_depth / 2.0)
	else:
		background.mesh = _generate_curved_box(w, h, curvature, BACKGROUND_PADDING * 2, background_depth, -0.05)
		background.position = Vector3.ZERO
		
	background.material_override = null

	# 3. Collisioni
	if face_collision_shape != null:
		if is_flat:
			var box_shape = BoxShape3D.new()
			box_shape.size = Vector3(background_w, background_h, background_depth)
			face_collision_shape.shape = box_shape
			face_collision_shape.position = background.position
		else:
			face_collision_shape.shape = background.mesh.create_trimesh_shape()
			face_collision_shape.position = Vector3.ZERO

	# 4. Trigger Area
	var trigger_depth = max(background_h, TRIGGER_MIN_DEPTH)
	if trigger_collision_shape != null and trigger_collision_shape.shape is BoxShape3D:
		trigger_collision_shape.shape.size = Vector3(background_w, 0.2, trigger_depth)
		trigger_collision_shape.position = Vector3(0, 0, trigger_depth / 2.0)
		if is_inside_tree():
			trigger_collision_shape.global_position.y = 0.1
			trigger_collision_shape.global_rotation_degrees = Vector3.ZERO

	# 5. Control Panel
	if controls_panel != null:
		controls_panel.position.y = -h / 2.0
		controls_panel.scale = Vector3.ONE
		LivingUtils.get_node_aabb(controls_panel)
		var native_width = LivingUtils.get_node_aabb(controls_panel).size.x
		var s = (w * CONTROL_PANEL_H_PROP) / native_width if native_width > 0.0 else 1.0
		controls_panel.scale = Vector3(s, s, s)


# ----------------------------------------------------------------------
# GENERATORI PROCEDURALI
# ----------------------------------------------------------------------

# Generatore Plane (usato solo per lo schermo video sottilissimo sul fronte)
func _generate_curved_plane(w: float, h: float, curve_deg: float, pad_total: float = 0.0, z_offset: float = 0.0) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var is_flat = abs(curve_deg) <= 0.01
	var dir = -sign(curve_deg) if curve_deg != 0 else 1.0
	var angle_rad = 0.0
	var radius = 0.0
	var total_w = w + pad_total
	var total_h = h + pad_total

	if not is_flat:
		angle_rad = deg_to_rad(abs(curve_deg))
		radius = w / angle_rad 
		angle_rad = total_w / radius

	var get_v = func(i: int, y: float):
		var u = float(i) / CURVE_SEGMENTS
		var x = 0.0; var z = 0.0; var normal = Vector3(0, 0, 1)

		if is_flat:
			x = lerp(-total_w / 2.0, total_w / 2.0, u)
		else:
			var current_angle = lerp(-angle_rad / 2.0, angle_rad / 2.0, u)
			x = sin(current_angle) * radius
			z = (cos(current_angle) * radius - radius) * dir
			normal = Vector3(sin(current_angle) * dir, 0, cos(current_angle)).normalized()

		return Vector3(x, y, z) + normal * z_offset

	var y_top = total_h / 2.0
	var y_bot = -total_h / 2.0

	st.set_smooth_group(1) 

	for i in range(CURVE_SEGMENTS):
		var f_tl = get_v.call(i, y_top); var f_tr = get_v.call(i + 1, y_top)
		var f_bl = get_v.call(i, y_bot); var f_br = get_v.call(i + 1, y_bot)

		var u_left = float(i) / CURVE_SEGMENTS
		var u_right = float(i + 1) / CURVE_SEGMENTS

		st.set_uv(Vector2(u_left, 1.0)); st.add_vertex(f_bl)
		st.set_uv(Vector2(u_right, 1.0)); st.add_vertex(f_br)
		st.set_uv(Vector2(u_right, 0.0)); st.add_vertex(f_tr)

		st.set_uv(Vector2(u_left, 1.0)); st.add_vertex(f_bl)
		st.set_uv(Vector2(u_right, 0.0)); st.add_vertex(f_tr)
		st.set_uv(Vector2(u_left, 0.0)); st.add_vertex(f_tl)

	st.generate_normals()
	st.generate_tangents()

	return st.commit()


# Generatore BOX 3D (disegna una "scatola" curva solida per il retro)
func _generate_curved_box(w: float, h: float, curve_deg: float, pad_total: float, thickness: float, z_offset: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var is_flat = abs(curve_deg) <= 0.01
	var dir = -sign(curve_deg) if curve_deg != 0 else 1.0

	var angle_rad = 0.0
	var radius = 0.0
	var total_w = w + pad_total
	var total_h = h + pad_total

	if not is_flat:
		angle_rad = deg_to_rad(abs(curve_deg))
		radius = w / angle_rad 
		angle_rad = total_w / radius

	var get_v = func(i: int, y: float, z_push: float):
		var u = float(i) / CURVE_SEGMENTS
		var x = 0.0; var z = 0.0; var normal = Vector3(0, 0, 1)

		if is_flat:
			x = lerp(-total_w / 2.0, total_w / 2.0, u)
		else:
			var current_angle = lerp(-angle_rad / 2.0, angle_rad / 2.0, u)
			x = sin(current_angle) * radius
			z = (cos(current_angle) * radius - radius) * dir
			normal = Vector3(sin(current_angle) * dir, 0, cos(current_angle)).normalized()

		return Vector3(x, y, z) + normal * z_push

	var y_top = total_h / 2.0
	var y_bot = -total_h / 2.0
	var z_front = z_offset
	var z_back = z_offset - thickness 

	for i in range(CURVE_SEGMENTS):
		var f_tl = get_v.call(i, y_top, z_front); var f_tr = get_v.call(i + 1, y_top, z_front)
		var f_bl = get_v.call(i, y_bot, z_front); var f_br = get_v.call(i + 1, y_bot, z_front)

		var b_tl = get_v.call(i, y_top, z_back); var b_tr = get_v.call(i + 1, y_top, z_back)
		var b_bl = get_v.call(i, y_bot, z_back); var b_br = get_v.call(i + 1, y_bot, z_back)

		st.set_smooth_group(1)
		_add_quad_simple(st, f_bl, f_br, f_tr, f_tl)
		_add_quad_simple(st, b_br, b_bl, b_tl, b_tr)

		st.set_smooth_group(0) 
		_add_quad_simple(st, f_tl, f_tr, b_tr, b_tl)
		_add_quad_simple(st, b_bl, b_br, f_br, f_bl)
		
		if i == 0:
			_add_quad_simple(st, b_bl, f_bl, f_tl, b_tl)
		if i == CURVE_SEGMENTS - 1:
			_add_quad_simple(st, f_br, b_br, b_tr, f_tr)

	st.generate_normals()
	st.generate_tangents()

	return st.commit()


# Helper interno per aggiungere i quadrati con UV
func _add_quad_simple(st: SurfaceTool, v1: Vector3, v2: Vector3, v3: Vector3, v4: Vector3):
	st.set_uv(Vector2(0, 1)); st.add_vertex(v1)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v2)
	st.set_uv(Vector2(1, 0)); st.add_vertex(v3)

	st.set_uv(Vector2(0, 1)); st.add_vertex(v1)
	st.set_uv(Vector2(1, 0)); st.add_vertex(v3)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v4)
