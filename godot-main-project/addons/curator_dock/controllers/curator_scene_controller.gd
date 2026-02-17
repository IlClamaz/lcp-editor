@tool
extends RefCounted
class_name CuratorSceneController

# ============================================================
# CuratorSceneController
# ============================================================
# Responsabilità:
# - Tutte le operazioni "scene-aware" ma NON-UI:
#   - capire se la scena aperta è una LivingScene
#   - leggere/scrivere il default globale dell'Omeka URL (EditorSettings)
#   - trovare/creare la root LivingElement (radice DB in scena)
#   - applicare l'Omeka URL alla LivingScene con Undo/Redo
#
# Nota:
# Questo controller è RefCounted: è un helper puro, senza dipendenze da Control.
# ============================================================


# Chiave salvata dentro EditorSettings (persistente per l'editor/utente).
# Serve come "default" globale per Omeka quando una scena non ha ancora l'URL settato.
const KEY_OMEKA_URL := "curator/omeka_url_default"

# Nome previsto per la root LivingElement dentro una LivingScene.
# Se il nodo esiste con questo nome, lo consideriamo la radice DB.
# Se non esiste, cerchiamo "il primo LivingElement figlio".
var root_living_element_name := "LivingRoot"


func get_living_scene(editor_interface: EditorInterface) -> LivingScene:
	# Ritorna la LivingScene attualmente aperta nell'editor (se presente).
	#
	# - Usa editor_interface.get_edited_scene_root(): è la scena che stai editando.
	# - Controlla che il root sia effettivamente un LivingScene.
	#
	# Se non c'è scena aperta o il root non è LivingScene, ritorna null.
	if editor_interface == null:
		return null
	var sr := editor_interface.get_edited_scene_root()
	if sr == null:
		return null
	return sr as LivingScene if sr is LivingScene else null


func edited_scene_root(editor_interface: EditorInterface) -> Node:
	# Helper: ritorna il root della scena attualmente editata.
	# Utile quando dobbiamo assegnare owner a nodi nuovi per renderli salvabili e visibili nel SceneTree dock.
	return null if editor_interface == null else editor_interface.get_edited_scene_root()


func load_global_default_url(editor_interface: EditorInterface) -> String:
	# Legge il default globale dell'Omeka URL dalle EditorSettings.
	#
	# - Questo valore è indipendente dalla scena: è una preferenza dell'utente/editor.
	# - Viene usato come fallback se la LivingScene non ha OMEKA_BASE_URL impostato.
	if editor_interface == null:
		return ""
	var es := editor_interface.get_editor_settings()
	return str(es.get_setting(KEY_OMEKA_URL)) if es.has_setting(KEY_OMEKA_URL) else ""


func save_global_default_url(editor_interface: EditorInterface, url: String) -> void:
	# Scrive il default globale dell'Omeka URL nelle EditorSettings.
	# Tipicamente chiamato quando l'utente modifica il campo "Globale" nel dock.
	if editor_interface == null:
		return
	var es := editor_interface.get_editor_settings()
	es.set_setting(KEY_OMEKA_URL, url)


func find_root_living_element(ls: Node) -> LivingElement:
	# Trova la root LivingElement all'interno della LivingScene.
	#
	# Strategia:
	# 1) Prima prova per nome (root_living_element_name, default: "LivingRoot")
	# 2) Se non esiste, prende il primo figlio che è un LivingElement
	#
	# Perché questa doppia strategia?
	# - Il nome rende la root "stabile" e facile da riconoscere.
	# - Il fallback permette compatibilità con scene più vecchie o manuali.
	if ls == null:
		return null

	# 1) lookup per nome (più deterministico)
	var named := ls.get_node_or_null(root_living_element_name)
	if named != null and named is LivingElement:
		return named as LivingElement

	# 2) fallback: primo figlio LivingElement
	for c in ls.get_children():
		if c is LivingElement:
			return c as LivingElement
	return null


func ensure_root_living_element(
	editor_interface: EditorInterface,
	undo_redo: EditorUndoRedoManager,
	desired_item_id: int
) -> LivingElement:
	# Garantisce che la scena corrente contenga una root LivingElement.
	#
	# - Se esiste già: aggiorna l'item_id al valore desiderato.
	# - Se non esiste: crea un nuovo LivingElement, lo aggiunge alla LivingScene e imposta owner.
	#
	# Il return è sempre la root LivingElement risultante (o null se non c'è LivingScene).

	var ls := get_living_scene(editor_interface)
	if ls == null:
		return null

	var existing := find_root_living_element(ls)
	if existing != null:
		# Caso 1: root esiste già → sync item_id (persistente)
		if undo_redo != null:
			# Con Undo/Redo: permette Ctrl+Z
			undo_redo.create_action("Set Root LivingElement item_id")
			undo_redo.add_do_property(existing, "item_id", desired_item_id)
			undo_redo.add_undo_property(existing, "item_id", existing.item_id)
			undo_redo.commit_action()
		else:
			# Fallback: set diretto
			existing.item_id = desired_item_id
		return existing

	# Caso 2: root non esiste → creazione
	if undo_redo != null:
		# Creiamo il nodo prima, poi lo "aggiungiamo" con Undo/Redo
		var new_root := LivingElement.new()
		new_root.name = root_living_element_name
		new_root.item_id = desired_item_id

		# Undo/Redo:
		# - Do: add_child
		# - Undo: remove_child
		# - Do: set_owner (per renderlo salvabile e visibile nel SceneTree)
		undo_redo.create_action("Create Root LivingElement")
		undo_redo.add_do_method(ls, "add_child", new_root)
		undo_redo.add_undo_method(ls, "remove_child", new_root)
		undo_redo.add_do_method(new_root, "set_owner", edited_scene_root(editor_interface))
		undo_redo.commit_action()
		return new_root
	else:
		# Fallback senza Undo/Redo
		var root_el := LivingElement.new()
		root_el.name = root_living_element_name
		root_el.item_id = desired_item_id
		ls.add_child(root_el)

		# owner = edited_scene_root è fondamentale:
		# - fa apparire il nodo nel SceneTree dock
		# - fa sì che venga salvato nella .tscn
		root_el.owner = edited_scene_root(editor_interface)
		return root_el


func apply_scene_url(
	editor_interface: EditorInterface,
	undo_redo: EditorUndoRedoManager,
	scene_url: String,
	global_default_url: String
) -> void:
	# Applica l'Omeka URL alla LivingScene corrente (OMEKA_BASE_URL).
	#
	# Comportamento:
	# - se scene_url è vuoto, usa global_default_url come fallback
	# - scrive la proprietà su LivingScene usando Undo/Redo quando disponibile
	#
	# Questo è importante perché LivingElement.fetch_omeka_info() legge l'URL
	# dalla LivingScene root (living_root.OMEKA_BASE_URL).

	var ls := get_living_scene(editor_interface)
	if ls == null:
		return

	# Normalizza input: rimuove spazi
	var new_url := scene_url.strip_edges()

	# Fallback al default globale se l'utente lascia vuoto
	if new_url == "":
		new_url = global_default_url.strip_edges()

	if undo_redo != null:
		# Undo/Redo completo: salva vecchio e nuovo valore
		undo_redo.create_action("Set LivingScene Omeka URL")
		undo_redo.add_do_property(ls, "OMEKA_BASE_URL", new_url)
		undo_redo.add_undo_property(ls, "OMEKA_BASE_URL", ls.OMEKA_BASE_URL)
		undo_redo.commit_action()
	else:
		# Fallback senza Undo/Redo
		ls.OMEKA_BASE_URL = new_url
