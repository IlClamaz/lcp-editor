@tool
extends MeshInstance3D
class_name LivingImage

@export var image_path: String = "":
	set(value):
		image_path = value
		if is_node_ready():
			_update_texture()

var pixel_size: float = 0.01

@export var diagonal: float = 1.0:
	set(value):
		diagonal = max(value, 0.01)
		if is_node_ready():
			_update_texture()

# --- Parametro per la Curvatura ---
@export var curvature: float = 0.0 :
	set(v):
		curvature = v
		if is_node_ready():
			_update_texture()

var current_texture: Texture2D
## This will be added as child and will containg the box geometry acting as background
var background: MeshInstance3D = null
## This is needed to intercept collisions for ray casting
var face_collision_shape: CollisionShape3D = null
## This is needed to trigger collisions with the walking camera
var trigger_collision_shape: CollisionShape3D = null


# The background thickness is computed as this factor of the video width
const BACKGROUND_THICKNESS_PROP: float = 0.01
# Absolute background padding size around the video area
const BACKGROUND_PADDING: float = 0
const CURVE_SEGMENTS: int = 32 
const TRIGGER_MIN_DEPTH: float = 5.0

func _ready():
	
	if background == null:
		# Background rectangle (BoxMesh)
		background = MeshInstance3D.new()
		background.mesh = BoxMesh.new()
		background.mesh.size = Vector3(1, 1, BACKGROUND_THICKNESS_PROP)  # Adjust as needed

		# The collision box to be picked up by ray cast
		face_collision_shape = CollisionShape3D.new()
		face_collision_shape.name = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE
		face_collision_shape.shape = BoxShape3D.new()

		# Collision nodes for camera trigger
		var trigger_body = StaticBody3D.new()
		trigger_body.name = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_NODE
		trigger_body.collision_layer = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
		trigger_body.collision_mask = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
		trigger_collision_shape = CollisionShape3D.new()
		trigger_collision_shape.shape = BoxShape3D.new()
		trigger_body.add_child(trigger_collision_shape)
		add_child(trigger_body)


		# The static body collecting the background geometry and the collision box
		var static_body = StaticBody3D.new()
		static_body.collision_layer = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
		static_body.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
		static_body.add_child(background)
		static_body.add_child(face_collision_shape)
		add_child(static_body)
	
	_update_texture()


func _update_texture():

	if ResourceLoader.exists(image_path):
		current_texture = load(image_path) as Texture2D

		if current_texture:
			var tex_size = current_texture.get_size()
			var effective_pixel_size := pixel_size
			var native_diagonal_px := tex_size.length()
			if native_diagonal_px > 0.0:
				effective_pixel_size = diagonal / native_diagonal_px
			var quad_size = tex_size * effective_pixel_size
			var w = quad_size.x
			var h = quad_size.y
			
			var is_flat = abs(curvature) <= 0.01
			
			# 1. Mesh Immagine (Piano Sottile a Z=0)
			var screen_mesh = _generate_curved_plane(w, h, curvature, 0.0, 0.0)
			self.mesh = screen_mesh
			
			var material = StandardMaterial3D.new()
			material.albedo_texture = current_texture
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.cull_mode = BaseMaterial3D.CULL_BACK
			self.material_override = material
			
			# Box Background
			var background_w = w + BACKGROUND_PADDING * 2
			var background_h = h + BACKGROUND_PADDING * 2
			var background_depth = background_w * BACKGROUND_THICKNESS_PROP
			
			if is_flat:
				var box = BoxMesh.new()
				box.size = Vector3(background_w, background_h, background_depth)
				background.mesh = box
				background.position = Vector3(0, 0, -1.01 * background_depth / 2.0)
			else:
				# Generiamo una vera e propria "scatola" curva che ha uno spessore (background_depth)
				background.mesh = _generate_curved_box(w, h, curvature, BACKGROUND_PADDING * 2, background_depth, -0.05)
				background.position = Vector3.ZERO
				
			# Manteniamo sempre il materiale a NULL: in questo modo userà il materiale grigio di default!
			background.material_override = null

			# 3. Collisioni
			if face_collision_shape != null:
				if is_flat:
					var box_shape = BoxShape3D.new()
					box_shape.size = Vector3(background_w, background_h, background_depth)
					face_collision_shape.shape = box_shape
					face_collision_shape.position = background.position
				else:
					# Ora il trimesh abbraccerà una vera scatola curva
					face_collision_shape.shape = background.mesh.create_trimesh_shape()
					face_collision_shape.position = Vector3.ZERO

			# 4. Collisioni Trigger
			if trigger_collision_shape != null and trigger_collision_shape.shape is BoxShape3D:
				var trigger_depth = max(background_h / 2.0, TRIGGER_MIN_DEPTH)
				trigger_collision_shape.shape.size = Vector3(background_w, 0.2, trigger_depth)
				trigger_collision_shape.position = Vector3(0, 0, trigger_depth / 2.0)
				if is_inside_tree():
					trigger_collision_shape.global_position.y = 0.1

		else:
			push_error("Couldn't load image '%s'" % [image_path])
			
	else:
		if image_path != "":
			push_error("Image path '%s' doesn't exist " % [image_path])
		current_texture = null
		mesh = null
		material_override = null


