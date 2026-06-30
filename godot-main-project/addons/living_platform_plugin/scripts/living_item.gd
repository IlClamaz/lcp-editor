@tool
extends Node3D
class_name LivingItem

# ==============================================================================
# COSTANTI E VARIABILI GLOBALI
# ==============================================================================
const OMEKA_TITLE_MAX_LEN: int = 200
const PARTICIPATORY_ITEM_TYPE_KEY := "lcp_form:has_participatory_item_type_f"
var MEDIA_SAVE_PATH: String = "res://downloaded_living_media"
var living_video_player_scene = preload("res://addons/living_platform_plugin/scripts/living_video.tscn")
const LIVING_SLIDESHOW_SCENE_PATH := "res://addons/living_platform_plugin/scripts/living_slideshow.tscn"
## Concrete visible medium type, set from Omeka participatory item type when instantiating.
enum MediumType {UNKNOWN, IMAGE, TEXT, VIDEO, VIDEO360, THREEDMODEL, THREEDMODELANIMATED, CROWD, SCENE, SLIDESHOW, PORTAL, SOUND}

@export var item_id: int = 0
@export_group("OMEKAS")
@export var title: String = ""
@export var modified: String = ""
@export_multiline var short_description: String = ""
@export_multiline var long_description: String = ""
@export_multiline var catalog_description: String = ""
@export var resource_class: int = 0
@export var components: Array[int] = []
@export var areas: Array[int] = []
@export var medium_uri: String = ""
@export var thumbnail_uri: String = ""

# ==============================================================================
# STATO BUILD E TRACKING
# ==============================================================================
enum BuildState { IDLE, FETCHING, SPAWNING_CHILDREN, DOWNLOADING, READY, ERROR }

signal build_state_changed(new_state: int)
signal build_finished(success: bool)
signal _dummy_success(filename: String, local_path: String, type: String)
signal _dummy_error(reason: String)

# Per tracciare lo stato dello scaricamento (quindi dei micro-cambiamenti) lato UI e capire se ci sono errori...
signal download_media_success(filename: String, path: String, type: String)
signal download_media_error(reason: String)
signal download_thumbnail_success(filename: String, path: String, type: String)
signal download_thumbnail_error(reason: String)

var _build_state: int = BuildState.IDLE  # Così teniamo traccia dello stato del nodo.
var build_state: int:
	get: return _build_state
	set(v):
		_build_state = v
		build_state_changed.emit(_build_state) # Quando cambia, mandiamo un messaggio con lo stato nuovo

var _pending_children: int = 0  # Contatore per sapere se ci sono ancora dei "figli" che devono terminare il download, quando finisce si fa -1 
var _pending_downloads: int = 0 # Simile a sopra, diventa 1 quando il nodo fa partire la richiesta HTTP per scaricare il media da Nextcloud. Torna a 0 quando il download è completato (o fallito)
var _is_using_cache: bool = false # Diventa true non appena il nodo legge il file JSON locale ed esegue il controllo (la "Probe") con Nextcloud. Se dopo i controlli scopre che deve scaricare di nuovo il file da internet (perché obsoleto o mancante), torna a false
var _must_reinstantiate_medium: bool = false # Diventa true solo ed esclusivamente se il file .glb è stato appena scaricato e sovrascritto sul disco.

# ==============================================================================
# CONTROLLI EDITOR E IMPOSTAZIONI
# ==============================================================================
@export_group("REFRESH AND MEDIUM")
@export_tool_button("Sincronizza Item da DB") var fetch_omeka_info_btn = fetch_omeka_info

@export var auto_fetch_metadata: bool = true
@export var auto_instantiate_children: bool = true
@export var auto_download_medium: bool = true
@export var auto_instantiate_medium: bool = true
@export var auto_recurse_children: bool = true

@export_tool_button("Instantiate Components and Areas") var instantiate_children_btn = instantiate_children
@export_tool_button("Instantiate Media") var instantiate_medium_btn = instantiate_medium

@export var media_filename: String
@export var media_path: String
@export var media_type: String
@export var participatory_item_type: String = ""
@export var thumbnail_path: String = ""
@export var medium_type: MediumType = MediumType.UNKNOWN
@export_group("")

