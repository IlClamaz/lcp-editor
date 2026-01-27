@tool
extends Node3D

class_name LivingMedia

var MEDIA_SAVE_PATH: String = "downloaded_living_media"

# The prototype scene to instantiate video players
var living_video_player_scene = preload("res://addons/living_platform_plugin/living_video.tscn")


@export var media_id: int = 0

# Properties taken from Omeka Item JSON info
@export_tool_button("Fetch Omeka Info") var fetch_living_info = fetch_omeka_info
@export var source_url: String
@export var media_type: String
@export var modified: String

# Properties taken from  Omeka Media JSON info
@export_tool_button("Download Media") var download_media_btn = download_media
@export var media_filename: String
@export var media_path: String

@export_tool_button("Visualize Media") var visualize_media_btn = visualize_media

## SIGNALS ##
signal fetch_json_success()
signal fetch_json_error(reason: String)

signal download_media_success()
signal download_media_error(reason: String)


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

func _enter_tree():
	# print("Living Media Tree Enter.")
	fetch_json_success.connect(_on_fetch_json_success, CONNECT_DEFERRED)
	fetch_json_error.connect(_on_fetch_json_error, CONNECT_DEFERRED)
	
	download_media_success.connect(_on_download_media_success, CONNECT_DEFERRED)
	download_media_error.connect(_on_download_media_error, CONNECT_DEFERRED)

func _exit_tree():
	# print("Living Media Tree Exit.")
	fetch_json_success.disconnect(_on_fetch_json_success)
	fetch_json_error.disconnect(_on_fetch_json_error)

	download_media_success.disconnect(_on_download_media_success)
	download_media_error.disconnect(_on_download_media_error)

#
# SIGNAL CALLBACKS
#
func _on_fetch_json_success():
	print("on fetch success")
	download_media()


func _on_fetch_json_error(err: String):
	push_error(err)
	source_url = err

func _on_download_media_success():
	print("on download media success")
	visualize_media()

func _on_download_media_error(err: String):
	push_error(err)
	media_filename = err

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
	_fetch_json_from_url(item_url)
	# print(item_json)
	
	# Needed to refresh the GUI when values or scene structure has changed
	# notify_property_list_changed()

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
	
	if typeof(data) == TYPE_DICTIONARY:
		var media_dict: Dictionary = data as Dictionary  # Cast to Dictionary
		# print(item_dict)
		source_url = media_dict["o:source"]
		media_type = media_dict["o:media_type"]
		modified = media_dict["o:modified"]["@value"]
		
		# Needed to refresh the GUI when values or scene structure has changed
		notify_property_list_changed()

	else:
		var msg = "Expected a dictionary. Found %s." % str(typeof(data))
		emit_signal("fetch_json_error", msg)


	# print("Fetch completed")
	emit_signal("fetch_json_success")


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


func download_media() -> void:
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
	
	var requested_filename = _extract_filename_from_headers(headers)
	var new_media_filename = str(media_id) + "-" + requested_filename
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
func visualize_media() -> void:
	
	# Remove all children first
	for child in get_children():
		child.free()
	
	var new_child = null
	
	if media_type == "image/png":
		print("Instantiating an image.")
		new_child = LivingImage.new()
		new_child.name = "LivingImage-" + str(media_id)
		new_child.image_path = media_path
	elif media_type == "text/plain":
		print("Instantiating a text.")
		new_child = LivingText.new()
		new_child.name = "LivingText-" + str(media_id)
		new_child.text_path = media_path
	elif media_type == "video/ogg":
		print("Instantiating a video.")
		new_child = living_video_player_scene.instantiate()
		new_child.name = "LivingVideo-" + str(media_id)
		# Do not uncomment the following line! Cannot load a media if the player is not yet ready in the scene.
		# new_child.load_video_stream(media_path)
	else:
		push_error("Unknown media type '%'" % media_type)
		return
	
	print("Visualizing media type %s by adding child %s" % [media_type, new_child.name])
	add_child(new_child)
	
	# Needed to refresh the Editor GUI when values or scene structure has changed
	if Engine.is_editor_hint():
		# Important. Set the owner to make it visible in the scene dock and persist
		new_child.owner = get_tree().edited_scene_root
		# For @tool scripts, access EditorInterface to save
		EditorInterface.mark_scene_as_unsaved()
