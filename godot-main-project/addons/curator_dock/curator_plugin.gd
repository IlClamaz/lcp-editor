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
const CURATOR_PROFILE_NAME = "Curator"
const DEVELOPER_PROFILE_NAME = "Developer"
const PROFILE_BASE_DIR = "res://addons/curator_dock/profiles"

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
	dock = preload("res://addons/curator_dock/docks/curator_dock.gd").new()

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
	dock.undo_redo = get_undo_redo()

	# Nome del pannello come appare nella UI dei dock dell’editor.
	dock.name = "Curator"

	# Aggancia il dock alla UI dell’editor.
	# DOCK_SLOT_RIGHT_UL = dock a destra in alto (upper-left della colonna destra).
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

	if not scene_saved.is_connected(_on_scene_saved):
		scene_saved.connect(_on_scene_saved)

	# Usiamo call_deferred per applicare il profilo in modo sicuro 
	# solo quando l'interfaccia di Godot ha finito di caricarsi
	call_deferred("_setup_environment")

func _setup_environment() -> void:
	var dev_profile_path = PROFILE_BASE_DIR.path_join(DEVELOPER_PROFILE_NAME + ".profile")
	var cur_profile_path = PROFILE_BASE_DIR.path_join(CURATOR_PROFILE_NAME + ".profile")
	
	var selected_profile_name = ""
	var selected_profile_source = ""
	
	# --- LOGICA DI FALLBACK ---
	if FileAccess.file_exists(dev_profile_path):
		selected_profile_name = DEVELOPER_PROFILE_NAME
		selected_profile_source = dev_profile_path
	elif FileAccess.file_exists(cur_profile_path):
		selected_profile_name = CURATOR_PROFILE_NAME
		selected_profile_source = cur_profile_path
	else:
		push_warning("Curator Plugin: Nessun profilo trovato (né Developer né Curator) in " + PROFILE_BASE_DIR)
		return

	# 1. Copiamo e applichiamo il profilo Editor
	_apply_profile(selected_profile_name, selected_profile_source)
	
	# 2. Gestione intelligente della Console (Output)
	var settings = EditorInterface.get_editor_settings()
	if settings != null:
		if selected_profile_name == CURATOR_PROFILE_NAME:
			# Per i curatori: spegniamo l'apertura automatica della console
			settings.set("run/output/always_open_output_on_play", false)
		else:
			# Per i dev: la riattiviamo per comodità di debug
			settings.set("run/output/always_open_output_on_play", true)

func _apply_profile(profile_name: String, source_path: String) -> void:
	var editor_paths = EditorInterface.get_editor_paths()
	var config_dir = editor_paths.get_config_dir()
	var profiles_dir = config_dir.path_join("feature_profiles")
	var target_profile_path = profiles_dir.path_join(profile_name + ".profile")
	
	# Creiamo la cartella "feature_profiles" globale nel PC dell'utente se non esiste
	if not DirAccess.dir_exists_absolute(profiles_dir):
		DirAccess.make_dir_recursive_absolute(profiles_dir)
		
	# Copiamo fisicamente il file dal progetto al PC
	var content = FileAccess.get_file_as_string(source_path)
	var f = FileAccess.open(target_profile_path, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()
		
	# Ordiniamo a Godot di attivare il profilo scelto
	EditorInterface.set_current_feature_profile(profile_name)
	print("Curator Plugin: Ambiente configurato con successo (Profilo: '%s')" % profile_name)


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
	
	if scene_saved.is_connected(_on_scene_saved):
		scene_saved.disconnect(_on_scene_saved)

func _on_scene_saved(filepath: String) -> void:
	if is_instance_valid(dock) and dock.has_method("_toast"):
		dock.call("_toast", "Salvato: %s" % filepath.get_file(), 2)