func _ready() -> void:
	# true se è in esecuzione nell'editor...
	if not Engine.is_editor_hint(): print("Item '%s' ready." % self.name)

func set_item_visible(v: bool):
	for c in get_children():
		if c is LivingItem: (c as LivingItem).set_item_visible(v)

# ==============================================================================
# FLUSSO MASTER DI COSTRUZIONE DELL'ITEM
# ==============================================================================
func fetch_omeka_info():
	if auto_download_medium and not auto_instantiate_medium:
		print("Fase 1 (Download) per '%s'." % name)
	elif not auto_download_medium and auto_instantiate_medium:
		print("Fase 2 (Istanziazione) per '%s'." % name)
		
	_reset_build_tracking() # mettiamo i pending_children e pending_download a 0
	build_state = BuildState.FETCHING
	call_deferred("_run_build_process_async") # Quando l'editor è "libero" lo chiama

func _run_build_process_async() -> void:
	# Chiediamo i metadati a Omeka SOLO se ce n'è davvero bisogno
	if auto_fetch_metadata:
		var meta_ok = await _fetch_omeka_metadata_async() 
		if not meta_ok:
			_fail_build("Errore fetch JSON da Omeka per %s" % name)
			return

	# "Leggi il JSON di Omeka e, se scopri di essere composto da altri elementi o aree, 
	# crea subito i loro nodi base (es. LivingElement-1739) e attaccateli sotto".
	# genera lo scheletro della scena, quando facciamo la ricorsione
	# altrimenti lo fa solo per sè
	if auto_instantiate_children: 
		build_state = BuildState.SPAWNING_CHILDREN
		instantiate_children()

	# "Ora che hai aggiornato te stesso, prendi tutti i tuoi figli (LivingItem) 
	# e ordina anche a loro di aggiornarsi (chiamando il loro fetch_omeka_info())".
	if auto_recurse_children:
		for child in get_children():
			if child is LivingItem:
				child.auto_fetch_metadata = auto_fetch_metadata
				child.auto_instantiate_children = auto_instantiate_children
				child.auto_recurse_children = auto_recurse_children
				child.auto_download_medium = auto_download_medium
				child.auto_instantiate_medium = auto_instantiate_medium
				_begin_child_build(child) # aumenta i pending children
				child.fetch_omeka_info() # rilanciamo il flusso sui figli

	# Qui scarichiamo i media...
	# Controlla su Nextcloud se c'è un modello 3D o un'immagine legata a te. 
	# Se c'è (e se la cache è vecchia), scarica fisicamente il file .glb o .jpg nella cartella locale del PC
	if auto_download_medium:
		build_state = BuildState.DOWNLOADING
		_mark_download_started()
		await _sync_media_async()
		_mark_download_done()

	if auto_recurse_children and _pending_children > 0:
		while _pending_children > 0:
			if not is_inside_tree():
				return
			await get_tree().process_frame

	if auto_instantiate_medium:
		await _instantiate_medium_for_build()

	_try_emit_build_finished()

func _instantiate_medium_for_build() -> void:
	if Engine.is_editor_hint() and media_path != "" and _must_reinstantiate_medium:
		await _deferred_force_reimport_and_instantiate()
	else:
		await instantiate_medium()

