@tool
extends Node3D

class_name LivingItem

var MEDIA_SAVE_PATH: String = "res://downloaded_living_media"

# When an Element info are fetched from OmekaS, the object name is set to the item title.
# However, some titles are too long. So, we chop them to this number of characters.
const OMEKA_TITLE_MAX_LEN: int = 200

## The prototype scene to instantiate video players
var living_video_player_scene = preload("res://addons/living_platform_plugin/scripts/living_video.tscn")

#
# Main OmekaS properties
## The item id, taken from the OmekaS database
@export var item_id: int = 0

@export_group("OMEKAS")
@export var title: String = ""
@export var modified: String = ""
@export_multiline var short_description: String = ""
@export_multiline var long_description: String = ""
@export_multiline var catalog_description: String = ""
@export var resource_class: int = 0
## Corresponding to lcp_form:is_composed_of_f
@export var components: Array[int] = []
## Corresponding to lcp_form:has_participatory_area_f
@export var areas: Array[int] = []
# E.g.:
# "https://nextcloud.livingculture.it/s/rB3oKHRzcRQfERs/download"
# or
# "http://nextcloud.livingculture.it/public.php/dav/files/C4tEyTMpEyz3gTY/Duck.glb"
## From lcp_form:has_URI
@export var medium_uri: String = ""
## From "thumbnail_display_urls" --> "square"
@export var thumbnail_uri: String = ""

# ------------------------------------------------------------
# BUILD / ASYNC TRACKING + DOWNLOADS PROGRESS
# ------------------------------------------------------------

enum BuildState { IDLE, FETCHING, SPAWNING_CHILDREN, DOWNLOADING, READY, ERROR }

signal build_state_changed(new_state: int)
signal build_finished(success: bool)

var _build_state: int = BuildState.IDLE
var build_state: int:
	get: return _build_state
	set(v):
		_build_state = v
		build_state_changed.emit(_build_state)

var _pending_children: int = 0
var _pending_downloads: int = 0
var _finished_emitted: bool = false
var _build_started: bool = false
var _is_using_cache: bool = false

# The OmekaS info that we don't need to display at the moment
var item_sets: Array[int] = []
var media: Array[int] = []


@export_group("REFRESH AND MEDIUM")
@export_tool_button("Fetch Omeka Info") var fetch_omeka_info_btn = fetch_omeka_info
## After fetch, automatically instantiate all children
@export var auto_instantiate_children: bool = true
## After fetch, automatically download the linked medium_uri
@export var auto_download_medium: bool = true
## After medium download, automatically instantiate it
@export var auto_instantiate_medium: bool = true
## After instantiating all children, copy refresh values and iterate children
@export var auto_recurse_children: bool = true

## When true, the media are not downloaded during recursive instantiation.
@export var metadata_only: bool = false

@export_tool_button("Instantiate Components and Areas") var instantiate_children_btn = instantiate_children
# @export_tool_button("Instantiate Media") var instantiate_media_btn = instantiate_media
@export_tool_button("Download Media") var download_medium_btn = download_medium
@export_tool_button("Instantiate Media") var instantiate_medium_btn = instantiate_medium
@export var media_filename: String
@export var media_path: String
@export var media_type: String
@export var thumbnail_path: String = ""
@export_group("")


## SIGNALS ##
signal fetch_json_success()
signal fetch_json_error(reason: String)

signal download_media_success(filename: String, path: String, type: String)
signal download_media_error(reason: String)

signal download_thumbnail_success(filename: String, path: String, type: String)
signal download_thumbnail_error(reason: String)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("Item '%s' ready." % [self.name])


func _enter_tree():
	# print("Living Item Tree Enter.")
	fetch_json_success.connect(_on_json_fetch_success, CONNECT_DEFERRED)
	fetch_json_error.connect(_on_json_fetch_error, CONNECT_DEFERRED)
	
	download_media_success.connect(_on_download_media_success, CONNECT_DEFERRED)
	download_media_error.connect(_on_download_media_error, CONNECT_DEFERRED)

	download_thumbnail_success.connect(_on_download_thumbnail_success, CONNECT_DEFERRED)
	download_thumbnail_error.connect(_on_download_thumbnail_error, CONNECT_DEFERRED)

