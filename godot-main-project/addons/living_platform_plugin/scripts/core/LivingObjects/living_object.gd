@tool
extends LivingItem

class_name LivingObject


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


func _enter_tree():
	self.add_to_group(LivingConstants.RAY_PICKABLE_GROUP_NAME)


func _exit_tree():
	if self.is_in_group(LivingConstants.RAY_PICKABLE_GROUP_NAME):
		self.remove_from_group(LivingConstants.RAY_PICKABLE_GROUP_NAME)


func instantiate_medium() -> void:
	super.instantiate_medium()
	await get_tree().process_frame
	await get_tree().process_frame
