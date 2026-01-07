# This is the node type to be used as scene root.
# It contains the global variables used by the Living Items in the scene
@tool
extends Node3D

class_name LivingScene

@export var OMEKA_BASE_URL: String = "https://omekas.livingculture.it"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
