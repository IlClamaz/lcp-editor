@tool
extends LivingItem

class_name LivingObject

@export var triggers_enabled: bool = true :
	set(v):
		triggers_enabled = v
		if not is_inside_tree():
			return
		apply_trigger_state()


func _ready() -> void:
	super._ready()

	self.set_meta(LivingConstants.META_EDIT_GROUP, true)

	# --- INVISIBILITA' ALLA NASCITA ---
	# Se l'oggetto non ha il meta "is_born", significa che è stato appena
	# scaricato e creato dallo script. Lo nascondiamo e gli mettiamo il meta.
	# Quando salviamo, il meta viene salvato nel file. Al Play, salterà questo blocco
	if not self.has_meta(LivingConstants.META_IS_BORN):
		self.set_meta(LivingConstants.META_IS_BORN, true)
		self.visible = false

	call_deferred("apply_trigger_state")


func _enter_tree():
	self.add_to_group(LivingConstants.RAY_PICKABLE_GROUP_NAME)


func _exit_tree():
	if self.is_in_group(LivingConstants.RAY_PICKABLE_GROUP_NAME):
		self.remove_from_group(LivingConstants.RAY_PICKABLE_GROUP_NAME)


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	await get_tree().process_frame
	apply_trigger_state()


# ==============================================================================
# TRIGGER CONTROL
# ==============================================================================
func apply_trigger_state() -> void:
	for c in get_children():
		_set_trigger_recursive(c, triggers_enabled)


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
