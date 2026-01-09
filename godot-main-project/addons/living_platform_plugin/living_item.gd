@tool
extends Node3D

class_name LivingItem

# Export decorators.
# See: https://docs.godotengine.org/en/4.5/tutorials/scripting/gdscript/gdscript_exports.html#basic-use
@export var item_id: int = 0
@export_tool_button("Fetch URL") var fetch_living_media = fetch_omeka_info

@export var title: String = ""
@export var modified: String = ""
@export var resource_class: int = 0

@export var item_sets: Array[int] = []
@export var media: Array[int] = []


# Set any of the given flags from the editor.
@export_flags("PreExperience", "Experience", "PostExperience") var experience_visibility = 0

# Test enumerations
#enum NamedEnum {THING_1, THING_2, ANOTHER_THING = -1}
#@export var test_enum: NamedEnum

#@export var ints: Array[int] = [1, 2, 3]

# Nested typed arrays such as `Array[Array[float]]` are not supported yet.
#@export var two_dimensional: Array[Array] = [[1.0, 2.0], [3.0, 4.0]]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("Test Button Ready.")
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _enter_tree():
	print("Living Item Tree Enter.")
	
	#pressed.connect(clicked)
	#var n = Button.new()
	#add_child(n, true)


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

	# Retrieve info from the Omeka server
	# var item_url: String = url + "/api/items/?id=" + str(item_id)
	# var item_url: String = url + "/api/items?pretty_print=1"
	var item_url: String = base_url + "/api/items?pretty_print=1&id=" + str(item_id)
	print("Getting info from OmekaURL '" + item_url + "'" )
	fetch_json_from_url(item_url)
	# print(item_json)
	
	# Needed to refresh the GUI when values or scene structure has changed
	notify_property_list_changed()


func fetch_json_from_url(url: String) -> void:
	# Create HTTPRequest node
	var http_request := HTTPRequest.new()
	add_child(http_request)

	# Connect completion callback
	http_request.request_completed.connect(_on_fetch_json_completed)

	# Clear all fields
	title = ""
	modified = ""
	resource_class = 0
	item_sets.clear()
	media.clear()

	# Start GET request
	var err := http_request.request(url)
	if err != OK:
		push_error("HTTP error occurred: %s" % err)
		title = "ERROR"
		http_request.queue_free()
	else:
		print("Request delegated to child %s" % http_request.name)

func _on_fetch_json_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	# Basic HTTP error handling (4xx / 5xx)
	if response_code < 200 or response_code >= 300:
		push_error("HTTP error occurred: response code %d" % response_code)
		title = "ERROR"
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
		title = "ERROR"
		return

	# Parse JSON body
	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		push_error("Invalid response content: JSON parse error %d" % parse_err)
		title = "ERROR"
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
			title = item_dict["o:title"]
			modified = item_dict["o:modified"]["@value"]
			var resource_class_entry = item_dict["o:resource_class"]
			if resource_class_entry:
				print("Valid rc entry")
				resource_class = item_dict["o:resource_class"]["o:id"]
			else:
				print("Skipping resource_class")
			
			for s in item_dict["o:item_set"]:
				var set_id: int = s["o:id"]  # Forces convertion to int (or it would be a float)
				# print(str(typeof(set_id)))
				item_sets.append(set_id)

			media.clear()
			for m_dict in item_dict["o:media"]:
				# print("Appending media: ", typeof(m_dict), " ",  m_dict)
				var media_id: int = m_dict["o:id"]
				print("Appending media id: ", media_id)
				media.append(media_id)

			# Needed to refresh the GUI when values or scene structure has changed
			notify_property_list_changed()

		else:
			title = "ERROR"
			push_error("Got an empty array.")

	else:
		title = "ERROR"
		push_error("Expected an array. Found %s." % str(typeof(data)))

	# print("Fetch completed")
