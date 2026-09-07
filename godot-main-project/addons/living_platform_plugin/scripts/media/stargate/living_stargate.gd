@tool
extends Node3D

class_name LivingStargate

## The ID of the target environment. The corresponding scene will be searched automatically in the save folder.
@export var target_environment_id: int

## Set this to true if you want to specify the teleport target as scene path directly.
@export var use_scene_path: bool = false
## The path to the target scene.
@export var target_scene_path: String = ""

@export_group("Stargate state colors")
@export var color_active: Color = Color(1.0, 0.6, 0.0)
@export var color_inactive: Color = Color(0.55, 0.55, 0.55)
@export var color_used: Color = Color(1.0, 0.25, 0.2)

var albedo_color: Color = Color(1.0, 0.6, 0.0, 1.0)
var emission_color: Color = Color(1.0, 0.55, 0.0)
@export var stargate_caption_text: String = "Stargate to..." : set = set_stargate_caption_text
@export var stargate_caption_scale: float = 3.0 : set = set_stargate_caption_scale
@export var stargate_caption_position_y: float = 1.7 : set = set_stargate_caption_position_y

## Distance (in meters) the camera is moved backward along its looking direction before teleporting,
## so that on returning to this scene the player is not already standing inside the stargate trigger.
const CAMERA_OFFSET_AFTER_TELEPORT: float = 3.0
const STARGATE_CONE_BOTTOM_RADIUS: float = 1.0
const STARGATE_CONE_TOP_RADIUS: float = 1.5
const STARGATE_CONE_HEIGHT: float = 2.0
const STARGATE_CONE_LEAN_Z: float = 0.0
const STARGATE_CONE_SEGMENTS: int = 24
const STARGATE_CONE_ALPHA_TOP: float = 0.0
const STARGATE_CONE_ALPHA_BOTTOM: float = 1.0

enum StargateState { INACTIVE, ACTIVE, USED, UNUSED }

var _stargate_state: StargateState = StargateState.INACTIVE
var _collision_enabled: bool = false

@export_tool_button("Switch to environment") var switch_btn = switch_to_target_environment
@export_tool_button("Update Stargate Visual") var update_visual_btn = update_stargate_visual

