@tool
extends LivingItem

class_name LivingElement

@export_flags(LivingConstants.ITEM_VISIBILITY_PRE_STR, LivingConstants.ITEM_VISIBILITY_POST_STR) var visibility: int = LivingConstants.ItemVisibility.PRE_EXPERIENCE | LivingConstants.ItemVisibility.POST_EXPERIENCE

@export_group("APPEARANCE")
@export var face_visible: bool = true
@export_tool_button("Apply Face Visibility") var apply_face_visibility_btn = apply_face_visibility
@export_range(-360.0, 360.0) var curvature: float = 0.0 :
	set(v):
		curvature = v
		if not is_inside_tree(): return # Evita errori all'avvio dell'editor
		
		# Troviamo il figlio 2D e lo aggiorniamo in tempo reale
		_set_curvature()


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
	call_deferred("_set_curvature")

func _enter_tree():
	self.add_to_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME)

func _exit_tree():
	if self.is_in_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME):
		self.remove_from_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME)


func instantiate_medium() -> void: 
	# Facciamo fare al LivinItem tutto il lavoro di istanziazione (Scarica e crea i nodi)
	super.instantiate_medium()
	
	# Ora che la geometria esiste, il figlio fa il suo lavoro specifico
	await get_tree().process_frame
	await get_tree().process_frame
	_set_curvature()
	apply_face_visibility()

# ==============================================================================
# CURVATURE CONTROL (Solo figli diretti)
# ==============================================================================

func _set_curvature() -> void:
	var child = _get_2d_child()
	if is_instance_valid(child):
		child.curvature = self.curvature

func _get_2d_child() -> Node:
	for child in get_children():
		if child is LivingVideo or child is LivingImage:
			return child
	return null

func _has_2d_in_children() -> bool:
	return get_children().any(func(c): return c is LivingVideo or c is LivingImage)


# ==============================================================================
# FACE VISIBILITY CONTROL
# ==============================================================================
func apply_face_visibility() -> void:
	# Nessun if iniziale, cerchiamo a tappeto in tutti i figli
	for c in get_children():
		_set_face_recursive(c, face_visible)

func _set_face_recursive(node: Node, is_vis: bool) -> void:
	# Controlliamo che sia una Mesh e che abbia il nome corretto (ignorando le maiuscole/minuscole)
	if node is MeshInstance3D and node.name.to_lower() == LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE.to_lower():
		node.visible = is_vis
	
	for child in node.get_children():
		_set_face_recursive(child, is_vis)

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
