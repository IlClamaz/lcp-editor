@tool
extends LivingItem

class_name LivingElement

@export_flags(LivingConstants.ITEM_VISIBILITY_PRE_STR, LivingConstants.ITEM_VISIBILITY_POST_STR) var visibility: int = LivingConstants.ItemVisibility.PRE_EXPERIENCE | LivingConstants.ItemVisibility.POST_EXPERIENCE

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

func _enter_tree():
	super._enter_tree()
	self.add_to_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME)

func _exit_tree():
	super._exit_tree()
	if self.is_in_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME):
		self.remove_from_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME)
