@tool
extends LivingObject
class_name Living3DModelAnimatedObject

# Typed parent for Omeka "OggettoAnimato". Animation/AI curator settings.

@export_group("ANIMATED MODEL")
@export var move_speed: float = 2.0 :
	set(v):
		move_speed = v
		if not is_inside_tree():
			return
		apply_animated_settings()
@export var random_poses_playing: bool = true :
	set(v):
		random_poses_playing = v
		if not is_inside_tree():
			return
		apply_animated_settings()
@export var moving: bool = true :
	set(v):
		moving = v
		if not is_inside_tree():
			return
		apply_animated_settings()
@export var random_spawn: bool = false :
	set(v):
		random_spawn = v
		if not is_inside_tree():
			return
		apply_animated_settings()
@export_range(0.0, 1.0, 0.01) var extra_pose_chain_chance: float = 0.35 :
	set(v):
		extra_pose_chain_chance = clampf(v, 0.0, 1.0)
		if not is_inside_tree():
			return
		apply_animated_settings()
@export_range(2, 6, 1) var extra_pose_chain_min: int = 2 :
	set(v):
		extra_pose_chain_min = clampi(v, 2, 6)
		if not is_inside_tree():
			return
		apply_animated_settings()
@export_range(2, 6, 1) var extra_pose_chain_max: int = 3 :
	set(v):
		extra_pose_chain_max = clampi(v, 2, 6)
		if not is_inside_tree():
			return
		apply_animated_settings()


func _ready() -> void:
	super._ready()
	call_deferred("apply_animated_settings")


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	await get_tree().process_frame
	apply_animated_settings()


func get_living_3dmodel_animated_child() -> Living3DModelAnimated:
	for child in get_children():
		if child is Living3DModelAnimated:
			return child as Living3DModelAnimated
	return null


func build_animated_settings() -> Dictionary:
	return {
		"move_speed": move_speed,
		"random_poses_playing": random_poses_playing,
		"moving": moving,
		"random_spawn": random_spawn,
		"extra_pose_chain_chance": extra_pose_chain_chance,
		"extra_pose_chain_min": extra_pose_chain_min,
		"extra_pose_chain_max": extra_pose_chain_max,
	}


func apply_animated_settings() -> void:
	var animated_child := get_living_3dmodel_animated_child()
	if animated_child == null:
		return
	animated_child.apply_settings(build_animated_settings())
