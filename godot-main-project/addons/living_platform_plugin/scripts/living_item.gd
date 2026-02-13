@tool
extends Node

class_name LivingItem

# Export decorators.
# See: https://docs.godotengine.org/en/4.5/tutorials/scripting/gdscript/gdscript_exports.html#basic-use
@export var item_id: int = 0
@export_tool_button("Fetch Omeka Info") var fetch_living_info = fetch_omeka_info

@export var title: String = ""
@export var modified: String = ""
@export var description: String = ""
@export var resource_class: int = 0

@export var item_sets: Array[int] = []
@export var media: Array[int] = []

@export var selected_media: int = -1

@export_tool_button("Instantiate Media") var instantiate_media_btn = instantiate_media


# Set any of the given flags from the editor.
@export_flags(LivingConstants.ITEM_VISIBILITY_PRE_STR, LivingConstants.ITEM_VISIBILITY_POST_STR) var visibility: int = LivingConstants.ItemVisibility.PRE_EXPERIENCE | LivingConstants.ItemVisibility.POST_EXPERIENCE


## SIGNALS ##
signal fetch_json_success()
signal fetch_json_error(reason: String)



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("LivingItem '%s' Ready." % [self.name])

func _enter_tree():
	# print("Living Item Tree Enter.")
	fetch_json_success.connect(_on_json_fetch_success, CONNECT_DEFERRED)
	fetch_json_error.connect(_on_json_fetch_error, CONNECT_DEFERRED)

func _exit_tree():
	# print("Living Item Tree Exit.")
	fetch_json_success.disconnect(_on_json_fetch_success)
	fetch_json_error.disconnect(_on_json_fetch_error)


func _on_json_fetch_success():
	# print("on fetch success")
	instantiate_media()
	_refresh_media_children()

	
func _on_json_fetch_error(err: String):
	push_error(err)
	title = err


func set_visible(v: bool):
	for c in get_children():
		if c is LivingMedia:
			(c as LivingMedia).visible = v

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
	description = ""
	resource_class = 0
	item_sets.clear()
	media.clear()
	# Delete all LivingMedia children
	_delete_media_children()

	# Retrieve info from the Omeka server
	# var item_url: String = url + "/api/items/?id=" + str(item_id)
	# var item_url: String = url + "/api/items?pretty_print=1"
	var item_url: String = base_url + "/api/items?pretty_print=1&id=" + str(item_id)
	print("Getting info from OmekaURL '" + item_url + "'" )
	_fetch_json_from_url(item_url)
	# print(item_json)
	
	# Needed to refresh the GUI when values or scene structure has changed
	# notify_property_list_changed()

func _delete_media_children() -> void:
	for child in get_children():
		if child is LivingMedia:
			child.queue_free()

func _refresh_media_children() -> void:
	for child in get_children():
		if child is LivingMedia:
			child.fetch_omeka_info()


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
			var description_term = item_dict["dcterms:description"]
			if "@value" in description_term:
				description = description_term["@value"]

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
func instantiate_media() -> void:

	_delete_media_children()

	if selected_media < 0 or selected_media >= media.size():
		push_error("Media index %s out of range. Number of available media: %s" % [selected_media, media.size()])
		return

	#  Instantiate the new LivingMedia child
	var new_media_id := media[selected_media]
	var new_child = LivingMedia.new()
	new_child.media_id = new_media_id
	new_child.name = "LivingMedia-" + str(new_media_id)
	add_child(new_child)
	
	if Engine.is_editor_hint():
		# Important. Set the owner to make it visible in the scene dock and persist
		new_child.owner = get_tree().edited_scene_root
	
	# Needed to refresh the Editor GUI when values or scene structure has changed
	if Engine.is_editor_hint():
		# For @tool scripts, access EditorInterface to save
		EditorInterface.mark_scene_as_unsaved()