# Quando cambia un media su nextcloud, 
# _must_reinstantiate_medium è true, quindi cancelliamo e reinstaziamo il media nuovo
func _deferred_force_reimport_and_instantiate() -> void:
	# Distruggiamo le vecchie istanze
	for child in get_children():
		if _is_living_medium_node(child):
			child.owner = null
			remove_child(child)
			child.queue_free()
			
	# Aspettiamo il prossimo frame per essere sicuri che i nodi siano spariti
	await get_tree().process_frame
	
	if not Engine.is_editor_hint() or media_path == "":
		await instantiate_medium()
		return
	
	var fs = _get_fs()
	
	# Aspettiamo se il LivingEnvironment sta ancora scansionando la Fase 1.5
	while fs.is_scanning():
		if not is_inside_tree(): return
		await get_tree().process_frame
		
	# I file .import sono già stati creati, ci basta costringere Godot a ignorare la cache
	var ext = media_path.get_extension().to_lower()
	if ext in ["glb", "gltf"]:
		var type_hint = "PackedScene"
		ResourceLoader.load(media_path, type_hint, ResourceLoader.CACHE_MODE_IGNORE)
	elif ext not in ["zip", "pck"]:
		# Ricarichiamo la RAM per tutti gli altri file (immagini, video, testi) 
		ResourceLoader.load(media_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		
	# 4. Finalmente istanziamo
	await instantiate_medium()

# ==============================================================================
# METADATA + STRUTTURA
# ==============================================================================
func _fetch_omeka_metadata_async() -> bool:
	var living_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if living_root == null: 
		return false
	
	var base_url := str(living_root.get("OMEKA_BASE_URL")).strip_edges().trim_suffix("/")
	var item_url := base_url + "/api/items?pretty_print=1&id=" + str(item_id)
	
	var response = await HTTPDownloader.request_json(self, item_url, 25.0)
	if not response.get("ok", false): 
		return false
	
	var data = response.get("json", [])
	if typeof(data) != TYPE_ARRAY or data.is_empty(): 
		return false
	var item_dict = data[0]
	if typeof(item_dict) != TYPE_DICTIONARY: 
		return false

	title = item_dict.get("o:title", "Senza Titolo")
	self.name = title.substr(0, OMEKA_TITLE_MAX_LEN)
	modified = item_dict.get("o:modified", {}).get("@value", "")
	short_description = get_omeka_text(item_dict, "lcp_form:has_short_text_f")
	long_description = get_omeka_text(item_dict, "lcp_form:has_long_text_f")
	catalog_description = get_omeka_text(item_dict, "lcp_form:has_catalogue_text_f")

	if item_dict.get("o:resource_class"): resource_class = item_dict["o:resource_class"]["o:id"]

	components.clear() # creiamo una lista di componenti
	for comp in item_dict.get("lcp_form:is_composed_of_f", []): components.append(int(comp.get("value_resource_id", 0)))
	areas.clear()
	for a in item_dict.get("lcp_form:has_participatory_area_f", []): areas.append(int(a.get("value_resource_id", 0)))

	medium_uri = ""
	if item_dict.has("lcp_form:has_URI") and typeof(item_dict["lcp_form:has_URI"]) == TYPE_ARRAY and not item_dict["lcp_form:has_URI"].is_empty(): 
		var mu = item_dict["lcp_form:has_URI"][0].get("@id")
		if mu != null: medium_uri = str(mu)

	thumbnail_uri = ""
	if item_dict.has("thumbnail_display_urls") and typeof(item_dict["thumbnail_display_urls"]) == TYPE_DICTIONARY:
		var tu = item_dict["thumbnail_display_urls"].get("square")
		if tu != null: thumbnail_uri = str(tu)

	participatory_item_type = get_omeka_text(item_dict, PARTICIPATORY_ITEM_TYPE_KEY)

	notify_property_list_changed()
	return true

# Per ottenere le varie descriptions...
func get_omeka_text(item_dict: Dictionary, key: String) -> String:
	if not item_dict.has(key): return ""
	var arr = item_dict[key]
	if typeof(arr) != TYPE_ARRAY or arr.is_empty() or typeof(arr[0]) != TYPE_DICTIONARY: return ""
	return str(arr[0].get("@value", ""))

func instantiate_children() -> void:
	var existing_children = {} # Questo serve al "refresh", se ho già un element o un'area con quell'id come figlio, non lo ricreo
	for child in get_children():
		if child is LivingItem: existing_children[child.item_id] = child

	for c in components:
		if existing_children.has(c):
			existing_children.erase(c) # semplicemente lo tolgo dalla lista
		else: # altrimenti lo creo
			var new_element := LivingElement.new() 
			new_element.item_id = c # ci appiccico l'id nel nome
			new_element.name = "LivingElement-" + str(c)
			add_child(new_element)
			if Engine.is_editor_hint(): new_element.owner = get_tree().edited_scene_root

	for a in areas:
		if existing_children.has(a):
			existing_children.erase(a)
		else:
			var new_area := LivingArea.new()
			new_area.item_id = a
			new_area.name = "LivingArea-" + str(a)
			add_child(new_area)
			if Engine.is_editor_hint(): new_area.owner = get_tree().edited_scene_root

	# il dizionario existing_children conterrà solo i nodi che erano presenti in Godot, 
	# ma che non sono stati depennati perché non c'erano nei dati di Omeka. 
	# Significa che il curatore ha cancellato quegli elementi dal database online
	for old_child in existing_children.values():  
		old_child.owner = null
		remove_child(old_child)
		old_child.queue_free()

# ==============================================================================
# DOWNLOAD / SYNC
# ==============================================================================

# DOWNLOAD DEI MEDIA

# {  Formato CACHE
#   "media_path": "", # dal downloader, dove si trova nel filesystem
#   "media_remote_content_length": "", # fp con head
#   "media_remote_etag": "", # fp con head
#   "media_remote_last_modified": "", # fp con head
#   "media_type": "", # dal downloader
#   "thumb_path": "", # dal downloader
#   "thumb_source_uri": "" # dal downloader
# }
func _sync_media_async() -> void:
	if medium_uri == "" and thumbnail_uri == "": return #ad esempio i living_area...
	
	# definiamo il percorso della cartella dell'item, così sappiamo dove scaricare
	var item_dir = MEDIA_SAVE_PATH.path_join(str(item_id)) 
	if not DirAccess.dir_exists_absolute(item_dir): DirAccess.make_dir_recursive_absolute(item_dir)
			
	var cache_path = item_dir.path_join("cache_info.json")  
	var cache_data = _read_cache(cache_path) # vediamo se esiste e se c'è la otteniamo come dizionario
	
	_is_using_cache = true 
	_must_reinstantiate_medium = false

	# Se c'è l'uri e non è una cartella /s...
	if medium_uri != "" and not _looks_like_directory_medium_uri(medium_uri):
		
		var remote_fp = await _get_remote_fingerprint_async(medium_uri, "")
		var local_fp = _build_media_fingerprint_from_cache(cache_data) # Prendiamola dalla cache, se c'è il dizionario avrà valori pieni, altrimenti vuoti
		# Il file esiste già nel filesystem?
		var file_exists = cache_data.get("media_path", "") != "" and FileAccess.file_exists(cache_data["media_path"]) 
		
		# QUA CI ENTRA SE: il file NON esiste (media mancante)
		# O se (ha una fingerprint remota valida E la fp online è DIVERSA dalla cache)
		if not file_exists or (_has_valid_media_fingerprint(remote_fp) and not _media_fingerprint_equal(remote_fp, local_fp)):
			print("Item %d: Media obsoleto o mancante. Avvio download..." % item_id)
			_is_using_cache = false # Quindi non stiamo usando la cache
			_must_reinstantiate_medium = true # Quindi dobbiamo reistanziare il media

			# QUI SCARICHIAMO EFFETTIVAMENTE, non entriamo finché non abbiamo il file
			var dl_res = await _download_file_async(medium_uri, item_dir, str(item_id) + "-", "")
			if dl_res.get("ok", false):
				media_path = dl_res["local_path"] # prendiamoli dal downloader
				media_type = dl_res["type"]
				media_filename = media_path.get_file()
				remote_fp["media_path"] = media_path # aggiorniamo la fp
				remote_fp["media_type"] = media_type
				_update_cache(cache_path, remote_fp) # mettiamo la fp nella cache
			
				if media_type == "application/zip":
					print("Item %d: È uno ZIP. Estrazione in corso (Fase 1)..." % item_id)
					_extract_zip_package(media_path, item_dir)
				
				if Engine.is_editor_hint():
					var fs = _get_fs()
					if fs != null:
						fs.update_file(media_path)
						# Aggiorniamo l'editor anche sulla cartella per fargli vedere i file estratti
						fs.update_file(item_dir)
				
				download_media_success.emit(media_filename, media_path, media_type) # aggiorniamo UI!
			else:
				download_media_error.emit(dl_res["error"])
		else:
			print("Item %d: Cache file principale valida." % item_id)
			media_path = cache_data.get("media_path", "")
			media_type = cache_data.get("media_type", "")
			if media_type == "": media_type = _get_fallback_media_type(media_path)
			media_filename = media_path.get_file()
			download_media_success.emit(media_filename, media_path, media_type)

	if thumbnail_uri != "": # Stessa cosa per la thumb e il suo path + uri...
		var thumb_exists = cache_data.get("thumb_path", "") != "" and FileAccess.file_exists(cache_data["thumb_path"])
		if not thumb_exists or cache_data.get("thumb_source_uri", "") != thumbnail_uri:
			var dl_res = await _download_file_async(thumbnail_uri, item_dir, str(item_id) + "-thumbnail-", "")
			if dl_res.get("ok", false):
				thumbnail_path = dl_res["local_path"]
				_update_cache(cache_path, {"thumb_path": thumbnail_path, "thumb_source_uri": thumbnail_uri})
				download_thumbnail_success.emit(thumbnail_path.get_file(), thumbnail_path, "image/jpeg")
			else:
				download_thumbnail_error.emit(dl_res["error"])
		else:
			thumbnail_path = cache_data.get("thumb_path", "")
			download_thumbnail_success.emit(thumbnail_path.get_file(), thumbnail_path, "image/jpeg")

func _get_fallback_media_type(path: String, header_type: String = "") -> String:
	if header_type != "" and header_type != "application/octet-stream": return header_type
	var ext = path.get_extension().to_lower()
	if ext in ["png"]: return "image/png"
	elif ext in ["jpg", "jpeg"]: return "image/jpeg"
	elif ext in ["txt"]: return "text/plain"
	elif ext in ["ogg", "ogv"]: return "video/ogg"
	elif ext in ["glb", "gltf"]: return "model/gltf-binary"
	elif ext in ["zip", "pck"]: return "application/zip"
	return "application/octet-stream"

func _get_remote_fingerprint_async(uri: String, pwd: String) -> Dictionary:
	# Facciamo una HEAD, prendiamo solo l'etichetta del file
	var head_res = await HTTPDownloader.request_head(self, uri, 10.0, pwd)
	# Poi estraiamo la fingerprint
	var fp = _build_media_fingerprint_from_headers(head_res.get("headers", []))

	# Se la HEAD dovesse fallire, facciamo una GET
	if not head_res.get("ok", false) or not _has_valid_media_fingerprint(fp):
		var get_res = await HTTPDownloader.request_probe_get(self, uri, 10.0, pwd)
		if get_res.get("ok", false): return _build_media_fingerprint_from_headers(get_res.get("headers", []))
	return fp

func _download_file_async(uri: String, local_dir: String, prefix: String, pwd: String) -> Dictionary:
	var downloader := HTTPDownloader.new(uri, local_dir, prefix, _dummy_success, _dummy_error)
	downloader.remote_pwd = pwd.strip_edges()
	add_child(downloader) # Mettiamo il nodo HTTP come figlio

	var result = {"ok": false, "local_path": "", "error": "", "type": ""} # Viene riempito dal nodo http
	downloader.success_signal.connect(func(_fname, path, type):
		result["ok"] = true
		result["local_path"] = path # Qui avremo il path nel filesystem
		result["type"] = _get_fallback_media_type(path, type) # Qui nel caso in cui type non ci venga restituito, lo inferiamo dal path
	, CONNECT_ONE_SHOT)
	
	downloader.error_signal.connect(func(err): result["error"] = err, CONNECT_ONE_SHOT)
	downloader.do_download() # Qui avviene effettivamente il downoload

	while not result["ok"] and result["error"] == "":
		if not is_instance_valid(downloader) or downloader.is_queued_for_deletion():
			if result["error"] == "" and not result["ok"]: result["error"] = "Download interrotto."
			break # In caso di errori o cancellazioni del nodo, break
		await get_tree().process_frame # Non bloccante, aspettiamo finchè result non è pieno

	return result

func _read_cache(path: String) -> Dictionary: # Trasformiamo il json in un dizionario
	if FileAccess.file_exists(path):
		# Se esiste, leggiamo e poi trasformiamo in coppie chiave-valori
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY: return parsed
	return {} # altrimenti ritorniamo

func _update_cache(path: String, new_data: Dictionary) -> void:
	var data = _read_cache(path)
	data.merge(new_data, true)
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f: 
		f.store_string(JSON.stringify(data))
		f.close()

# QUESTO FORSE VIENE TOLTO, NON SO SE NE AVREMO, per ora solo l'env
# In quel caso, lo skippa perché ritorna false
func _looks_like_directory_medium_uri(uri: String) -> bool:
	if uri == "": return false
	if uri.contains("/public.php/dav/files/"):
		var marker := "/public.php/dav/files/"
		var idx := uri.find(marker)
		if idx == -1: return false
		var rest := uri.substr(idx + marker.length()).strip_edges().trim_suffix("/")
		return rest != "" and rest.split("/").size() == 1
	if uri.contains("/s/"): return not uri.ends_with("/download")
	return false

func _build_media_fingerprint_from_headers(headers: PackedStringArray) -> Dictionary:
	# Ritorniamo un dizionario con questi 3 campi, ottenuti dalla HEAD o dalla GET
	# Prendiamo tutti e tre per sicurezza, non è detto che dal server funzioni sempre etag
	return {
		"media_remote_etag": _get_header_value(headers, "etag"),
		"media_remote_last_modified": _get_header_value(headers, "last-modified"),
		"media_remote_content_length": _get_header_value(headers, "content-length")
	}

func _build_media_fingerprint_from_cache(cache_data: Dictionary) -> Dictionary:
	return {
		"media_remote_etag": str(cache_data.get("media_remote_etag", "")).strip_edges(),
		"media_remote_last_modified": str(cache_data.get("media_remote_last_modified", "")).strip_edges(),
		"media_remote_content_length": str(cache_data.get("media_remote_content_length", "")).strip_edges()
	}

func _has_valid_media_fingerprint(fingerprint: Dictionary) -> bool: # controlla che la fingerprint non sia nulla
	return (str(fingerprint.get("media_remote_etag", "")).strip_edges() != ""
		or str(fingerprint.get("media_remote_last_modified", "")).strip_edges() != ""
		or str(fingerprint.get("media_remote_content_length", "")).strip_edges() != "")

func _media_fingerprint_equal(a: Dictionary, b: Dictionary) -> bool:
	var a_etag := str(a.get("media_remote_etag", "")).strip_edges()
	var b_etag := str(b.get("media_remote_etag", "")).strip_edges()
	var a_lm := str(a.get("media_remote_last_modified", "")).strip_edges()
	var b_lm := str(b.get("media_remote_last_modified", "")).strip_edges()
	var a_len := str(a.get("media_remote_content_length", "")).strip_edges()
	var b_len := str(b.get("media_remote_content_length", "")).strip_edges()

	# 1. Controlliamo PRIMA l'ETag, che è il dato più sicuro e assoluto
	if a_etag != "" and b_etag != "": 
		return a_etag == b_etag
		
	# 2. Se per qualche motivo manca l'ETag, usiamo la combinazione data + peso
	if a_lm != "" and b_lm != "" and a_len != "" and b_len != "": 
		return a_lm == b_lm and a_len == b_len
		
	# 3. Fallback disperati
	if a_lm != "" and b_lm != "": return a_lm == b_lm
	if a_len != "" and b_len != "": return a_len == b_len
	return false

# Legge gli header ottenuti dalla get o dalla probe per la fp e ne estrae il valore
func _get_header_value(headers: PackedStringArray, header_name: String) -> String:
	var prefix := header_name.to_lower() + ":"
	for h in headers:
		var line := str(h)
		var low := line.to_lower()
		if low.begins_with(prefix):
			return line.substr(line.find(":") + 1).strip_edges()
	return ""

# ==============================================================================
# ISTANZIAZIONE E TRACKING ERRORI
# ==============================================================================
func _is_living_medium_node(child: Node) -> bool:
	return (
		child is Living3DModel
		or child is LivingImage
		or child is LivingVideo
		or child is LivingVideo360
		or child is LivingText
		or child is LivingScene
		or child is LivingCrowd
		or child is Living3DModelAnimated
		or child is LivingSlideShow
		or child is LivingPortal
		or child is LivingAudio
		or child is AudioStreamPlayer
	)

func _participatory_type_needs_media_path(item_type: String) -> bool:
	return item_type in ["Immagine", "Video", "Video360", "Oggetto", "OggettoAnimato", "Crowd", "ModelloContenitore", "Suono"]

func _participatory_type_is_structural(item_type: String) -> bool:
	return item_type in ["Ambiente", "Area"]

func _find_living_medium_child() -> Node:
	for child in get_children():
		if _is_living_medium_node(child):
			return child
	return null

func instantiate_medium() -> void:
	if participatory_item_type == "":
		print("Skipping medium instantiation for '%s': No participatory item type." % self.name)
		return

	if _participatory_type_is_structural(participatory_item_type):
		return

	if _participatory_type_needs_media_path(participatory_item_type) and media_path == "":
		print("Skipping medium instantiation for '%s': No media path." % self.name)
		return

	# Nota particolare per lo Stargate: 
    # se è di tipo Stargate, non guardiamo il media_path ma cerchiamo direttamente se ha già un figlio portal, 
	# in quel caso non facciamo nulla (perché magari è già stato istanziato e il media è lo stesso), 
	# altrimenti lo creiamo nuovo.
	# QUESTO SI FIXA USANDO CLASSI SPECIFICHE "MIDDLE" PER I VARI MEDIA.
	if participatory_item_type == "Stargate":
		var existing_medium := _find_living_medium_child()
		if existing_medium != null:
			medium_type = MediumType.PORTAL
			return
	
	# Se stiamo usando la cache e non dobbiamo reinstanziare il medium, allora non facciamo nulla.
	if _is_using_cache and not _must_reinstantiate_medium:
		for child in get_children():
			if _is_living_medium_node(child):
				print("LivingItem: Media già presente e aggiornato.")
				return 

	for child in get_children():
		if _is_living_medium_node(child):
			child.owner = null
			remove_child(child)
			child.queue_free()
	
	var new_child = null
	self.medium_type = MediumType.UNKNOWN
	
	match participatory_item_type:
		"Immagine":
			new_child = LivingImage.new()
			new_child.name = "LivingImage-" + str(item_id)
			new_child.image_path = media_path
			medium_type = MediumType.IMAGE
		"Video":
			new_child = living_video_player_scene.instantiate()
			new_child.name = "LivingVideo-" + str(item_id)
			new_child.video_path = media_path
			medium_type = MediumType.VIDEO
		"Video360":
			new_child = LivingVideo360.new()
			new_child.name = "LivingVideo360-" + str(item_id)
			new_child.video_path = media_path
			medium_type = MediumType.VIDEO360
		"OggettoAnimato":
			new_child = Living3DModelAnimated.new()
			new_child.name = "Living3DModelAnimated-" + str(item_id)
			new_child.model_path = media_path
			medium_type = MediumType.THREEDMODELANIMATED
		"Oggetto":
			new_child = Living3DModel.new()
			new_child.name = "Living3DModel-" + str(item_id)
			new_child.model_path = media_path
			medium_type = MediumType.THREEDMODEL
		"Crowd":
			new_child = LivingCrowd.new()
			new_child.name = "LivingCrowd-" + str(item_id)
			new_child.model_path = media_path
			medium_type = MediumType.CROWD
		"ModelloContenitore":
			self.visible = true
			new_child = LivingScene.new()
			new_child.name = "LivingScene-" + str(item_id)
			new_child.pack_path = media_path
			medium_type = MediumType.SCENE
			var extract_dir = media_path.get_base_dir()
			self.set_meta("_edit_lock_", true)
			new_child.set_meta("_edit_lock_", true)
			new_child.extraction_dir = extract_dir
			new_child.entry_scene_path = extract_dir.path_join("LivingEnvironmentTemplate.tscn")
		"Slideshow":
			var slideshow_scene: PackedScene = load(LIVING_SLIDESHOW_SCENE_PATH)
			if slideshow_scene == null:
				push_error("LivingItem: impossibile caricare la scena slideshow: %s" % LIVING_SLIDESHOW_SCENE_PATH)
				return
			new_child = slideshow_scene.instantiate()
			new_child.name = "LivingSlideShow-" + str(item_id)
			if media_path != "":
				new_child.set("frame_model_path", media_path)
			medium_type = MediumType.SLIDESHOW
		"Stargate":
			new_child = LivingPortal.new()
			new_child.name = "LivingPortal-" + str(item_id)
			medium_type = MediumType.PORTAL
		"Suono":
			new_child = LivingAudio.new()
			new_child.name = "LivingAudio-" + str(item_id)
			(new_child as LivingAudio).set_audio_path(media_path)
			medium_type = MediumType.SOUND
		_:
			push_error("Unknown participatory item type '%s' for item %d" % [participatory_item_type, item_id])
			assert(self.medium_type == MediumType.UNKNOWN)
			return
	
	add_child(new_child)
	_must_reinstantiate_medium = false
	
	if Engine.is_editor_hint():
		var root = get_tree().edited_scene_root
		new_child.owner = root if root != null else self.owner
		_mark_unsaved()

func get_pending_downloads() -> int: return maxi(0, _pending_downloads) # prendiamo il massimo tra 0 e _pending_downloads
	
func _reset_build_tracking() -> void:
	_pending_children = 0
	_pending_downloads = 0

func _try_emit_build_finished() -> void:
	if _pending_children > 0 or _pending_downloads > 0: return
	build_state = BuildState.READY
	build_finished.emit(true)

func _fail_build(reason: String = "") -> void:
	if reason.strip_edges() != "": push_error(reason)
	build_state = BuildState.ERROR
	build_finished.emit(false)

func _begin_child_build(child: LivingItem) -> void:
	_pending_children += 1
	child.build_finished.connect(func(_success: bool): # Mi collego al segnale del figlio, 
		_pending_children -= 1
		_try_emit_build_finished() # quando finisce, provo a lanciare il build finished per il padre, solo effettivamente l'ultimo che finisce riuscirà a farlo lanciare
	, CONNECT_ONE_SHOT)

func _mark_download_started() -> void:
	_pending_downloads += 1
	build_state = BuildState.DOWNLOADING

func _mark_download_done() -> void:
	_pending_downloads -= 1
	if _pending_downloads < 0: _pending_downloads = 0 # Questione di sicurezza, con la rete potrebbe succedere
	_try_emit_build_finished()

func _extract_zip_package(zip_path: String, extraction_dir: String) -> void:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK: return

	var uid_regex = RegEx.new()
	uid_regex.compile(" uid=\"uid://[^\"]*\"")
	var zip_files = zip.get_files()

	for file_name in zip_files:
		var content := zip.read_file(file_name)
		var out_path := extraction_dir.path_join(file_name)

		if file_name.ends_with(".tscn") or file_name.ends_with(".tres") or file_name.ends_with(".material"):
			var text = content.get_string_from_utf8()
			var modified = false
			
			if text.find("uid=\"uid://") != -1:
				text = uid_regex.sub(text, "", true)
				modified = true
			
			for dependency in zip_files:
				var original_path = "res://" + dependency
				var new_path = extraction_dir.path_join(dependency)
				if text.find(original_path) != -1:
					text = text.replace(original_path, new_path)
					modified = true
					
			if modified: content = text.to_utf8_buffer()

		var base_dir := out_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(base_dir):
			DirAccess.make_dir_recursive_absolute(base_dir)
			
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(content)
			f.close()
			
			# Avvisiamo l'Editor di questo specifico nuovo file estratto
			if Engine.is_editor_hint():
					var fs = _get_fs()
					if fs != null:
						fs.update_file(out_path)

	zip.close()

# Funzioni helper per nascondere EditorInterface al compilatore del gioco esportato
func _get_fs():
	if not Engine.is_editor_hint(): return null
	
	# Creiamo un micro-script fantasma in RAM
	var script = GDScript.new()
	script.source_code = "func execute():\n\treturn EditorInterface.get_resource_filesystem()"
	script.reload() # Lo compiliamo al volo
	
	# Creiamo un'istanza e la eseguiamo
	var obj = script.new()
	return obj.execute()

func _mark_unsaved():
	if not Engine.is_editor_hint(): return
	
	var script = GDScript.new()
	script.source_code = "func execute():\n\tEditorInterface.mark_scene_as_unsaved()"
	script.reload()
	
	var obj = script.new()
	obj.execute()
