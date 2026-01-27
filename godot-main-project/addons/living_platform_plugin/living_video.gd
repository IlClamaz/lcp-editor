## Simplified API for video playback on a 3D rectangle
@tool
extends Sprite3D

class_name LivingVideo

# References to the hand crafted children in the hierarchy
@onready var viewport = $"VideoPlayer-SubViewport"
@onready var player = $"VideoPlayer-SubViewport/VideoStreamPlayer"


# Test button to play the video referenced by the parent media
@export_tool_button("Play Parent Media Video") var play_video_btn = play_media_video

func play_media_video() -> void:
	var parent_media_node = $".." as LivingMedia
	var media_path = parent_media_node.media_path
	
	print("Loading media video ", media_path)
	
	load_video_stream(media_path)
	
	print("Playing")
	
	self.play_video()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#player = VideoStreamPlayer.new()
	#viewport = SubViewport.new()
	
	
	#viewport.add_child(player)
	#add_child(viewport)

	# print("Living video ready with owner", self.owner)

	#viewport.owner = owner
	#player.owner = owner
	#viewport.owner = self
	#player.owner = self
	
	print("Video Info. Type: ", typeof(player.stream), "	Stream: ", player.stream, "	Name: ",
	player.get_stream_name(), "	Length: ", player.get_stream_length())

func _enter_tree() -> void:
	print("Living video tree entering with owner", self.owner)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	# print("Pos: ", player.stream_position)
	pass

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
func load_video_stream(video_path: String) -> void:
	
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
		
	
	else:
		push_warning("Could not load video stream: %s" % video_path)
