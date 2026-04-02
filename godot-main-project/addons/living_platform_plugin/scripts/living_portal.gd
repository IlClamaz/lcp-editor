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
	
	var collision_area: Area3D = $"Area3D"
	# Set the collision layer/mask to the same used for Trigger the steles, with the "feet" of the camera.
	collision_area.collision_layer = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
	collision_area.collision_mask = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER

	collision_area.area_entered.connect(_on_body_entered_area)

	_create_portal_visual()


## Creates the portal visualization: a white emissive floor ring and an inclined
## yellow-orange transparent glow cone rising from it.
func _create_portal_visual() -> void:
	# --- White emissive floor ring ---
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 12
	torus.ring_segments = 48

	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color.WHITE
	ring_mat.emission_enabled = true
	ring_mat.emission = Color.WHITE
	ring_mat.emission_energy_multiplier = 3.0

	torus.material = ring_mat

	var ring_node := MeshInstance3D.new()
	ring_node.name = "PortalRing"
	ring_node.mesh = torus
	add_child(ring_node)

	# --- Inclined yellow-orange glow cone ---
	# bottom_radius, top_radius, height, lean_z (how far the top circle shifts in -Z)
	var glow_node := MeshInstance3D.new()
	glow_node.name = "PortalGlow"
	glow_node.mesh = _build_inclined_cone_mesh(1.0, 1.5, 2.0, 0.0, 24, 1.0, 0.0)

	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow_mat.vertex_color_use_as_albedo = true
	glow_mat.albedo_color = Color(1.0, 0.6, 0.0, 1.0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.55, 0.0)
	glow_mat.emission_energy_multiplier = 0.8

	glow_node.material_override = glow_mat
	add_child(glow_node)


## Builds a cone/frustum whose top circle is offset by [param lean_z] along -Z,
## giving the inclined appearance seen in the portal reference image.
func _build_inclined_cone_mesh(
		bottom_radius: float, top_radius: float,
		height: float, lean_z: float,
		segments: int,
		alpha_bottom: float = 1.0, alpha_top: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var color_bottom := Color(1.0, 1.0, 1.0, alpha_bottom)
	var color_top    := Color(1.0, 1.0, 1.0, alpha_top)

	for i in range(segments):
		var a0 := (float(i) / segments) * TAU
		var a1 := (float(i + 1) / segments) * TAU

		var b0 := Vector3(cos(a0) * bottom_radius, 0.0,    sin(a0) * bottom_radius)
		var b1 := Vector3(cos(a1) * bottom_radius, 0.0,    sin(a1) * bottom_radius)
		var t0 := Vector3(cos(a0) * top_radius,    height, sin(a0) * top_radius - lean_z)
		var t1 := Vector3(cos(a1) * top_radius,    height, sin(a1) * top_radius - lean_z)

		# Two triangles per quad strip segment (CULL_DISABLED so winding doesn't matter)
		st.set_color(color_bottom); st.add_vertex(b0)
		st.set_color(color_top);    st.add_vertex(t0)
		st.set_color(color_bottom); st.add_vertex(b1)

		st.set_color(color_bottom); st.add_vertex(b1)
		st.set_color(color_top);    st.add_vertex(t0)
		st.set_color(color_top);    st.add_vertex(t1)

	st.generate_normals()
	return st.commit()


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
