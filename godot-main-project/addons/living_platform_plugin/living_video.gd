## Simplified API for video playback on a 3D rectangle
@tool
extends Sprite3D

class_name LivingVideo

# References to the hand crafted children in the hierarchy
@onready var viewport = $"VideoPlayer-SubViewport"
@onready var player = $"VideoPlayer-SubViewport/VideoStreamPlayer"
@onready var controls_panel = $"Controls"

@export var video_path: String = ""

# Test button to play the video referenced by the parent media
@export_tool_button("Play Video") var play_video_btn = play_media_video
@export_tool_button("Toggle Pause") var toggle_pause_btn = toggle_pause
@export_tool_button("Stop Video") var stop_video_btn = stop_video


# This will be added as child and will containg the box geometry acting as background
var background: MeshInstance3D = null
# The background thickness is computed as this factor of the video width
const BACKGROUND_THICKNESS_PROP: float = 0.01
# Absolute background padding size around the video area
const BACKGROUND_PADDING: float = 0.2


func play_media_video() -> void:
	print("Loading and playing media video '%s'" % [video_path])
	
	load_and_play_video_stream(video_path)	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("LivingVideo Ready. Stream Info. Type: ", typeof(player.stream), "	Stream: ", player.stream, "	Name: ",
	player.get_stream_name(), "	Length: ", player.get_stream_length())


	# Background rectangle (BoxMesh)
	background = MeshInstance3D.new()
	background.mesh = BoxMesh.new()
	# background.mesh.size = Vector3(1, 1, BACKGROUND_THICKNESS)  # Adjust as needed
	add_child(background)

	_update_geometries()


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
	
## Load and play the video with the givan path name.
## Do NOT specify the `res://` prefix.
func load_and_play_video_stream(video_path: String) -> void:
	
	# Loads a VideoStream resource
	var stream := load(video_path)
	if stream and stream is VideoStreamTheora:
		# print("Stream size info. type: ", typeof(stream_size), stream_size)
		player.stream = stream
		
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
		
	else:
		push_warning("Could not load video stream: %s" % video_path)


func _update_geometries():
	
	var viewport_scaled_size = viewport.size * self.pixel_size	
	print("Video player bounds ", viewport_scaled_size)
	
	# Resizes the background
	var background_w = viewport_scaled_size.x + BACKGROUND_PADDING * 2
	var background_h = viewport_scaled_size.y + BACKGROUND_PADDING * 2
	var background_depth = background_w * BACKGROUND_THICKNESS_PROP
	background.mesh.size.x = background_w
	background.mesh.size.y = background_h
	background.mesh.size.z = background_depth
	background.position.x = 0 # background_w / 2 - padding
	background.position.y = 0
	background.position.z = - 1.001 * background_depth / 2.0  # Behind video Sprite3D, with a additional epsilon to avoid z-fight

	# Vertically adjust control panel position
	controls_panel.position.y = - background_h / 2.0