var stargate_subscene = preload("res://addons/living_platform_plugin/scripts/media/stargate/living_stargate_content.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_child(stargate_subscene.instantiate())
	
	var collision_area: Area3D = $"Area3D"
	# Set the collision layer/mask to the same used for Trigger the steles, with the "feet" of the camera.
	collision_area.collision_layer = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
	collision_area.collision_mask = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER

	collision_area.area_entered.connect(_on_body_entered_area)
	visibility_changed.connect(_on_visibility_changed)

	_create_stargate_visual()
	deactivate()
	_create_or_update_stargate_caption()
	scale = Vector3(0.7, 0.8, 0.7) # TO FIX: PROBABLY TO EXPOSE


## Orange glow, collisions on.
func activate() -> void:
	_stargate_state = StargateState.ACTIVE
	_apply_appearance(color_active, true)


## Gray glow, collisions off.
func deactivate() -> void:
	_stargate_state = StargateState.INACTIVE
	_apply_appearance(color_inactive, false)


## Red glow, collisions on — still usable (session state after first use).
func set_used() -> void:
	_stargate_state = StargateState.USED
	_apply_appearance(color_used, true)

## Same presentation as inactive until gameplay activates the stargate.
func set_unused() -> void:
	_stargate_state = StargateState.UNUSED
	_apply_appearance(color_inactive, false)


## Maps ACTIVATION and USE session values to stargate presentation.
## USE:USED takes priority over ACTIVATION when both are set.
func apply_presentation_state(activation_value: String = "", use_value: String = "") -> void:
	if use_value == "USED":
		set_used()
		return
	if activation_value == "ACTIVE":
		activate()
	elif activation_value == "INACTIVE":
		deactivate()
	elif use_value == "UNUSED":
		set_unused()


func _apply_appearance(color: Color, collisions_on: bool) -> void:
	albedo_color = color
	emission_color = color
	_collision_enabled = collisions_on
	update_stargate_visual()
	_update_collision_state()

## Creates the stargate visualization: a white emissive floor ring and an inclined
## yellow-orange transparent glow cone rising from it.
func _create_stargate_visual() -> void:
	if get_node_or_null("StargateRing") and get_node_or_null("StargateGlow"):
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
	ring_node.name = "StargateRing"
	ring_node.mesh = torus
	add_child(ring_node)

	# --- Inclined yellow-orange glow cone ---
	# bottom_radius, top_radius, height, lean_z (how far the top circle shifts in -Z)
	var glow_node := MeshInstance3D.new()
	glow_node.name = "StargateGlow"
	glow_node.mesh = _build_inclined_cone_mesh(
		STARGATE_CONE_BOTTOM_RADIUS,
		STARGATE_CONE_TOP_RADIUS,
		STARGATE_CONE_HEIGHT,
		STARGATE_CONE_LEAN_Z,
		STARGATE_CONE_SEGMENTS,
		STARGATE_CONE_ALPHA_BOTTOM,
		STARGATE_CONE_ALPHA_TOP
	)

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


func update_stargate_visual() -> void:
	_create_stargate_visual()

	var glow_node := get_node_or_null("StargateGlow") as MeshInstance3D
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
		# Ensure per-instance material so inspector color changes don't affect duplicated stargates.
		glow_mat = glow_mat.duplicate(true) as StandardMaterial3D

	glow_mat.resource_local_to_scene = true
	glow_node.material_override = glow_mat

	glow_mat.albedo_color = albedo_color
	glow_mat.emission = emission_color
	_create_or_update_stargate_caption()


func set_stargate_caption_text(value: String) -> void:
	stargate_caption_text = value
	if is_inside_tree():
		_create_or_update_stargate_caption()

func set_stargate_caption_scale(value: float) -> void:
	stargate_caption_scale = value
	if is_inside_tree():
		_create_or_update_stargate_caption()

func set_stargate_caption_position_y(value: float) -> void:
	stargate_caption_position_y = value
	if is_inside_tree():
		_create_or_update_stargate_caption()


func apply_settings(settings: Dictionary) -> void:
	if settings.has("target_environment_id"):
		target_environment_id = int(settings["target_environment_id"])
	if settings.has("use_scene_path"):
		use_scene_path = bool(settings["use_scene_path"])
	if settings.has("target_scene_path"):
		target_scene_path = str(settings["target_scene_path"])
	if settings.has("color_active"):
		color_active = settings["color_active"] as Color
	if settings.has("color_inactive"):
		color_inactive = settings["color_inactive"] as Color
	if settings.has("color_used"):
		color_used = settings["color_used"] as Color
	if settings.has("stargate_caption_text"):
		stargate_caption_text = str(settings["stargate_caption_text"])
	if settings.has("stargate_caption_scale"):
		stargate_caption_scale = float(settings["stargate_caption_scale"])
	if settings.has("stargate_caption_position_y"):
		stargate_caption_position_y = float(settings["stargate_caption_position_y"])
	if is_inside_tree():
		update_stargate_visual()
		_create_or_update_stargate_caption()


func _create_or_update_stargate_caption() -> void:
	var caption := get_node_or_null("StargateCaption") as LivingCaptionHud
	if not caption:
		caption = LivingCaptionHud.new(false, true)
		caption.name = "StargateCaption"
		add_child(caption)

	caption.position = Vector3(0.0, stargate_caption_position_y, -STARGATE_CONE_LEAN_Z * 0.5)
	caption.scale = Vector3.ONE * stargate_caption_scale
	caption.text_fit_mode = LivingCaption.TextFitMode.SCALE
	caption.set_display_text(stargate_caption_text)


## Builds a cone/frustum whose top circle is offset by [param lean_z] along -Z,
## giving the inclined appearance seen in the stargate reference image.
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
	if _stargate_state != StargateState.ACTIVE and _stargate_state != StargateState.USED:
		return

	# If not visible, acts as not active
	if not visible:
		return

	print("Stargate '%s' collided with node %s" % [self.name, n.name])

	# If the collision is not with the camera feet, just do nothing.
	if n.name != "CameraFeetArea3D":
		return

	# Get ref to the LivingCamera instance	
	var lc = n.get_parent().get_parent()
	assert (lc is LivingCamera)

	var camera: LivingCamera = lc as LivingCamera
	var new_camera_position := _compute_exit_position(camera)

	set_used()

	# prepare a function that will move the camera out of the stargate after the fading is done
	var post_fade_func = func():
		LivingEventManager.notify_stargate_collided(get_parent().item_id)
		camera.global_position = new_camera_position

	# Play the sound that is starting the teleport process
	LivingSceneManager.get_current_scene().play_sound(LivingConstants.AUDIO_STARGATE_ACTIVATED)

	# Fade to black, teleport while covered, then fade back in.
	camera.fade_out(LivingCamera.FADE_COLOR, post_fade_func)


## Moves the player away from the stargate horizontally so cached scene restores stay on walkable floor.
func _compute_exit_position(camera: LivingCamera) -> Vector3:
	var offset_dir := camera.global_position - global_position
	offset_dir.y = 0.0
	if offset_dir.length_squared() < 0.01:
		offset_dir = -global_transform.basis.z
		offset_dir.y = 0.0
	offset_dir = offset_dir.normalized()

	var new_pos := camera.global_position + offset_dir * CAMERA_OFFSET_AFTER_TELEPORT
	return new_pos


func _on_visibility_changed() -> void:
	_update_collision_state()


func _update_collision_state() -> void:
	var collision_area := get_node_or_null("Area3D") as Area3D
	if not collision_area:
		return

	var enabled := visible and _collision_enabled
	collision_area.set_deferred("monitoring", enabled)
	collision_area.set_deferred("monitorable", enabled)



func switch_to_target_environment() -> void:
	if use_scene_path:
		LivingSceneManager.go_to_scene(target_scene_path)
	else:
		LivingSceneManager.go_to_scene(target_environment_id)