func _exit_tree():
	# print("Living Item Tree Exit.")
	fetch_json_success.disconnect(_on_json_fetch_success)
	fetch_json_error.disconnect(_on_json_fetch_error)
	
	download_media_success.disconnect(_on_download_media_success)
	download_media_error.disconnect(_on_download_media_error)

	download_thumbnail_success.disconnect(_on_download_thumbnail_success)
	download_thumbnail_error.disconnect(_on_download_thumbnail_error)


func _on_json_fetch_success():
	self.name = title.substr(0, OMEKA_TITLE_MAX_LEN)

	# 1) Download medium (se richiesto)
	# NB: qui NON incrementiamo pending: lo facciamo dentro download_medium() quando parte davvero
	if auto_download_medium:
		download_medium()

	# 2) Instantiate children
	if auto_instantiate_children:
		build_state = BuildState.SPAWNING_CHILDREN
		instantiate_children()

	# 3) Recurse into children (se richiesto)
	if auto_recurse_children:
		for child in get_children():
			if child is LivingItem:
				# Propaga flag al figlio
				child.auto_instantiate_children = auto_instantiate_children
				child.auto_recurse_children = auto_recurse_children
				child.auto_download_medium = auto_download_medium
				child.auto_instantiate_medium = auto_instantiate_medium
				child.metadata_only = metadata_only

				_begin_child_build(child as LivingItem)
				child.call_deferred("fetch_omeka_info")

	# 4) Se non abbiamo nulla in pending (nessun figlio, nessun download), chiudi subito
	_try_emit_build_finished()



func _on_json_fetch_error(err: String):
	title = err
	_fail_build("Fetch JSON error on %s: %s" % [name, err])


func _on_download_media_success(filename, path, type):
	media_filename = filename
	media_path = path
	media_type = type
	
	# --- FALLBACK PER IL TIPO DI MEDIA ---
	if media_type == "" or media_type == null or media_type == "application/octet-stream":
		var ext = media_path.get_extension().to_lower() # controlliamo come finisce il file...
		if ext in ["png"]: media_type = "image/png"
		elif ext in ["jpg", "jpeg"]: media_type = "image/jpeg"
		elif ext in ["txt"]: media_type = "text/plain"
		elif ext in ["ogg", "ogv"]: media_type = "video/ogg"
		elif ext in ["glb", "gltf"]: media_type = "model/gltf-binary"
		elif ext in ["zip", "pck"]: media_type = "application/zip"

	print("Download media '%s' success (Type: %s). Visualize it." % [media_path, media_type])

	# Salviamo in cache l'esatto percorso e formato del file principale scaricato
	_update_cache_data({"media_path": media_path, "media_type": media_type})

	# --- SALTIAMO L'ATTESA SE USIAMO LA CACHE ---
	# Se il file è appena stato scaricato (non cache), aspettiamo Godot.
	# Se è in cache, saltiamo la coda e istanziamo all'istante!
	if Engine.is_editor_hint() and self.is_inside_tree() and not _is_using_cache:
		_wait_for_godot_import_and_instantiate()
	else:
		instantiate_medium()
		_mark_download_done()