# ----------------------------------------------------------------------
# PROCEDURAL GENERATION OF THE CURVED PLANE AND BOX
# ----------------------------------------------------------------------

# Generatore Plane (usato solo per l'immagine sottilissima sul fronte)
func _generate_curved_plane(w: float, h: float, curve_deg: float, pad_total: float = 0.0, z_offset: float = 0.0) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	var is_flat = abs(curve_deg) <= 0.01
	var dir = -sign(curve_deg) if curve_deg != 0 else 1.0
	var angle_rad = 0.0
	var radius = 0.0
	var total_w = w + pad_total
	var total_h = h + pad_total

	if not is_flat:
		angle_rad = deg_to_rad(abs(curve_deg))
		radius = w / angle_rad 
		angle_rad = total_w / radius

	for i in range(CURVE_SEGMENTS + 1):
		var u = float(i) / CURVE_SEGMENTS
		var x: float; var z: float; var normal: Vector3

		if is_flat:
			x = lerp(-total_w / 2.0, total_w / 2.0, u)
			z = 0.0
			normal = Vector3(0, 0, 1)
		else:
			var current_angle = lerp(-angle_rad / 2.0, angle_rad / 2.0, u)
			x = sin(current_angle) * radius
			z = (cos(current_angle) * radius - radius) * dir
			normal = Vector3(sin(current_angle) * dir, 0, cos(current_angle)).normalized()

		var offset_vec = normal * z_offset
		st.set_normal(normal)
		st.set_uv(Vector2(u, 1.0))
		st.add_vertex(Vector3(x, -total_h / 2.0, z) + offset_vec)

		st.set_normal(normal)
		st.set_uv(Vector2(u, 0.0))
		st.add_vertex(Vector3(x, total_h / 2.0, z) + offset_vec)

	return st.commit()


