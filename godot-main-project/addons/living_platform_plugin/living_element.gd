@tool
extends Node3D

class_name LivingElement

var MEDIA_SAVE_PATH: String = "downloaded_living_media"

# The prototype scene to instantiate video players
var living_video_player_scene = preload("res://addons/living_platform_plugin/scenes/living_video.tscn")


# Export decorators.
# See: https://docs.godotengine.org/en/4.5/tutorials/scripting/gdscript/gdscript_exports.html#basic-use
@export var item_id: int = 0
@export_tool_button("Fetch Omeka Info") var fetch_omeka_info_btn = fetch_omeka_info

@export var title: String = ""
@export var modified: String = ""
@export_multiline var short_description: String = ""
@export_multiline var long_description: String = ""
@export_multiline var catalog_description: String = ""
@export var resource_class: int = 0
@export var components: Array[int] = []
@export_tool_button("Instantiate Components") var instantiate_components_btn = instantiate_components


@export var item_sets: Array[int] = []
@export var media: Array[int] = []

# HUD
@export var xr_camera_path: NodePath        # Qui portiamo la camera, magari la cerchiamo??

@export var hud_distance_m: float = 2.0
@export var long_distance_m: float = 1.0
@export var hysteresis_m: float = 0.15

@export var hud_offset: Vector3 = Vector3(0, 1.5, -1.2)  # davanti alla camera (Z negativo = avanti nello spazio camera)
@export var hud_font_size: float = 10                      # scala pannello (dipende dalla tua scala)
@export var hud_line_delay_s: float = 3 

enum CaptionMode { OFF, HUD, LONG }
var _caption_mode: CaptionMode = CaptionMode.OFF

var _xr_cam: Node3D = null
var _hud_text_3d: LivingText = null
var _hud_lines: PackedStringArray = []
var _hud_line_index: int = 0
var _hud_reveal_running: bool = false
var _hud_accumulated: String = ""
var _hud_timer: Timer = null


# E.g.:
# "https://nextcloud.livingculture.it/s/rB3oKHRzcRQfERs/download"
# or
# "http://nextcloud.livingculture.it/public.php/dav/files/C4tEyTMpEyz3gTY/Duck.glb"
@export var media_uri: String = ""

# @export_tool_button("Instantiate Media") var instantiate_media_btn = instantiate_media
@export_tool_button("Download Media") var download_media_btn = download_media
@export var media_filename: String
@export var media_path: String
@export var media_type: String



# Set any of the given flags from the editor.
@export_flags(LivingConstants.ITEM_VISIBILITY_PRE_STR, LivingConstants.ITEM_VISIBILITY_POST_STR) var visibility: int = LivingConstants.ItemVisibility.PRE_EXPERIENCE | LivingConstants.ItemVisibility.POST_EXPERIENCE


## SIGNALS ##
signal fetch_json_success()
signal fetch_json_error(reason: String)

signal download_media_success()
signal download_media_error(reason: String)



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("LivingItem '%s' Ready." % [self.name])
	self.set_meta("_edit_group_", true)

	_xr_cam = get_node_or_null(xr_camera_path) as Node3D  # Riferimento alla camera, se esiste
	if not Engine.is_editor_hint():
		_hud_timer = Timer.new()
		_hud_timer.one_shot = false
		_hud_timer.autostart = false
		add_child(_hud_timer)
		_hud_timer.timeout.connect(_on_hud_timer_timeout)



func _process(_delta: float) -> void:  # Controlla distanza dalla camera e aggiorna modalità di caption
	if _xr_cam == null:
		return

	if Engine.is_editor_hint():
		return

	var d := global_position.distance_to(_xr_cam.global_position)
	var hud_on := hud_distance_m
	var hud_off := hud_distance_m + hysteresis_m
	var long_on := long_distance_m
	var long_off := long_distance_m + hysteresis_m

	match _caption_mode:
		CaptionMode.OFF:
			if d <= long_on:
				_set_caption_mode(CaptionMode.LONG)
			elif d <= hud_on:
				_set_caption_mode(CaptionMode.HUD)

		CaptionMode.HUD:
			_update_hud_transform()
			if d <= long_on:
				_set_caption_mode(CaptionMode.LONG)
			elif d >= hud_off:
				_set_caption_mode(CaptionMode.OFF)

		CaptionMode.LONG:
			if d > hud_off:
				_set_caption_mode(CaptionMode.OFF)
			elif d >= long_off and d <= hud_on:
				_set_caption_mode(CaptionMode.HUD)


