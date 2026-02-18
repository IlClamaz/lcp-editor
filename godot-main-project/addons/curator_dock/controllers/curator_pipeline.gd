@tool
extends RefCounted
class_name CuratorPipeline

# ============================================================
# CuratorPipeline
# ============================================================
# Responsabilità:
# - Orchestrare una "pipeline" standard per i LivingElement:
#     1) fetch_omeka_info() sul nodo (popola title, components, media_uri, ecc.)
#     2) instantiate_components() (crea figli LivingElement in base a components[])
#     3) sui figli: fetch_omeka_info() e download_media() quando necessario
#
# Questa classe NON conosce UI e NON gestisce Undo/Redo:
# è un helper puro che esegue chiamate su LivingElement e reagisce ai segnali.
#
# Nota importante:
# - fetch_omeka_info() è asincrona (usa HTTPRequest e segnali).
# - Quindi la pipeline deve "aspettare" la fine del fetch usando i segnali:
#     fetch_json_success / fetch_json_error
#
# Perché CONNECT_ONE_SHOT:
# - Evita accumulo di connessioni multiple nel tempo (memory leak / doppi trigger).
# - Garantisce che la callback venga eseguita una sola volta per chiamata.
# ============================================================

func hydrate_root_and_ensure_components(root_el: LivingElement, editor_interface: EditorInterface) -> void:
	root_el.fetch_omeka_info()

	root_el.fetch_json_success.connect(func():
		ensure_components_under_root(root_el, editor_interface)

		for c in root_el.get_children():
			if c is LivingElement:
				fetch_then_download_media(c as LivingElement)
	, CONNECT_ONE_SHOT)

	root_el.fetch_json_error.connect(func(reason: String):
		push_warning("Fetch root fallito (%s): %s" % [root_el.name, reason])
	, CONNECT_ONE_SHOT)



func ensure_components_under_root(root_el: LivingElement, editor_interface: EditorInterface) -> void:
	for cid in root_el.components:
		var id := int(cid)
		if _has_direct_child_with_item_id(root_el, id):
			continue

		var new_el := LivingElement.new()
		new_el.item_id = id
		new_el.name = "LivingElement-%d" % id
		root_el.add_child(new_el)

		# owner per persistere in scena editata
		if Engine.is_editor_hint() and editor_interface != null:
			new_el.owner = editor_interface.get_edited_scene_root()



func _has_direct_child_with_item_id(parent: Node, id: int) -> bool:
	for c in parent.get_children():
		if c is LivingElement and int((c as LivingElement).item_id) == id:
			return true
	return false


func fetch_then_download_media(le: LivingElement) -> void:
	le.fetch_omeka_info()

	le.fetch_json_success.connect(func():
		if str(le.media_uri).strip_edges() != "" and str(le.media_path).strip_edges() == "":
			le.download_media()
	, CONNECT_ONE_SHOT)

	le.fetch_json_error.connect(func(reason: String):
		push_warning("Fetch child fallito (#%d): %s" % [le.item_id, reason])
	, CONNECT_ONE_SHOT)




