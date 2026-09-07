@tool
extends Node3D

class_name LivingTarget


## Fixed XZ plane size for procedural targets (metres). Pivot sits on the plane center.
const PROCEDURAL_PLANE_SIZE := Vector2(3.0, 3.0)
const PROCEDURAL_PLANE_THICKNESS := 0.02


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	## Create the model node and adds it as child
	var scene_root := load_model()

	# Ephemeral marker, pose comes from LivingTargetObject exports.
	LivingVisitPoint.sync_on_medium(self)


func load_model() -> Node3D:
	
	# Remove all children first (visit marker is recreated after load, like colliders).
	for child in get_children():
		child.queue_free()
	
	var procedural_root := _build_procedural_plane()
	add_child(procedural_root)
	return procedural_root


## Flat plane on XZ (y = 0). Pivot at the plane center.
func _build_procedural_plane() -> Node3D:
	var root := Node3D.new()
	root.name = "ProceduralPlane"

	var plane := PlaneMesh.new()
	plane.size = PROCEDURAL_PLANE_SIZE
	plane.orientation = PlaneMesh.FACE_Y

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mi := MeshInstance3D.new()
	mi.name = "Plane"
	mi.mesh = plane
	mi.material_override = mat
	root.add_child(mi)

	return root