func _set_caption_mode(new_mode: CaptionMode) -> void:
	if new_mode == _caption_mode:
		return

	# exit
	match _caption_mode:
		CaptionMode.HUD:
			_hide_hud_3d()
		CaptionMode.LONG:
			_destroy_description_node()

	_caption_mode = new_mode

	# enter
	match _caption_mode:
		CaptionMode.OFF:
			pass
		CaptionMode.HUD:
			_destroy_description_node()
			_show_hud_3d_and_reveal()
		CaptionMode.LONG:
			_hide_hud_3d()
			_create_description_node()
	

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
	# print("on JSON fetch success")
	
	self.name = title.substr(0, 20)
	
	if media_uri != "":
		download_media()
	else:
		print("No media to download for item %s" % [item_id])

	
func _on_json_fetch_error(err: String):
	push_error(err)
	title = err


func _on_download_media_success():
	print("on download media success")
	visualize_media()


func _on_download_media_error(err: String):
	push_error(err)
	media_uri = err


func set_visible(v: bool):
	for c in get_children():
		if c is LivingMedia:
			(c as LivingMedia).visible = v


#
# OMEKAS JSON DOWNLOAD
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
	title = ""
	modified = ""
	short_description = ""
	long_description = ""
	catalog_description = ""
	resource_class = 0
	components.clear()
	media_uri = ""

	item_sets.clear()
	media.clear()

	# Delete all LivingMedia children
	_delete_all_children()

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
		if child is Living3DModel or child is LivingImage or child is LivingVideo:
			child.queue_free()


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
			var description_array: Array = item_dict["dcterms:description"]
			# There will be 3 items [0, 1, 2] == short, long, catalog
			if description_array.size() != 3:
				push_error("For item %s, description array, expecting 3 items. Found %s" % [item_id, description_array.size()])
			short_description = description_array[0]["@value"]
			if description_array.size() >= 2:
				long_description = description_array[1]["@value"]
			if description_array.size() >= 3:
				catalog_description = description_array[2]["@value"]

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
			
			# MEDIA URI
			if "lcp_form:has_URI" in item_dict:
				var uri_array: Array = item_dict["lcp_form:has_URI"]
				if uri_array.size() != 1:
					push_error("for field lcp_form:has_URI, expected an array of size 1. Found %s" % [uri_array.size()])
				else:
					media_uri = uri_array[0]["@id"]
			
			# COMPONENTS
			components.clear()
			if "lcp_form:is_composed_of_f" in item_dict.keys():
				for component_dict in item_dict["lcp_form:is_composed_of_f"]:
					var component_id: int = component_dict["value_resource_id"]
					components.append(component_id)
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

# Given that the Omeka info was fetcher and the media list has been retrieved,
# here create LivingMedia instances for each entry
#func instantiate_media() -> void:
#
	#_delete_all_children()
#
#
	##  Instantiate the new LivingMedia child
	#var new_media_id := media[selected_media]
	#var new_child = LivingMedia.new()
	#new_child.media_id = new_media_id
	#new_child.name = "LivingMedia-" + str(new_media_id)
	#add_child(new_child)
	#
	#if Engine.is_editor_hint():
		## Important. Set the owner to make it visible in the scene dock and persist
		#new_child.owner = get_tree().edited_scene_root
	#
	## Needed to refresh the Editor GUI when values or scene structure has changed
	#if Engine.is_editor_hint():
		## For @tool scripts, access EditorInterface to save
		#EditorInterface.mark_scene_as_unsaved()


