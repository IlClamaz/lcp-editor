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
	# --- PROTEZIONE INIZIALE ---
	if not is_inside_tree(): 
		return

	# 1. PULIZIA: Rimuove eventuali scene precedentemente caricate per evitare duplicati
	for child in get_children():
		child.queue_free()

	if pack_path == "":
		push_error("LivingScene: pack_path is empty")
		return

	# 2. SINCRONIZZAZIONE CON L'EDITOR: 
	if Engine.is_editor_hint():
		var fs = EditorInterface.get_resource_filesystem()
		while fs.is_scanning():
			# Protezione dentro il loop (se veniamo cancellati mentre aspettiamo)
			if not is_inside_tree(): return 
			await get_tree().process_frame
			
		# Protezione prima di far partire il timer
		if not is_inside_tree(): return 
		await get_tree().create_timer(0.2).timeout

	# 3. VERIFICA FILE SORGENTE
	if not FileAccess.file_exists(pack_path):
		push_error("LivingScene: File non trovato: " + pack_path)
		return

	print("LivingScene: Estrazione del pacchetto ZIP...")
	
	# Inizializziamo il lettore ZIP nativo di Godot
	var zip := ZIPReader.new()
	var err := zip.open(pack_path)
	if err != OK:
		push_error("LivingScene: Il file non è un file ZIP valido o è corrotto.")
		return
	
	# Creiamo la cartella di destinazione se non esiste già
	if not DirAccess.dir_exists_absolute(extraction_dir):
		DirAccess.make_dir_recursive_absolute(extraction_dir)
	
	var zip_files = zip.get_files()
	var files_extracted = 0
	
	# 4. PREPARAZIONE REGEX PER GLI UID:
	# I file di Godot 4 salvano gli UID (es: uid="uid://abcd123"). 
	# Spostando i file in una nuova cartella tramite estrazione, gli UID si corrompono.
	# Questa espressione regolare ci servirà per trovarli ed eliminarli.
	var uid_regex = RegEx.new()
	uid_regex.compile(" uid=\"uid://[^\"]*\"")
	
	# 5. CICLO DI ESTRAZIONE E MODIFICA "AL VOLO"
	for file_name in zip_files:
		var content := zip.read_file(file_name)
		var out_path := extraction_dir.path_join(file_name)
		
		# Se il file è un testo che definisce una scena o una risorsa (es. materiali)...
		if file_name.ends_with(".tscn") or file_name.ends_with(".tres") or file_name.ends_with(".material"):
			var text = content.get_string_from_utf8()
			var modified = false
			
			# STEP A: Rimuoviamo gli UID per forzare Godot a usare i nostri nuovi percorsi (testuali)
			if text.find("uid=\"uid://") != -1:
				text = uid_regex.sub(text, "", true) # 'true' applica la sostituzione globale
				modified = true
			
			# STEP B: Relocazione dinamica dei percorsi.
			# Cerchiamo i vecchi percorsi assoluti (es. res://texture.png) 
			# e li aggiorniamo alla nuova sottocartella (es. res://cartella/texture.png)
			for dependency in zip_files:
				var original_path = "res://" + dependency
				var new_path = extraction_dir.path_join(dependency)
				
				if text.find(original_path) != -1:
					text = text.replace(original_path, new_path)
					modified = true
					
			# Se il file è stato alterato, lo riconvertiamo in un buffer di byte per il salvataggio
			if modified:
				content = text.to_utf8_buffer()
		# -----------------------------------------------------
		
		# Crea eventuali sottocartelle interne allo ZIP (es. "assets/texture.png")
		var base_dir := out_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(base_dir):
			DirAccess.make_dir_recursive_absolute(base_dir)
			
		# Scrive fisicamente il file sul disco
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(content)
			f.close()
			files_extracted += 1
			print(" -> File estratto in: ", out_path)

	zip.close()
	print("LivingScene: Estratti %d file con successo in %s." % [files_extracted, extraction_dir])

	# --- 6. SINCRONIZZAZIONE PULITA CON GODOT ---
	if Engine.is_editor_hint() and is_inside_tree():
		var fs = EditorInterface.get_resource_filesystem()
		
		# Diamo il tempo al sistema operativo di rilasciare i file appena estratti
		await get_tree().process_frame
		fs.scan()
		
		while fs.is_scanning():
			if not is_inside_tree(): return
			await get_tree().process_frame
			
		# Buffer extra: diamo a Godot il tempo di far partire i task sui .glb estratti
		for i in range(30):
			if not is_inside_tree(): return
			await get_tree().process_frame

	# 7. CARICAMENTO DELLA SCENA PRINCIPALE (POLLING GENTILE)
	if not FileAccess.file_exists(entry_scene_path):
		push_error("LivingScene: La scena di destinazione non esiste: " + entry_scene_path)
		return

	var ps = null
	var attempts = 0
	
	while ps == null and attempts < 30:
		ps = ResourceLoader.load(entry_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
		if ps == null:
			attempts += 1
			print("LivingScene: Attesa dipendenze per %s (Tentativo %d/30)..." % [entry_scene_path.get_file(), attempts])
			# Rallentiamo i tentativi a 30 frame (~0.5s) per non far collidere i dialoghi di Godot!
			for i in range(30): 
				if not is_inside_tree(): return
				await get_tree().process_frame

	if ps == null:
		push_error("LivingScene: Impossibile caricare la scena dopo svariati tentativi: " + entry_scene_path)
		return

	print("LivingScene: SCENA CARICATA CON SUCCESSO!")
	var inst = ps.instantiate()
	
	# Diciamo a Godot di aggiungere il nodo, settare le posizioni, 
	# impostare l'owner e bloccarlo in un colpo solo, ma nel frame successivo e in modo sicuro!
	call_deferred("_add_and_own_safely", inst)

# --- FUNZIONI DI SUPPORTO ---

func _add_and_own_safely(nodo_istanziato: Node) -> void:
	# 1. Aggiungiamo il nodo all'albero (ora è sicuro!)
	add_child(nodo_istanziato)
	
	# 2. Posizioniamo la scena 
	if nodo_istanziato is Node3D:
		nodo_istanziato.position = Vector3.ZERO
		nodo_istanziato.scale = Vector3.ONE

	# 3. Impostiamo l'owner e blocchiamo i nodi ricorsivamente
	if Engine.is_editor_hint():
		var root = get_tree().edited_scene_root
		if root != null:
			_lock_and_own_recursive(nodo_istanziato, root)


func _lock_and_own_recursive(node: Node, tree_root: Node) -> void:
	# Impostiamo l'owner (fondamentale per poter salvare la scena nell'Editor)
	node.owner = tree_root
	
	# Blocchiamo l'oggetto nell'Editor 3D
	node.set_meta("_edit_lock_", true)
	
	# Lo facciamo per tutti i suoi figli!
	for child in node.get_children():
		_lock_and_own_recursive(child, tree_root)
