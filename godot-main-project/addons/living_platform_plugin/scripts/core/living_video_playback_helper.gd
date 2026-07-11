extends RefCounted
class_name LivingVideoPlaybackHelper

# Shared play/pause/stop dispatch for LivingVideo and LivingVideo360 children.


static func play(child: Node) -> void:
	if child == null:
		return
	if child is LivingVideo:
		(child as LivingVideo).play_video()
	elif child is LivingVideo360:
		(child as LivingVideo360).play()


static func pause(child: Node) -> void:
	if child == null:
		return
	if child is LivingVideo:
		(child as LivingVideo).pause()
	elif child is LivingVideo360:
		(child as LivingVideo360).pause()


static func toggle_pause(child: Node) -> void:
	if child == null:
		return
	if child is LivingVideo:
		(child as LivingVideo).toggle_pause()
	elif child is LivingVideo360:
		(child as LivingVideo360).toggle_pause()


static func stop(child: Node) -> void:
	if child == null:
		return
	if child is LivingVideo:
		(child as LivingVideo).stop_video()
	elif child is LivingVideo360:
		(child as LivingVideo360).stop()
