@tool
extends EditorPlugin

# ============================================================
# Curator Editor Plugin
# ============================================================
# Questo è lo script che Godot carica quando abiliti il plugin in:
#   Project Settings → Plugins
#
# Responsabilità:
# - Creare il dock (pannello UI) del curatore
# - Iniettarci le dipendenze editoriali (EditorInterface, UndoRedo)
# - Agganciarlo a un DOCK_SLOT dell’editor
# - Rimuoverlo e liberarlo quando il plugin viene disabilitato
# ============================================================

# Riferimento al dock creato (Control) così possiamo rimuoverlo e fare cleanup.
var dock: Control


func _enter_tree() -> void:
	# Chiamato quando il plugin viene attivato (o quando il progetto viene caricato con plugin già attivo).
	# Qui è il momento giusto per:
	# - istanziare la UI del dock
	# - collegarla all'editor (editor_interface / undo_redo)
	# - aggiungerla alla UI dell’Editor.

	print("Curator plugin loaded, adding dock...")

	# Istanzia il dock:
	# - preload(...) carica lo script della UI
	# - .new() crea l'istanza del Control definito in curator_dock.gd
	#
	# Nota: questa è una "UI dinamica" (non una .tscn), quindi creata da codice.
	dock = preload("res://addons/curator_dock/curator_dock.gd").new()

	# Inietta l’EditorInterface (serve al dock per:
	# - leggere la scena editata (get_edited_scene_root)
	# - accedere alle EditorSettings (salvataggio url globale)
	# - e più in generale dialogare con l'editor.
	dock.editor_interface = get_editor_interface()

	# Inietta l’UndoRedo manager.
	# In Godot 4.x, EditorPlugin espone get_undo_redo(), che ritorna un EditorUndoRedoManager.
	# Serve per registrare operazioni come:
	# - creare nodi
	# - modificare proprietà (item_id, OMEKA_BASE_URL)
	# - spostare nodi (auto layout)
	#
	# ✅ In Godot 4.5 è corretto farlo così.
	dock.undo_redo = get_undo_redo()

	# Nome del pannello come appare nella UI dei dock dell’editor.
	dock.name = "Curator"

	# Aggancia il dock alla UI dell’editor.
	# DOCK_SLOT_RIGHT_UL = dock a destra in alto (upper-left della colonna destra).
	# Puoi cambiare slot se preferisci un'altra posizione.
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	# Chiamato quando il plugin viene disattivato (o l'editor sta chiudendo).
	# Qui dobbiamo ripulire:
	# - rimuovere il dock dai docks dell'editor
	# - liberare l'istanza (queue_free) per evitare leak / doppie istanze

	if dock and is_instance_valid(dock):
		# Rimuove la UI dalla zona dock dell'editor
		remove_control_from_docks(dock)

		# Libera il nodo UI
		dock.queue_free()
