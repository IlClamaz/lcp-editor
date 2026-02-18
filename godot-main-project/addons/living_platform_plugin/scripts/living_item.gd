@tool
extends Node3D

class_name LivingItem

var MEDIA_SAVE_PATH: String = "res://downloaded_living_media"

# When an Element info are fetched from OmekaS, the object name is set to the item title.
# Howeve, some titles are was too long. So, we chop them to this number of characters.
const OMEKA_TITLE_MAX_LEN: int = 200

# The prototype scene to instantiate video players
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
@export_group("")


## SIGNALS ##
signal fetch_json_success()
signal fetch_json_error(reason: String)

signal download_media_success()
signal download_media_error(reason: String)


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("LivingItem '%s' Ready." % [self.name])


func _enter_tree():
	# print("Living Item Tree Enter.")
	fetch_json_success.connect(_on_json_fetch_success, CONNECT_DEFERRED)
	fetch_json_error.connect(_on_json_fetch_error, CONNECT_DEFERRED)
	
	download_media_success.connect(_on_download_media_success, CONNECT_DEFERRED)
	download_media_error.connect(_on_download_media_error, CONNECT_DEFERRED)


func _exit_tree():
	# print("Living Item Tree Exit.")
	fetch_json_success.disconnect(_on_json_fetch_success)
	fetch_json_error.disconnect(_on_json_fetch_error)
	
	download_media_success.disconnect(_on_download_media_success)
	download_media_error.disconnect(_on_download_media_error)


func _on_json_fetch_success():
	self.name = title.substr(0, OMEKA_TITLE_MAX_LEN)
	
	if auto_download_medium:
		download_medium()
	
	if auto_instantiate_children:
		instantiate_children()


func _on_json_fetch_error(err: String):
	push_error(err)
	title = err


func _on_download_media_success():
	print("Download media '%s' success. Visualize it." % [media_path])
	
	# Force re-scan of the freshly retrieved media
	var fs := EditorInterface.get_resource_filesystem()
	if not fs.is_scanning():
		fs.scan()
		
	if auto_instantiate_medium:
		instantiate_medium()


func _on_download_media_error(err: String):
	push_error(err)
	media_filename = err

#
# UTILITY METHODS
#

## Recursively set the visibility of this Item and all children
func set_visible(v: bool):
	for c in get_children():
		if c is LivingItem:
			(c as LivingItem).set_visible(v)


#
# OMEKAS JSON DOWNLOAD
#

# Called when the property button is clicked
func fetch_omeka_info():
	print("Fetching OmekaS information for node '%s'." % name)

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


## Scans the two lists -- components and areas -- and instantiate them as children using either the LivingElement or the LivingArea as subclass.
func instantiate_children() -> void:
	
	# Delete all LivingItem children
	for child in get_children():
		if child is LivingItem:
			child.free()

	# Iterate components
	for c in components:
		var new_element := LivingElement.new() 
		new_element.item_id = c
		new_element.name = "LivingElement-" + str(c)

		add_child(new_element)
		
		# Important. Set the owner to make it visible in the scene dock and persist saves.
		# But only if this self node is also in a scene.
		if Engine.is_editor_hint():  # and self.owner != null:
			new_element.owner = get_tree().edited_scene_root
		
		if auto_recurse_children:
			new_element.fetch_omeka_info()

	for c in areas:
		var new_area := LivingArea.new()
		new_area.item_id = c
		new_area.name = "LivingArea-" + str(c)

		add_child(new_area)
		
		# Important. Set the owner to make it visible in the scene dock and persist saves.
		# But only if this self node is also in a scene.
		if Engine.is_editor_hint():  # and self.owner != null:
			print("SETTING AREA OWNER")
			new_area.owner = get_tree().edited_scene_root
		
		if auto_recurse_children:
			new_area.fetch_omeka_info()

#
# MEDIA DOWNLOAD
#

# Current http request for downloading the media.
var _active_download_request: HTTPRequest

func _parse_nextcloud_share_link(shared_url: String) -> Dictionary:
	# Analyses a typical NextCloud share link.
	# Returns { "base_url": String, "token": String }
	# Example:
	# https://nextcloud.example.com/s/5ZK4QSbQGr9bktT
	# -> { "base_url": "https://nextcloud.example.com", "token": "5ZK4QSbQGr9bktT" }

	var url_regex := RegEx.new()
	url_regex.compile(r"^(https?)://([^/]+)(/.+)?$")  # Godot RegEx with raw string literal [web:2][web:4]
	var match := url_regex.search(shared_url)
	if match == null:
		push_error("Invalid URL: %s" % shared_url)
		return {}

	var scheme := match.get_string(1)
	var netloc := match.get_string(2)
	var path := match.get_string(3)
	if path == null:
		path = ""

	var parts := path.trim_prefix("/").trim_suffix("/").split("/")

	if parts.size() < 2 or parts[0] != "s":
		push_error("Unexpected share URL format: %s" % shared_url)
		return {}

	var token := parts[1]
	var base_url := "%s://%s" % [scheme, netloc]

	return {
		"base_url": base_url,
		"token": token,
	}