# Generatore BOX 3D (disegna una "scatola" curva con spessore reale)
func _generate_curved_box(w: float, h: float, curve_deg: float, pad_total: float, thickness: float, z_offset: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var is_flat = abs(curve_deg) <= 0.01
	var dir = -sign(curve_deg) if curve_deg != 0 else 1.0

	var angle_rad = 0.0
	var radius = 0.0
	var total_w = w + pad_total
	var total_h = h + pad_total

	if not is_flat:
		angle_rad = deg_to_rad(abs(curve_deg))
		radius = w / angle_rad 
		angle_rad = total_w / radius

	# Funzione lambda per calcolare rapidamente la posizione del vertice nello spazio
	var get_v = func(i: int, y: float, z_push: float):
		var u = float(i) / CURVE_SEGMENTS
		var x = 0.0; var z = 0.0; var normal = Vector3(0, 0, 1)

		if is_flat:
			x = lerp(-total_w / 2.0, total_w / 2.0, u)
		else:
			var current_angle = lerp(-angle_rad / 2.0, angle_rad / 2.0, u)
			x = sin(current_angle) * radius
			z = (cos(current_angle) * radius - radius) * dir
			normal = Vector3(sin(current_angle) * dir, 0, cos(current_angle)).normalized()

		return {"pos": Vector3(x, y, z) + normal * z_push, "normal": normal}

	var y_top = total_h / 2.0
	var y_bot = -total_h / 2.0
	var z_front = z_offset
	var z_back = z_offset - thickness # Lo spessore "scava" la faccia posteriore all'indietro lungo la curva

	# Costruiamo il solido segmento per segmento
	for i in range(CURVE_SEGMENTS):
		# Estraiamo gli 8 vertici necessari per il cubetto curvo attuale
		var f_tl = get_v.call(i, y_top, z_front); var f_tr = get_v.call(i + 1, y_top, z_front)
		var f_bl = get_v.call(i, y_bot, z_front); var f_br = get_v.call(i + 1, y_bot, z_front)

		var b_tl = get_v.call(i, y_top, z_back); var b_tr = get_v.call(i + 1, y_top, z_back)
		var b_bl = get_v.call(i, y_bot, z_back); var b_br = get_v.call(i + 1, y_bot, z_back)

		# Faccia FRONTALE
		_add_quad(st, f_bl.pos, f_br.pos, f_tr.pos, f_tl.pos, f_tl.normal, f_tr.normal, f_tr.normal, f_tl.normal)

		# Faccia POSTERIORE (Normali invertite)
		var n_b_l = -b_tl.normal; var n_b_r = -b_tr.normal
		_add_quad(st, b_br.pos, b_bl.pos, b_tl.pos, b_tr.pos, n_b_r, n_b_l, n_b_l, n_b_r)

		# Faccia SUPERIORE
		_add_quad(st, f_tl.pos, f_tr.pos, b_tr.pos, b_tl.pos, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP)

		# Faccia INFERIORE
		_add_quad(st, b_bl.pos, b_br.pos, f_br.pos, f_bl.pos, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)

		# Faccia SINISTRA (Chiude il lato mancino del pannello, calcolata solo al primo segmento)
		if i == 0:
			var n_left = f_tl.normal.cross(Vector3.UP).normalized()
			_add_quad(st, b_bl.pos, f_bl.pos, f_tl.pos, b_tl.pos, n_left, n_left, n_left, n_left)

		# Faccia DESTRA (Chiude il lato destro del pannello, calcolata solo all'ultimo segmento)
		if i == CURVE_SEGMENTS - 1:
			var n_right = Vector3.UP.cross(f_tr.normal).normalized()
			_add_quad(st, f_br.pos, b_br.pos, b_tr.pos, f_tr.pos, n_right, n_right, n_right, n_right)

	return st.commit()


# Helper interno per tracciare 2 triangoli che formano un quad
func _add_quad(st: SurfaceTool, v1: Vector3, v2: Vector3, v3: Vector3, v4: Vector3, n1: Vector3, n2: Vector3, n3: Vector3, n4: Vector3):
	# Primo triangolo
	st.set_normal(n1); st.set_uv(Vector2(0, 1)); st.add_vertex(v1)
	st.set_normal(n2); st.set_uv(Vector2(1, 1)); st.add_vertex(v2)
	st.set_normal(n3); st.set_uv(Vector2(1, 0)); st.add_vertex(v3)
	# Secondo triangolo
	st.set_normal(n1); st.set_uv(Vector2(0, 1)); st.add_vertex(v1)
	st.set_normal(n3); st.set_uv(Vector2(1, 0)); st.add_vertex(v3)
	st.set_normal(n4); st.set_uv(Vector2(0, 0)); st.add_vertex(v4)
