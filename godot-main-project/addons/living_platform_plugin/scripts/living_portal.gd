@tool
extends Node3D

class_name LivingPortal


## The ID of the target environment. The corresponding scene will be searched automatically in the save folder.
@export var target_environment_id: int

## Set this to true if you want to specify the teleport target as scene path directly.
@export var use_scene_path: bool = false
## The path to the target scene.
@export var target_scene_path: String = ""

@export var albedo_color: Color = Color(1.0, 0.6, 0.0, 1.0)
@export var emission_color: Color = Color(1.0, 0.55, 0.0)

## Distance (in meters) the camera is moved backward along its looking direction before teleporting,
## so that on returning to this scene the player is not already standing inside the portal trigger.
const CAMERA_OFFSET_AFTER_TELEPORT: float = 3.0

@export_tool_button("Switch to environment") var switch_btn = switch_to_target_environment
@export_tool_button("Update Portal Visual") var update_visual_btn = update_portal_visual

var portal_subscene = preload("res://addons/living_platform_plugin/scripts/living_portal_content.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_child(portal_subscene.instantiate())
	
	var collision_area: Area3D = $"Area3D"
	# Set the collision layer/mask to the same used for Trigger the steles, with the "feet" of the camera.
	collision_area.collision_layer = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
	collision_area.collision_mask = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER

	collision_area.area_entered.connect(_on_body_entered_area)
	visibility_changed.connect(_on_visibility_changed)

	_create_portal_visual()
	update_portal_visual()
	_update_collision_state_from_visibility()


## Creates the portal visualization: a white emissive floor ring and an inclined
## yellow-orange transparent glow cone rising from it.
func _create_portal_visual() -> void:
	if get_node_or_null("PortalRing") and get_node_or_null("PortalGlow"):
		return

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
	ring_mat.resource_local_to_scene = true

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
	glow_mat.albedo_color = albedo_color
	glow_mat.emission_enabled = true
	glow_mat.emission = emission_color
	glow_mat.emission_energy_multiplier = 0.8
	glow_mat.resource_local_to_scene = true

	glow_node.material_override = glow_mat
	add_child(glow_node)


func update_portal_visual() -> void:
	_create_portal_visual()

	var glow_node := get_node_or_null("PortalGlow") as MeshInstance3D
	if not glow_node:
		return

	var glow_mat := glow_node.material_override as StandardMaterial3D
	if not glow_mat:
		glow_mat = StandardMaterial3D.new()
		glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		glow_mat.vertex_color_use_as_albedo = true
		glow_mat.emission_enabled = true
		glow_mat.emission_energy_multiplier = 0.8
	else:
		# Ensure per-instance material so inspector color changes don't affect duplicated portals.
		glow_mat = glow_mat.duplicate(true) as StandardMaterial3D

	glow_mat.resource_local_to_scene = true
	glow_node.material_override = glow_mat

	glow_mat.albedo_color = albedo_color
	glow_mat.emission = emission_color


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
	if not visible:
		return

	print("Portal '%s' collided with node %s" % [self.name, n.name])

	if n.name != "CameraFeetArea3D":
		return
	
	var lc = n.get_parent().get_parent()
	assert (lc is LivingCamera)

	# print("Retrieving camera information")
	var camera: LivingCamera = lc as LivingCamera
	# Offset the camera 2 meters back w.r.t. the looking direction to avoid being already in the portal on returns.
	var new_camera_position = camera.global_position + camera.global_basis.z * CAMERA_OFFSET_AFTER_TELEPORT

	var post_fade_func = func():
		switch_to_target_environment()
		# Set the camera position after the teleport happened
		camera.global_position = new_camera_position

	camera.fade_out(Color.WHITE_SMOKE, post_fade_func)


func _on_visibility_changed() -> void:
	_update_collision_state_from_visibility()


func _update_collision_state_from_visibility() -> void:
	var collision_area := get_node_or_null("Area3D") as Area3D
	if not collision_area:
		return

	var collision_enabled: bool = visible
	collision_area.monitoring = collision_enabled
	collision_area.monitorable = collision_enabled



func switch_to_target_environment() -> void:

	# Given the environment id, scan the scene save directory for the most recent scene for the given environment
	LivingConstants.SAVED_SCENES_FOLDER

	var target_path: String
	if self.use_scene_path:
		target_path = self.target_scene_path
	else:
		target_path = LivingUtils.get_most_recent_scene(self.target_environment_id)
		print("Most recent scene for environment %s is '%s'" % [self.target_environment_id, target_path])

	if target_path == "":
		print("No destination scene specified. No teleporting.")
		return

	print("Loading and showing scene '%s'" % [target_path])
	# The @tool annotation prevents direct autoload name access in editor context. Use the node path instead
	var scene_manager := get_node_or_null("/root/LivingSceneManager")
	if scene_manager:
		scene_manager.go_to_scene(target_path)
	else:
		push_error("LivingSceneManager autoload not found")
