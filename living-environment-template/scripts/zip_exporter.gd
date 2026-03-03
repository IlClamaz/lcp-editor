@tool
extends EditorScript

# 1. Metti qui il percorso della tua scena principale
const MAIN_SCENE = "res://LivingEnvironmentTemplate.tscn"

# 2. Metti qui il nome dello ZIP che vuoi ottenere
const OUTPUT_ZIP = "res://export/current.zip"

func _run():
	print("--- INIZIO ESPORTAZIONE ZIP CRUDA ---")
	
	if not FileAccess.file_exists(MAIN_SCENE):
		push_error("La scena principale non esiste: ", MAIN_SCENE)
		return
	
	# Trova tutte le dipendenze in automatico
	var files_to_zip = get_all_dependencies(MAIN_SCENE)
	print("Trovati %d file da zippare." % files_to_zip.size())
	
	# Prepara il Packer ZIP
	var packer = ZIPPacker.new()
	var err = packer.open(OUTPUT_ZIP)
	if err != OK:
		push_error("Impossibile creare lo ZIP. Errore: ", err)
		return
		
	var aggiunti = 0
	# Zippa i file
	for file_path in files_to_zip:
		if not FileAccess.file_exists(file_path):
			push_error("File mancante sul disco, saltato: ", file_path)
			continue
			
		var f = FileAccess.open(file_path, FileAccess.READ)
		if f == null:
			push_error("Impossibile leggere il file: ", file_path)
			continue
			
		var content = f.get_buffer(f.get_length())
		f.close()
		
		# Rimuoviamo "res://" per creare un percorso relativo pulito nello ZIP.
		# Es: res://modelli/albero.glb diventa modelli/albero.glb
		var zip_path = file_path.replace("res://", "")
		
		packer.start_file(zip_path)
		packer.write_file(content)
		packer.close_file()
		print(" -> Zippato: ", zip_path)
		aggiunti += 1
		
	packer.close()
	print("--- ESPORTAZIONE COMPLETATA! ---")
	print("File creati: %d. Salvo in: %s" % [aggiunti, OUTPUT_ZIP])
	print("Ora puoi caricare questo ZIP su NextCloud.")


# Funzione ricorsiva per trovare tutti i file necessari alla scena
func get_all_dependencies(start_path: String) -> Array[String]:
	var all_files: Array[String] = []
	var to_check: Array[String] = [start_path]
	
	while to_check.size() > 0:
		var current = to_check.pop_back()
		if not all_files.has(current):
			all_files.append(current)
			# Se il file esiste, chiediamo a Godot quali altri file usa
			if ResourceLoader.exists(current):
				var deps = ResourceLoader.get_dependencies(current)
				for raw_d in deps:
					var d = raw_d
					
					# --- RIPULITURA UID GODOT 4 ---
					# Trova dove inizia "res://" e taglia via tutto l'UID precedente
					var res_index = d.find("res://")
					if res_index != -1:
						d = d.substr(res_index)
					# ------------------------------
						
					if not all_files.has(d) and not to_check.has(d):
						to_check.append(d)
	return all_files
