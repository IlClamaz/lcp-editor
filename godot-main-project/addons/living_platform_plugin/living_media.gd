@tool
extends Node

class_name LivingMedia

@export var item_id: int = 0
@export_tool_button("Fetch Omeka Info") var fetch_living_info = fetch_omeka_info


@export var source_url: String
@export var media_type: String
@export var modified: String


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


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

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
	# var item_url: String = url + "/api/items/?id=" + str(item_id)
	# var item_url: String = url + "/api/items?pretty_print=1"
	var item_url: String = base_url + "/api/media/" + str(item_id) + "?pretty_print=1" 
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
