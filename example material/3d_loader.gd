extends Node

const GLB_URL := "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/2.0/Avocado/glTF-Binary/Avocado.glb"
@export var loaded_scale: float = 1.0

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	var err := _http.request(GLB_URL, [], HTTPClient.METHOD_GET)
	if err != OK:
		push_error("Impossibile avviare la richiesta: %s" % err)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_error("Download fallito. result=%s, http=%s" % [result, response_code])
		return

	var gltf := GLTFDocument.new()
	var state := GLTFState.new()

	# ordine giusto: bytes, base_path, state, flags(opzionale)
	var err := gltf.append_from_buffer(body, "", state) # oppure: , GLTFDocument.FLAGS_NONE
	if err != OK:
		push_error("Errore GLTF append_from_buffer: %s" % err)
		return

	var scene_root: Node = gltf.generate_scene(state)
	if scene_root == null:
		push_error("Impossibile generare la scena dal GLB.")
		return

	get_tree().current_scene.add_child(scene_root)

	if scene_root is Node3D:
		(scene_root as Node3D).scale = Vector3.ONE * loaded_scale

	print("GLB caricato con successo: ", scene_root.name)