func instantiate_components() -> void:
	for c in components:
		var new_element := LivingElement.new() 
		new_element.item_id = c
		new_element.name = "LivingElement-" + str(c)

		add_child(new_element)
		
		if Engine.is_editor_hint():
			# Important. Set the owner to make it visible in the scene dock and persist
			new_element.owner = get_tree().edited_scene_root
		

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


func download_media() -> void:
	# Downloads a file shared through NextCloud (https://nextcloud.example.com/s/rB3oKHRzcRQfERs/download
	# The link is first converted into the equivalent WebDAV link (https://nextcloud.example.com/public.php/dav/files/rB3oKHRzcRQfERs) before downloading
	# This is done because the original NextCloud share link is using redirect, but the HTTPRequest
	# implementation of Godot doesn't support redirect, leading to error 303.

	var public_url: String = media_uri
	# If the link was a NextCloud share, convert it into a webdav link
	if not public_url.contains("/public.php/dav/files/"):
		var url_info := _parse_nextcloud_share_link(media_uri)
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
func visualize_media() -> void:
	
	# Remove all children first
	for child in get_children():
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


@export_tool_button("Show Description") var create_description_btn = _create_description_node
@export_tool_button("Remove Description") var destroy_description_btn = _destroy_description_node

var description_text: LivingText = null

#
# LONG TEXT VISUALIZATION
#
func _create_description_node() -> void:
	
	_destroy_description_node()

	var combined_aabb :AABB = LivingUtils.get_node_aabb(self)

	description_text = LivingText.new(false)
	# print("DESCRIPTION: ", description)
	add_child(description_text)
	description_text.set_text(long_description)
	
	# DEBUG
	# LivingUtils.set_owner_R(description_text, get_tree().edited_scene_root)
	
	# Position the description according to the bbox
	var description_aabb = description_text.get_aabb()
	var description_offset = (combined_aabb.size.x / 2.0) + (description_aabb.size.x / 2.0) + (description_aabb.size.x * 0.05)
	# Put the description on the left
	description_text.position.x = - description_offset

func _destroy_description_node() -> void:
	
	if description_text:
		description_text.free()
		description_text = null


#
# SHORT TEXT (HUD) VISUALIZATION
#

func _show_hud_3d_and_reveal() -> void:
	if _xr_cam == null:
		# se non c'è camera, niente HUD
		return

	if _hud_text_3d == null:
		_hud_text_3d = LivingText.new(false)
		_hud_text_3d.name = "LivingHUDText"
		_xr_cam.add_child(_hud_text_3d)

		_hud_text_3d.font_size = hud_font_size
		_hud_text_3d.alpha = 1.0
		_update_hud_transform()

	var txt := short_description
	_hud_lines = txt.split("\n", false)
	_hud_line_index = 0

	_hud_reveal_running = true

	# mostra subito la prima riga/frase
	_on_hud_timer_timeout()

	# avvia loop
	if _hud_timer:
		_hud_timer.stop()
		_hud_timer.wait_time = hud_line_delay_s
		_hud_timer.start()


func _hide_hud_3d() -> void:
	_hud_reveal_running = false
	if _hud_timer:
		_hud_timer.stop()
	if _hud_text_3d:
		_hud_text_3d.queue_free()
		_hud_text_3d = null


func _update_hud_transform() -> void:
	if _hud_text_3d == null:
		return
	# head-locked: offset nello spazio della camera
	_hud_text_3d.transform = Transform3D(Basis.IDENTITY, hud_offset)


func _on_hud_timer_timeout() -> void:
	if not _hud_reveal_running:
		return
	if _caption_mode != CaptionMode.HUD:
		return
	if _hud_text_3d == null:
		return
	if _hud_lines.size() == 0:
		_hud_text_3d.set_text("")
		return

	# loop continuo
	if _hud_line_index >= _hud_lines.size():
		_hud_line_index = 0

	var line := _hud_lines[_hud_line_index].strip_edges()
	_hud_line_index += 1

	# mostra SOLO la riga corrente (no concatenazione)
	_hud_text_3d.set_text(line)