func download_medium() -> void:
	# Downloads a file shared through NextCloud (https://nextcloud.example.com/s/rB3oKHRzcRQfERs/download
	# The link is first converted into the equivalent WebDAV link (https://nextcloud.example.com/public.php/dav/files/rB3oKHRzcRQfERs) before downloading
	# This is done because the original NextCloud share link is using redirect, but the HTTPRequest
	# implementation of Godot doesn't support redirect, leading to error 303.

	# se siamo in modalità "solo metadata", NON scaricare e NON visualizzare media
	if metadata_only:
		return

	if medium_uri == "":
		push_error("No media to download for item %s" % [item_id])
		return


	var public_url: String = medium_uri
	# If the link was a NextCloud share, convert it into a webdav link
	if not public_url.contains("/public.php/dav/files/"):
		var url_info := _parse_nextcloud_share_link(public_url)
		public_url = url_info['base_url'] + "/public.php/dav/files/" + url_info['token']

	print("Downloading media from URL '%s'..." % [public_url])

	media_filename = "Downloading..."
	media_path = ""
	media_type = ""
	
	# Create and configure HTTPRequest
	var http_request := HTTPRequest.new()
	add_child(http_request)
	_active_download_request = http_request
	
	# Connect one-shot callback (auto-disconnects after firing)
	http_request.request_completed.connect(
		_on_webdav_download_completed.bind(http_request),
		CONNECT_ONE_SHOT
	)
	
	# Issue GET request
	var err := http_request.request(public_url)
	if err != OK:
		http_request.queue_free()
		_active_download_request = null
		var msg = "HTTPRequest failed to start: %d" % err
		emit_signal("download_media_error", msg)


func _extract_filename_from_headers(headers: PackedStringArray) -> String:
	for header_line in headers:
		if "content-disposition" in header_line.to_lower():
			# Parse: "Content-Disposition: attachment; filename=\"example.png\""
			var regex := RegEx.new()
			regex.compile('filename[\\s]*=[\\s"]*([^";]+)')
			var match := regex.search(header_line)
			if match:
				return match.get_string(1).strip_edges().uri_decode()  # Decode URL-encoded chars
	return ""


const CONTENT_TYPE_KEY = "Content-Type: "

func _extract_content_type_from_headers(headers: PackedStringArray) -> String:
	
	var out: String = ""
	
	for header_line: String in headers:
		if header_line.begins_with(CONTENT_TYPE_KEY):
			out = header_line.substr(CONTENT_TYPE_KEY.length())
			break

	return out



func _on_webdav_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	http_request.queue_free()
	_active_download_request = null
	
	if result != HTTPRequest.RESULT_SUCCESS:
		var msg = "Download failed: result=%d, code=%d" % [result, response_code]
		emit_signal("download_media_error", msg)
		return
	
	if response_code != 200:
		var msg = "Server error: %d" % response_code
		emit_signal("download_media_error", msg)
		return
		
	#print("=== HEADERS ===")
	#for hline in headers:
		#print(hline)

	media_type = _extract_content_type_from_headers(headers)
	
	
	var requested_filename = _extract_filename_from_headers(headers)
	var new_media_filename = str(item_id) + "-" + requested_filename
	var new_media_path = MEDIA_SAVE_PATH + "/" + new_media_filename

	# Prepare the sotring directory, if not already
	if not DirAccess.dir_exists_absolute(MEDIA_SAVE_PATH):
		var err: Error = DirAccess.make_dir_recursive_absolute(MEDIA_SAVE_PATH)
		if err != OK:
			var msg = "Failed to create %s: %s" % [MEDIA_SAVE_PATH, error_string(err)]
			emit_signal("download_media_error", msg)
			return


	# Stream body to file in chunks (8192 bytes)
	var file := FileAccess.open(new_media_path, FileAccess.WRITE)
	if file == null:
		var msg = "Failed to open local file: %s" % new_media_path
		emit_signal("download_media_error", msg)
		return
	
	var chunk_size := 8192
	for i in range(0, body.size(), chunk_size):
		var end := mini(i + chunk_size, body.size())
		file.store_buffer(body.slice(i, end))
	
	file.close()

	media_filename = new_media_filename
	media_path = new_media_path
	
	print("Downloaded to %s" % media_filename)

	# Needed to refresh the GUI when values or scene structure has changed
	notify_property_list_changed()
	emit_signal("download_media_success")


#func reimport_resource(resource_path: String):
	#
	## Delete .import file to force reimport
	#var import_path = resource_path.get_base_dir() + "/.import/" + resource_path.get_file().get_basename() + ".import"
	#if DirAccess.open(resource_path.get_base_dir()).file_exists(resource_path.get_file()):
		#DirAccess.remove_absolute(import_path)
	#
	## Trigger filesystem rescan
	#get_editor_interface().get_resource_filesystem().scan()
	#
	#print("Reimported: %s" % resource_path)

# Given that the Omeka info was fetcher and the media has been downloaded,
# here create the correct node subtype and add it as child.
func instantiate_medium() -> void:
	
	# Remove all media children first
	for child in get_children():
		if child is Living3DModel or child is LivingImage or child is LivingVideo or child is LivingText:
			child.free()
	
	var new_child = null
	
	if media_type == "image/png":
		print("Instantiating an image.")
		new_child = LivingImage.new()
		new_child.name = "LivingImage-" + str(item_id)
		new_child.image_path = media_path
	elif media_type == "text/plain":
		print("Instantiating a text.")
		new_child = LivingText.new()
		new_child.name = "LivingText-" + str(item_id)
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
	else:
		push_error("Unknown media type '%s'" % [media_type])
		return
	
	print("Visualizing media type %s by adding child %s" % [media_type, new_child.name])
	add_child(new_child)
	
	# Needed to refresh the Editor GUI when values or scene structure has changed
	if Engine.is_editor_hint():
		# Important. Set the owner to make it visible in the scene dock and persist
		new_child.owner = get_tree().edited_scene_root
		# For @tool scripts, access EditorInterface to save
		EditorInterface.mark_scene_as_unsaved()
