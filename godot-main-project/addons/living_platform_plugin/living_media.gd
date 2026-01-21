@tool
extends Node

class_name LivingMedia

var MEDIA_SAVE_PATH: String = "downloaded_living_media"

@export var media_id: int = 0
@export_tool_button("Fetch Omeka Info") var fetch_living_info = fetch_omeka_info


@export var source_url: String
@export var media_type: String
@export var modified: String

@export_tool_button("Download Media") var download_media_btn = download_nextcloud_shared_file_webdav

@export var media_filename: String
@export var media_path: String

@export_tool_button("Visualize Media") var visualize_media_btn = visualize_media


# Reference URLs format
# List all
# https://omekadev.livingculture.it/api/media?pretty_print=1
# Single item
# https://omekadev.livingculture.it/api/media/6?pretty_print=1
# Important field(s):
# {
#   "o:source_url": "https:\/\/nextcloud.livingculture.it\/s\/rB3oKHRzcRQfERs\/download",
#   "o:media_type": "image\/png",
#   ...
# }

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


#
# OMEKA INFO FETCH
#

# Called when the property button is clicked
func fetch_omeka_info():
	print("Fetching OmekaS information for node '%s'." % name)

	# Get the base Omeka URL from the root node
	var living_root : LivingScene
	if Engine.is_editor_hint():
		living_root = get_tree().edited_scene_root as LivingScene
	else:
		living_root = get_tree().current_scene as LivingScene

	var base_url = living_root.OMEKA_BASE_URL

	# Clear all fields
	source_url = ""
	media_type = ""

	# Retrieve info from the Omeka server
	# var item_url: String = url + "/api/items/?id=" + str(media_id)
	# var item_url: String = url + "/api/items?pretty_print=1"
	var item_url: String = base_url + "/api/media/" + str(media_id) + "?pretty_print=1" 
	print("Getting info from OmekaURL '" + item_url + "'" )
	fetch_json_from_url(item_url)
	# print(item_json)
	
	# Needed to refresh the GUI when values or scene structure has changed
	# notify_property_list_changed()

# Reference to the latest HTTP request
var _active_request: HTTPRequest

func fetch_json_from_url(url: String) -> void:
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
		push_error("HTTP error occurred: %s" % err)
		source_url = "ERROR: HTTP error occurred: %s" % err
		http_request.queue_free()
		_active_request = null
	else:
		print("Request delegated to child %s" % http_request.name)

func _on_fetch_json_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:

	# Ensure that a possible existing old HTTPRequest node is destroyed in all cases
	http_request.queue_free()
	_active_request = null

	# Basic HTTP error handling (4xx / 5xx)
	if response_code < 200 or response_code >= 300:
		push_error("HTTP error occurred: response code %d" % response_code)
		source_url = "ERROR: HTTP error occurred: response code %d" % response_code
		return

	# Check Content-Type header for JSON-LD
	var content_type := ""
	for h in headers:
		# headers are "Key: Value" strings
		if h.to_lower().begins_with("content-type:"):
			content_type = h.substr(h.find(":") + 1, h.length()).strip_edges()
			break

	if "application/ld+json" not in content_type:
		push_error("Invalid response content: Response is not JSON type")
		source_url = "ERROR: Invalid response content: Response is not JSON type"
		return

	# Parse JSON body
	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		push_error("Invalid response content: JSON parse error %d" % parse_err)
		source_url = "ERROR: Invalid response content: JSON parse error %d" % parse_err
		return

	var data = json.get_data()  # Dictionary or Array, similar to Union[list, dict]
	# Use `data` here as needed, e.g.:
	# print(data)
	
	if typeof(data) == TYPE_DICTIONARY:
		var media_dict: Dictionary = data as Dictionary  # Cast to Dictionary
		# print(item_dict)
		source_url = media_dict["o:source"]
		media_type = media_dict["o:media_type"]
		modified = media_dict["o:modified"]["@value"]
		
		# Needed to refresh the GUI when values or scene structure has changed
		notify_property_list_changed()

	else:
		source_url = "ERROR: Expected a dictionary. Found %s." % str(typeof(data))
		push_error("Expected an dictionary. Found %s." % str(typeof(data)))

	# print("Fetch completed")


#
# MEDIA DOWNLOAD
#

# Current http request for downloading the media.
var _active_download_request: HTTPRequest

func _parse_nextcloud_share_link(shared_url: String) -> Dictionary:
	# Analyses a typical NextCLoud share link.
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


func download_nextcloud_shared_file_webdav() -> void:
	# Downloads a file shared through NextCloud (https://nextcloud.example.com/s/rB3oKHRzcRQfERs/download
	# The link is first converted into the equivalent WebDAV link (https://nextcloud.example.com/public.php/dav/files/rB3oKHRzcRQfERs) before downloading
	# This is done because the original NextCloud share link is using redirect, but the HTTPRequest
	# implementation of Godot doesn't support redirect, leading to error 303.

	var url_info := _parse_nextcloud_share_link(source_url)
	var public_url: String = url_info['base_url'] + "/public.php/dav/files/" + url_info['token']

	print("Downloading media from URL '%s'..." % [public_url])

	media_filename = "Downloading..."
	media_path = ""
	
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
		push_error("HTTPRequest failed to start: %d" % err)
		http_request.queue_free()
		_active_download_request = null
		media_filename = "ERROR"

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


func _on_webdav_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	http_request.queue_free()
	_active_download_request = null
	
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Download failed: result=%d, code=%d" % [result, response_code])
		media_filename = "ERROR"
		return
	
	if response_code != 200:
		push_error("Server error: %d" % response_code)
		media_filename = "ERROR"
		return
	
	var requested_filename = _extract_filename_from_headers(headers)
	var new_media_filename = str(media_id) + "-" + requested_filename
	var new_media_path = MEDIA_SAVE_PATH + "/" + new_media_filename

	# Prepare the sotring directory, if not already
	if not DirAccess.dir_exists_absolute(MEDIA_SAVE_PATH):
		var err: Error = DirAccess.make_dir_recursive_absolute(MEDIA_SAVE_PATH)
		if err != OK:
			push_error("Failed to create %s: %s" % [MEDIA_SAVE_PATH, error_string(err)])
			media_filename = "ERROR"
			return


	# Stream body to file in chunks (8192 bytes)
	var file := FileAccess.open(new_media_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open local file: %s" % new_media_path)
		media_filename = "ERROR"
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
func visualize_media() -> void:
	
	var new_child = null
	
	if media_type == "image/png":
		print("Instantiating an image.")
		new_child = LivingImage.new()
		new_child.image_path = media_path
		new_child.name = "LivingImage"
	else:
		push_error("Unknown media type '%'" % media_type)
	
	add_child(new_child)
	
	# Needed to refresh the Editor GUI when values or scene structure has changed
	if Engine.is_editor_hint():
		# Important. Set the owner to make it visible in the scene dock and persist
		new_child.owner = get_tree().edited_scene_root
		# For @tool scripts, access EditorInterface to save
		EditorInterface.mark_scene_as_unsaved()
