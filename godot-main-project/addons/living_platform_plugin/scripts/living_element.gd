@tool
extends LivingItem

class_name LivingElement

@export_flags(LivingConstants.ITEM_VISIBILITY_PRE_STR, LivingConstants.ITEM_VISIBILITY_POST_STR) var visibility: int = LivingConstants.ItemVisibility.PRE_EXPERIENCE | LivingConstants.ItemVisibility.POST_EXPERIENCE

@export_group("APPEARANCE")
@export var face_visible: bool = true :
	set(v):
		face_visible = v
		if not is_inside_tree():
			return
		apply_face_visibility()
@export var triggers_enabled: bool = true :
	set(v):
		triggers_enabled = v
		if not is_inside_tree():
			return
		apply_trigger_state()
@export_range(-360.0, 360.0) var curvature: float = 0.0 :
	set(v):
		curvature = v
		if not is_inside_tree(): return # Evita errori all'avvio dell'editor
		_set_curvature()

@export_range(0.01, 50.0) var diagonal: float = 1.0 :
	set(v):
		diagonal = max(v, 0.01)
		if not is_inside_tree(): return
		_set_pixel_size()


func _ready() -> void:
	super._ready()
	
	self.set_meta("_edit_group_", true)
	
	# --- INVISIBILITA' ALLA NASCITA ---
	# Se l'oggetto non ha il meta "is_born", significa che è stato appena
	# scaricato e creato dallo script. Lo nascondiamo e gli mettiamo il meta.
	# Quando salviamo, il meta viene salvato nel file. Al Play, salterà questo blocco
	if not self.has_meta("is_born"):
		self.set_meta("is_born", true)
		self.visible = false

	call_deferred("apply_face_visibility")
	call_deferred("apply_trigger_state")
	call_deferred("_set_curvature")
	call_deferred("_set_pixel_size")


func _enter_tree():
	self.add_to_group(LivingConstants.RAY_PICKABLE_GROUP_NAME)


func _exit_tree():
	if self.is_in_group(LivingConstants.RAY_PICKABLE_GROUP_NAME):
		self.remove_from_group(LivingConstants.RAY_PICKABLE_GROUP_NAME)


func instantiate_medium() -> void: 
	# Facciamo fare al LivinItem tutto il lavoro di istanziazione (Scarica e crea i nodi)
	super.instantiate_medium()
	
	# Ora che la geometria esiste, il figlio fa il suo lavoro specifico
	await get_tree().process_frame
	await get_tree().process_frame
	_set_curvature()
	_set_pixel_size()
	apply_face_visibility()
	apply_trigger_state()

# ==============================================================================
# CURVATURE and DIAGONAL CONTROL
# ==============================================================================

func _set_curvature() -> void:
	var child = _get_2d_child()
	if is_instance_valid(child):
		child.curvature = self.curvature

func _set_pixel_size() -> void:
	var child = _get_2d_child()
	if is_instance_valid(child):
		if "diagonal" in child:
			child.diagonal = diagonal
			return

func _get_2d_child() -> Node:
	for child in get_children():
		if child is LivingVideo or child is LivingImage or child is LivingSlideShow:
			return child
	return null

func _has_2d_in_children() -> bool:
	return get_children().any(func(c): return c is LivingVideo or c is LivingImage or c is LivingSlideShow)


func _map_pixel_size_from_target_diagonal(child: Node, diagonal_m: float) -> float:
	var native_size := _get_native_media_size(child)
	if native_size.x <= 0.0 or native_size.y <= 0.0:
		return -1.0

	var native_diagonal_px := native_size.length()
	if native_diagonal_px <= 0.0:
		return -1.0

	return diagonal_m / native_diagonal_px


func _get_native_media_size(child: Node) -> Vector2:
	if child is LivingImage:
		var image := child as LivingImage
		if image.current_texture != null:
			return image.current_texture.get_size()
		return Vector2.ZERO

	if child is LivingVideo:
		var video := child as LivingVideo
		if video.viewport != null:
			return Vector2(video.viewport.size)
		return Vector2.ZERO

	return Vector2.ZERO


# ==============================================================================
# FACE and TRIGGER VISIBILITY CONTROL
# ==============================================================================
func apply_face_visibility() -> void:
	# Nessun if iniziale, cerchiamo a tappeto in tutti i figli
	for c in get_children():
		_set_face_recursive(c, face_visible)


func apply_trigger_state() -> void:
	for c in get_children():
		_set_trigger_recursive(c, triggers_enabled)

func _set_face_recursive(node: Node, is_vis: bool) -> void:
	# Controlliamo che sia una Mesh e che abbia il nome corretto (ignorando le maiuscole/minuscole)
	if node is MeshInstance3D and node.name.to_lower() == LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE.to_lower():
		node.visible = is_vis
	
	for child in node.get_children():
		_set_face_recursive(child, is_vis)


func _set_trigger_recursive(node: Node, is_enabled: bool) -> void:
	if node.name.to_lower() == LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_NODE.to_lower():
		_set_trigger_collision_state_for_subtree(node, is_enabled)

	for child in node.get_children():
		_set_trigger_recursive(child, is_enabled)


func _set_trigger_collision_state_for_subtree(root: Node, is_enabled: bool) -> void:
	var targets: Array[CollisionObject3D] = []
	if root is CollisionObject3D:
		targets.append(root as CollisionObject3D)

	for subchild in root.find_children("*", "CollisionObject3D", true, false):
		var collision_obj := subchild as CollisionObject3D
		if collision_obj:
			targets.append(collision_obj)

	for collision_obj in targets:
		if not collision_obj.has_meta("default_collision_layer"):
			collision_obj.set_meta("default_collision_layer", collision_obj.collision_layer)
		if not collision_obj.has_meta("default_collision_mask"):
			collision_obj.set_meta("default_collision_mask", collision_obj.collision_mask)

		if is_enabled:
			collision_obj.collision_layer = int(collision_obj.get_meta("default_collision_layer"))
			collision_obj.collision_mask = int(collision_obj.get_meta("default_collision_mask"))
		else:
			collision_obj.collision_layer = 0
			collision_obj.collision_mask = 0

		if collision_obj is Area3D:
			var area := collision_obj as Area3D
			area.monitoring = is_enabled
			area.monitorable = is_enabled

func _has_face_in_children() -> bool:
	# Avviamo la scansione per dire al Dock se accendere o no il bottone
	for c in get_children():
		if _find_face_recursive(c):
			return true
	return false

func _find_face_recursive(node: Node) -> bool:
	# Stesso controllo case-insensitive anche qui
	if node is MeshInstance3D and node.name.to_lower() == LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE.to_lower():
		return true
		
	for child in node.get_children():
		if _find_face_recursive(child):
			return true
			
	return false
