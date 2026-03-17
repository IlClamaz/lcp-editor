@tool
extends Node3D
class_name LivingScene

## LivingScene si occupa di estrarre e istanziare dinamicamente un pacchetto ZIP 
## contenente una scena Godot (e le sue dipendenze) scaricato in precedenza.

# --- VARIABILI ESPORTATE ---
## Il percorso assoluto o relativo al file ZIP scaricato (es. "res://downloaded/123/123.zip")
@export var pack_path: String = ""                 
## Il percorso del file di scena principale da istanziare DOPO l'estrazione
@export var entry_scene_path: String = ""          
## La cartella di destinazione in cui verranno scompattati i file
@export var extraction_dir: String = "res://"  
## Se true, sovrascrive i file preesistenti con lo stesso nome durante l'estrazione
@export var replace_files: bool = true
## Se true, tenta di caricare automaticamente la scena non appena il nodo entra nell'albero
@export var auto_load_on_ready: bool = true

## Bottone esposto nell'Inspector dell'Editor per lanciare manualmente l'estrazione
@export_tool_button("Load Scene from ZIP") var load_scene_btn = load_scene

func _ready() -> void:
	# call_deferred assicura che il nodo sia completamente inizializzato prima di agire
	if auto_load_on_ready and pack_path != "" and entry_scene_path != "":
		call_deferred("load_scene")

## Metodo principale: Pulisce, estrae, ri-mappa i percorsi e istanzia la scena.
func load_scene() -> void:
	if not is_inside_tree(): return

	if get_child_count() > 0:
		if Engine.is_editor_hint() and auto_load_on_ready:
			print("LivingScene: Oggetti già presenti. Salto.")
			return
		for child in get_children():
			remove_child(child)
			child.queue_free()
		await get_tree().process_frame
		if not is_inside_tree(): return

	if entry_scene_path == "" or not FileAccess.file_exists(entry_scene_path):
		push_error("LivingScene: Scena non trovata in " + entry_scene_path)
		return

	print("LivingScene: Caricamento scena estratta...")
	var ps = ResourceLoader.load(entry_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if ps == null: return

	var inst = ps.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE if Engine.is_editor_hint() else 0)
	call_deferred("_add_and_own_safely", inst)

func _add_and_own_safely(nodo_istanziato: Node) -> void:
	# 1. Aggiungiamo il nodo all'albero
	add_child(nodo_istanziato)
	
	# 2. Posizioniamo la scena 
	if nodo_istanziato is Node3D:
		nodo_istanziato.position = Vector3.ZERO
		nodo_istanziato.scale = Vector3.ONE

	# 3. Impostiamo l'owner e blocchiamo i nodi
	if Engine.is_editor_hint():
		var root = get_tree().edited_scene_root
		if root != null:
			# Settiamo l'owner SOLO del nodo radice, non dei figli
			# Questo preserva l'integrità della scena senza creare cloni.
			nodo_istanziato.owner = root
			
			# Applichiamo il lucchetto a tutti in modo sicuro
			_lock_nodes_recursive(nodo_istanziato)


func _lock_nodes_recursive(node: Node) -> void:
	# Blocchiamo l'oggetto nell'Editor 3D senza alterare l'owner
	node.set_meta("_edit_lock_", true)
	
	for child in node.get_children():
		_lock_nodes_recursive(child)
