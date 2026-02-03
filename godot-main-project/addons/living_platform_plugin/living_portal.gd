@tool
extends Node3D

class_name LivingPortal

#@onready var base = $"CSGCylinder3D"
#@onready var emitter = $"GPUParticles3D"

@export var target_scene_path: String


@export_tool_button("Switch to scene") var switch_btn = switch_to_target_scene

var portal_subscene = preload("res://addons/living_platform_plugin/living_portal_content.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_child(portal_subscene.instantiate())
	
	var collision_area: Area3D = $"GPUParticles3D/Area3D"
	collision_area.body_entered.connect(_on_body_entered_area)

func _on_body_entered_area(n: Node3D):
	# print("Node '%s' collided with portal" % [n.name])
	if n is LivingCamera:
		print("Collision with a LivingCamera")
		call_deferred("switch_to_target_scene")


func switch_to_target_scene() -> void:
	print("Loading and showing scene %s" % [target_scene_path])
	
	var packed_scene = load(target_scene_path)  # Or preload() for static.
	if packed_scene:
		get_tree().change_scene_to_packed(packed_scene)
	else:
		push_error("Failed to load scene")
