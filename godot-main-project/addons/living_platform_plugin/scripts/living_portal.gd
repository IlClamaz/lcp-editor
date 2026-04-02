@tool
extends Node3D

class_name LivingPortal

#@onready var base = $"CSGCylinder3D"
#@onready var emitter = $"GPUParticles3D"

@export var target_scene_path: String = ""


@export_tool_button("Switch to scene") var switch_btn = switch_to_target_scene

var portal_subscene = preload("res://addons/living_platform_plugin/scripts/living_portal_content.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_child(portal_subscene.instantiate())
	
	var collision_area: Area3D = $"GPUParticles3D/Area3D"
	# Set the collision layer/mask to the same used for Trigger the steles, with the "feet" of the camera.
	collision_area.collision_layer = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
	collision_area.collision_mask = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER

	collision_area.area_entered.connect(_on_body_entered_area)

func _on_body_entered_area(n: Node3D):
	print("Portal '%s' collided with node %s" % [self.name, n.name])
	switch_to_target_scene.call_deferred()


func switch_to_target_scene() -> void:

	if target_scene_path == "":
		print("No destination scene specified. No teleporting.")
		return

	print("Loading and showing scene %s" % [target_scene_path])

	var packed_scene = load(target_scene_path)
	if packed_scene:
		get_tree().change_scene_to_packed(packed_scene)
	else:
		push_error("Failed to load scene")