# Coroutine ancorata al LivingItem per aspettare l'importer di Godot senza perdere il riferimento
# Non facciamo direttamente Instantiate_medium per evitare errori nella console tipo "Failed loading resource"
# Anche se di base sembra funzionare ugualmente... 
# TODO? Al momento escono molti errori di reimport già avviato che noi forziamo con fs.scan. Non dà alcun problema per ora.
# Forse possiamo lanciarne solo uno una volta che abbiamo fatto tutto...?
func _wait_for_godot_import_and_instantiate() -> void:
	var fs = EditorInterface.get_resource_filesystem()
	fs.scan()
	
	var wait_loops = 0
	
	# 1. Timeout loop per il file .import (si sblocca subito appena esiste)
	while not FileAccess.file_exists(media_path + ".import") and wait_loops < 600:
		if not self.is_inside_tree(): return
		await get_tree().process_frame
		wait_loops += 1

	# 2. Aspettiamo la fine della scansione generale
	while fs.is_scanning():
		if not self.is_inside_tree(): return
		await get_tree().process_frame

	# 3. POLLING
	# Così aggiorniamo la cache locale di Godot, evitiamo che restino in RAM dei modelli
	# Caso dei modelli 3D
	if media_path.get_extension().to_lower() in ["glb", "gltf"]:
		var res = null
		var attempts = 0
		
		# Ritenta velocemente fino a 30 volte, ma appena ci riesce prosegue all'istante
		while res == null and attempts < 30:
			res = ResourceLoader.load(media_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
			if res == null:
				attempts += 1
				# Pausa brevissima (5 frame)
				for i in range(5): 
					if not self.is_inside_tree(): return
					await get_tree().process_frame
	else:
		# Per immagini e video forziamo la cache. Ignoriamo gli ZIP perché Godot non li carica come risorse dirette
		if not media_path.get_extension().to_lower() in ["zip", "pck"]: # Questo lavoro di svuotamento cache lo facciamo in LivingScene per gli ZIP
			ResourceLoader.load(media_path, "", ResourceLoader.CACHE_MODE_REPLACE)
		await get_tree().process_frame
		await get_tree().process_frame

	# 4. Istanziamo
	print("LivingItem: Importazione conclusa, forzo istanziazione di %s" % media_path)
	instantiate_medium()
		
	# 5. Sblocchiamo la UI
	_mark_download_done()


func _on_download_media_error(err: String):
	push_error("Download media error signal. %s" % err)
	media_filename = err
	_mark_download_done()


func _on_download_thumbnail_success(filename, path, type):
	print("Downloaded sucessfully thumbnail '%s' of type %s into '%s'." % [filename, type, path])
	thumbnail_path = path

	# Salviamo in cache il percorso della thumbnail
	_update_cache_data({"thumb_path": thumbnail_path})

	_mark_download_done()

func _on_download_thumbnail_error(err: String):
	thumbnail_path = err
	push_error("Download thumbnail error signal. %s" % err)
	_mark_download_done()

#
# UTILITY METHODS
#

## Recursively set the visibility of this Item and all children
func set_item_visible(v: bool):
	for c in get_children():
		if c is LivingItem:
			(c as LivingItem).set_item_visible(v)


#
# OMEKAS JSON DOWNLOAD
#

# Called when the property button is clicked
func fetch_omeka_info():
	print("Fetching OmekaS information for node '%s'." % name)

	# --- build tracking ---
	_reset_build_tracking()
	build_state = BuildState.FETCHING

	# Get the base Omeka URL from the root node
	var living_root : LivingEnvironment
	if Engine.is_editor_hint():
		living_root = get_tree().edited_scene_root as LivingEnvironment
	else:
		living_root = get_tree().current_scene as LivingEnvironment

	var base_url = living_root.OMEKA_BASE_URL

	# Clear all fields
	title = ""
	modified = ""
	short_description = ""
	long_description = ""
	catalog_description = ""
	resource_class = 0
	components.clear()
	areas.clear()
	medium_uri = ""

	item_sets.clear()
	media.clear()

	# Retrieve info from the Omeka server
	# var item_url: String = url + "/api/items/?id=" + str(item_id)
	# var item_url: String = url + "/api/items?pretty_print=1"
	var item_url: String = base_url + "/api/items?pretty_print=1&id=" + str(item_id)
	print("Getting info from OmekaURL '" + item_url + "'" )
	_fetch_json_from_url(item_url)
	# print(item_json)
	
	# Needed to refresh the GUI when values or scene structure has changed
	# notify_property_list_changed()


func _delete_all_children() -> void:
	for child in get_children():
		# if child is Living3DModel or child is LivingImage or child is LivingVideo:
		if child is LivingItem:
			child.free()


# Reference to the latest HTTP request
var _active_request: HTTPRequest

func _fetch_json_from_url(url: String) -> void:
	# Create HTTPRequest node
	var http_request := HTTPRequest.new()
	add_child(http_request)

	# Connect completion callback
	_active_request = http_request
	http_request.request_completed.connect(
		_on_fetch_json_completed.bind(http_request),
		CONNECT_ONE_SHOT
	)

	# Start GET request
	var err := http_request.request(url)
	if err != OK:
		_active_request.queue_free()
		_active_request = null
		var msg = "HTTP request error occurred: %s" % err
		emit_signal("fetch_json_error", msg)
	else:
		print("Request delegated to child %s" % http_request.name)

 
func get_omeka_text(item_dict: Dictionary, key: String) -> String:
	# Se la proprietà non esiste -> testo vuoto
	if not item_dict.has(key):
		return ""
 
	# Omeka S: la proprietà è quasi sempre un Array di valori
	var arr = item_dict[key]
	if typeof(arr) != TYPE_ARRAY or arr.is_empty():
		return ""
 
	# Primo valore
	var v = arr[0]
	if typeof(v) != TYPE_DICTIONARY:
		return ""
 
	# Testo nel campo @value
	return str(v.get("@value", ""))


func _on_fetch_json_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:

	# Ensure that a possible existing old HTTPRequest node is destroyed in all cases
	http_request.queue_free()
	_active_request = null

	# Basic HTTP error handling (4xx / 5xx)
	if response_code < 200 or response_code >= 300:
		var msg = "HTTP error occurred: response code %d" % response_code
		emit_signal("fetch_json_error", msg)
		return

	# Check Content-Type header for JSON-LD
	var content_type := ""
	for h in headers:
		# headers are "Key: Value" strings
		if h.to_lower().begins_with("content-type:"):
			content_type = h.substr(h.find(":") + 1, h.length()).strip_edges()
			break

	if "application/ld+json" not in content_type:
		var msg = "Invalid response content: Response is not JSON type"
		emit_signal("fetch_json_error", msg)
		return

	# Parse JSON body
	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		var msg = "Invalid response content: JSON parse error %d" % parse_err
		emit_signal("fetch_json_error", msg)
		return

	var data = json.get_data()  # Dictionary or Array, similar to Union[list, dict]
	# Use `data` here as needed, e.g.:
	# print(data)
	
	if typeof(data) == TYPE_ARRAY:
		var items_arr: Array = data as Array  # Cast to Array
		var count: int = items_arr.size()     # Get number of elements
		if count > 0:
			var item_dict: Dictionary = items_arr[0] as Dictionary
			# print(item_dict)

			# TITLE
			title = item_dict["o:title"]

			# MODIFIED
			modified = item_dict["o:modified"]["@value"]
			
			# DESCRIPTION
			short_description   = get_omeka_text(item_dict, "lcp_form:has_short_text_f")
			long_description    = get_omeka_text(item_dict, "lcp_form:has_long_text_f")
			catalog_description = get_omeka_text(item_dict, "lcp_form:has_catalogue_text_f")

			# RESOURCE CLASS
			var resource_class_entry = item_dict["o:resource_class"]
			if resource_class_entry:
				# print("Valid rc entry")
				resource_class = item_dict["o:resource_class"]["o:id"]
			else:
				print("Skipping resource_class")
			
			# ITEM SET
			for s in item_dict["o:item_set"]:
				var set_id: int = s["o:id"]  # Forces convertion to int (or it would be a float)
				# print(str(typeof(set_id)))
				item_sets.append(set_id)

			# MEDIA LIST
			media.clear()
			for m_dict in item_dict["o:media"]:
				# print("Appending media: ", typeof(m_dict), " ",  m_dict)
				var media_id: int = m_dict["o:id"]
				print("Appending media id: ", media_id)
				media.append(media_id)
					
			# COMPONENTS
			components.clear()
			if "lcp_form:is_composed_of_f" in item_dict.keys():
				for component_dict in item_dict["lcp_form:is_composed_of_f"]:
					var component_id: int = component_dict["value_resource_id"]
					components.append(component_id)

			# AREAS
			if "lcp_form:has_participatory_area_f" in item_dict.keys():
				for area_dict in item_dict["lcp_form:has_participatory_area_f"]:
					var area_id: int = area_dict["value_resource_id"]
					areas.append(area_id)
			
			# MEDIUM URI
			if "lcp_form:has_URI" in item_dict:
				var uri_array: Array = item_dict["lcp_form:has_URI"]
				if uri_array.size() != 1:
					push_error("for field lcp_form:has_URI, expected an array of size 1. Found %s" % [uri_array.size()])
				else:
					medium_uri = uri_array[0]["@id"]

			if "thumbnail_display_urls" in item_dict:
				var thumbnails_dict = item_dict["thumbnail_display_urls"]
				if "square" in thumbnails_dict:
					var thumb_uri = thumbnails_dict["square"]
				#if "large" in thumbnails_dict:
					#var thumb_uri = thumbnails_dict["large"]
					if thumb_uri != null:
						thumbnail_uri = thumb_uri
					else:
						print("Null thumbnail for item %s" % [str(item_id)])
				else:
					print("No 'square' thumbnail for item %s" % [str(item_id)])
			else:
				print("No thumbnails for item %s" % [str(item_id)])

			# Needed to refresh the GUI when values or scene structure has changed
			notify_property_list_changed()

		else:
			var msg = "ERROR: Got an empty array (Unexisting id?)"
			emit_signal("fetch_json_error", msg)

	else:
		var msg = "ERROR: Expected an array. Found %s." % str(typeof(data))
		emit_signal("fetch_json_error", msg)

	# print("Fetch completed")
	emit_signal("fetch_json_success")


## Scans the two lists -- components and areas -- and instantiate them as children.
func instantiate_children() -> void:
	# Salviamo i figli attuali in un dizionario basato sul loro item_id
	var existing_children = {}
	for child in get_children():
		if child is LivingItem:
			existing_children[child.item_id] = child

	# Iterate Components
	for c in components:
		if existing_children.has(c):
			# Se esiste già, lo teniamo e lo togliamo dalla lista di "quelli da eliminare"
			existing_children.erase(c)
		else:
			# È un element nuovo dal database, lo creiamo
			var new_element := LivingElement.new() 
			new_element.item_id = c
			new_element.name = "LivingElement-" + str(c)
			add_child(new_element)
			if Engine.is_editor_hint():
				new_element.owner = get_tree().edited_scene_root

	# Iterate Areas
	for c in areas:
		if existing_children.has(c):
			# L'area esiste già, la teniamo.
			existing_children.erase(c)
		else:
			# È un'area nuova
			var new_area := LivingArea.new()
			new_area.item_id = c
			new_area.name = "LivingArea-" + str(c)
			add_child(new_area)
			if Engine.is_editor_hint():
				new_area.owner = get_tree().edited_scene_root

	# Tutto ciò che è rimasto nel dizionario 'existing_children' significa che
	# è stato eliminato dal database, quindi lo eliminiamo dalla scena
	for old_child in existing_children.values():
		old_child.free()


#
# MEDIA DOWNLOAD (CON CACHE LOCALE)
#
func download_medium() -> void:
	if metadata_only:
		return

	if medium_uri == "" and thumbnail_uri == "":
		print_debug("No media or thumbnail to download for item %s" % [item_id])
		return

	var item_dir = MEDIA_SAVE_PATH.path_join(str(item_id))
	var cache_info_path = item_dir.path_join("cache_info.json")

	# --- 1. LETTURA CACHE ---
	var use_cache = false
	var cached_media_path = ""
	var cached_media_type = ""
	var cached_thumb_path = ""

	if FileAccess.file_exists(cache_info_path):
		var cache_text = FileAccess.get_file_as_string(cache_info_path)
		var cache_data = JSON.parse_string(cache_text)
		
		if typeof(cache_data) == TYPE_DICTIONARY and cache_data.get("modified", "") == self.modified:
			# Leggiamo esattamente quello che avevamo salvato al termine del vecchio download
			cached_media_path = cache_data.get("media_path", "")
			cached_media_type = cache_data.get("media_type", "")
			cached_thumb_path = cache_data.get("thumb_path", "")
			
			# Controlliamo solo se i file specifici esistono ancora fisicamente
			var media_ok = (medium_uri == "" or FileAccess.file_exists(cached_media_path))
			var thumb_ok = (thumbnail_uri == "" or FileAccess.file_exists(cached_thumb_path))
			
			if media_ok and thumb_ok:
				use_cache = true

	# --- 2. CARICAMENTO DALLA CACHE ---
	if use_cache:
		_is_using_cache = true
		print("CACHE VALIDA: Salto il download per l'item %d." % item_id)
		
		if medium_uri != "" and cached_media_path != "":
			_mark_download_started()
			call_deferred("_on_download_media_success", cached_media_path.get_file(), cached_media_path, cached_media_type)
			
		if thumbnail_uri != "" and cached_thumb_path != "":
			_mark_download_started()
			call_deferred("_on_download_thumbnail_success", cached_thumb_path.get_file(), cached_thumb_path, "image/jpeg")
		
		return

	# --- 3. CACHE NON VALIDA: AVVIO DOWNLOAD ---
	_is_using_cache = false
	print("CACHE ASSENTE O OBSOLETA: Avvio download per l'item %d..." % item_id)
	
	# Pulisci la cartella da vecchi file
	if DirAccess.dir_exists_absolute(item_dir):
		var dir = DirAccess.open(item_dir)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if not dir.current_is_dir():
					dir.remove(file_name)
				file_name = dir.get_next()
	else:
		DirAccess.make_dir_recursive_absolute(item_dir)
		
	# Inizializza il file cache con la sola data (verrà arricchito man mano che i download finiscono)
	_update_cache_data({"modified": self.modified})

	media_filename = "Downloading..."
	media_path = ""
	media_type = ""

	# Scarica il media principale
	if medium_uri != "":
		_mark_download_started()
		var http_request := HTTPDownloader.new(medium_uri, item_dir, str(item_id) + "-", download_media_success, download_media_error)
		add_child(http_request)
		http_request.do_download()
	
	# Scarica l'immagine di anteprima
	if thumbnail_uri != "":
		_mark_download_started()
		var thumbnail_http_request := HTTPDownloader.new(thumbnail_uri, item_dir, str(item_id) + "-thumbnail-", download_thumbnail_success, download_thumbnail_error)
		add_child(thumbnail_http_request)
		thumbnail_http_request.do_download()


# Aggiorna in modo incrementale il file cache_info.json senza sovrascrivere dati precedenti
func _update_cache_data(new_data: Dictionary) -> void:
	var item_dir = MEDIA_SAVE_PATH.path_join(str(item_id))
	var cache_info_path = item_dir.path_join("cache_info.json")
	var current_data = {}
	
	if FileAccess.file_exists(cache_info_path):
		var text = FileAccess.get_file_as_string(cache_info_path)
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			current_data = parsed
			
	current_data.merge(new_data, true)
	
	var f = FileAccess.open(cache_info_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(current_data))
		f.close()


# Given that the Omeka info was fetcher and the media has been downloaded,
# here create the correct node subtype and add it as child.
func instantiate_medium() -> void:
	if media_type == "" or media_path == "":
		return 
		
	# Se il file non è cambiato su internet (abbiamo usato la cache),
	# controlliamo se il figlio 3D/ZIP esiste già. Se c'è, lo lasciamo in pace!
	if _is_using_cache:
		for child in get_children():
			if child is Living3DModel or child is LivingImage or child is LivingVideo or child is LivingText or child is LivingScene:
				print("LivingItem: Media già presente e aggiornato. Salto re-istanziazione.")
				return # Esce dalla funzione senza distruggere nulla!

	# Se arriviamo qui significa che: O il file è completamente nuovo (scaricato ora),
	# OPPURE il figlio mancava nella scena (è un nuovo oggetto appena sincronizzato).
	# Rimuoviamo eventuali rimasugli e creiamo il nuovo nodo.
	for child in get_children():
		if child is Living3DModel or child is LivingImage or child is LivingVideo or child is LivingText or child is LivingScene:
			child.free()
	
	var new_child = null
	
	if media_type == "image/png" or media_type == "image/jpeg":
		print("Instantiating an image.")
		new_child = LivingImage.new()
		new_child.name = "LivingImage-" + str(item_id)
		new_child.image_path = media_path
	elif media_type == "text/plain":
		print("Instantiating a text.")
		new_child = LivingText.new()
		new_child.name = "LivingText-" + str(item_id)
		# new_child = LivingCaptionLong.new()  # living_caption_scene.instantiate()
		# new_child.name = "LivingCaption-" + str(item_id)
		new_child.text_path = media_path
	elif media_type == "video/ogg":
		print("Instantiating a video.")
		new_child = living_video_player_scene.instantiate()
		new_child.name = "LivingVideo-" + str(item_id)
		new_child.video_path = media_path
		# Do not uncomment the following line! Cannot load a media if the player is not yet ready in the scene.
		# new_child.load_video_stream(media_path)
	elif media_type == "model/gltf-binary":
		print("Instantiating a 3D object.")
		new_child = Living3DModel.new()
		new_child.name = "Living3DModel-" + str(item_id)
		new_child.model_path = media_path
	elif media_type == "application/zip":
		self.visible = true # TEMPORANEO, UNA VOLTA FIXATI I TEMPLATE AGGIUSTIAMO
		print("Instantiating a LivingScene from ZIP.")
		new_child = LivingScene.new()
		new_child.name = "LivingScene-" + str(item_id)
		new_child.pack_path = media_path
		
		var extract_dir = media_path.get_base_dir()
		new_child.extraction_dir = extract_dir
		
		# Andrebbe fatto sulla base del campo!!!
		# 1. Blocchiamo il contenitore padre (LivingItem)
		self.set_meta("_edit_lock_", true)
		# 2. Blocchiamo il contenitore figlio (LivingScene)
		new_child.set_meta("_edit_lock_", true)
		# I nipoti (il contenuto dello ZIP) verranno bloccati 
		# in automatico dallo script living_scene.gd
		
		new_child.extraction_dir = extract_dir
		
		# Il path della scena è dentro questa cartella
		# Al momento nome hardcoded che viene generato dal progetto Godot del LE Template...
		new_child.entry_scene_path = extract_dir.path_join("LivingEnvironmentTemplate.tscn")
	else:
		push_error("Unknown media type '%s'" % [media_type])
		return
	
	print("Visualizing media type %s by adding child %s" % [media_type, new_child.name])
	add_child(new_child)
	
	# Needed to refresh the Editor GUI when values or scene structure has changed
	if Engine.is_editor_hint():
		# Important. Set the owner to make it visible in the scene dock and persist
		var root = get_tree().edited_scene_root
		if root != null:
			new_child.owner = root
		else:
			new_child.owner = self.owner
			
		EditorInterface.mark_scene_as_unsaved()



# BUILD TRACKING UTILS
func get_pending_downloads() -> int:
	return _pending_downloads
	
func _reset_build_tracking() -> void:
	_pending_children = 0
	_pending_downloads = 0
	_finished_emitted = false
	_build_started = true

func _try_emit_build_finished() -> void:
	if _finished_emitted:
		return
	if _pending_children > 0:
		return
	if _pending_downloads > 0:
		return

	_finished_emitted = true
	build_state = BuildState.READY
	build_finished.emit(true)

func _fail_build(reason: String = "") -> void:
	if reason.strip_edges() != "":
		push_error(reason)
	if _finished_emitted:
		return
	_finished_emitted = true
	build_state = BuildState.ERROR
	build_finished.emit(false)

func _begin_child_build(child: LivingItem) -> void:
	_pending_children += 1

	# child ha finito (success o error) => decrementa e tenta chiusura
	child.build_finished.connect(func(_success: bool):
		_pending_children -= 1
		_try_emit_build_finished()
	, CONNECT_ONE_SHOT)

func _mark_download_started() -> void:
	_pending_downloads += 1
	build_state = BuildState.DOWNLOADING

func _mark_download_done() -> void:
	_pending_downloads -= 1
	if _pending_downloads < 0:
		_pending_downloads = 0
	_try_emit_build_finished()
