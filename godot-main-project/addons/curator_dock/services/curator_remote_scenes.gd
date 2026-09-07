@tool
extends RefCounted
class_name CuratorRemoteScenes

## Remote scene I/O: list / download / upload .tscn via Nextcloud + Omeka medium URI.
## No UI. Uses CuratorSceneAccess for the open environment.

signal upload_finished(success: bool, msg: String)
signal fetch_finished(success: bool, list: Array, msg: String)
signal workflow_progress(step_name: String)
signal workflow_finished(success: bool, msg: String)

signal _direct_scene_list_success(list: Array[Dictionary])
signal _direct_scene_list_error(reason: String)
signal _dummy_success(filename: String, local_path: String, type: String)
signal _dummy_error(reason: String)

var access: CuratorSceneAccess


func bind_access(_access: CuratorSceneAccess) -> void:
	access = _access


func upload_scene(editor_interface: EditorInterface, pwd: String) -> void:
	var env := access.get_environment(editor_interface)
	if env == null:
		upload_finished.emit(false, "Environment not valid")
		return

	if env.medium_uri == null or env.medium_uri.strip_edges() == "":
		upload_finished.emit(false, "The environment has a problem on the database")
		return

	var root_node = access.edited_scene_root(editor_interface)
	var scene_path = root_node.scene_file_path if root_node != null else ""
	if scene_path.strip_edges() == "" or not FileAccess.file_exists(scene_path):
		upload_finished.emit(false, "Scene file not found: %s" % scene_path)
		return

	var temp_packed := load(scene_path) as PackedScene
	if temp_packed == null:
		upload_finished.emit(false, "Failed loading scene for upload: %s" % scene_path)
		return

	var temp_root := temp_packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if temp_root == null:
		upload_finished.emit(false, "Failed instantiating scene for upload.")
		return
	_clean_media_recursive(temp_root)

	var clean_packed := PackedScene.new()
	clean_packed.pack(temp_root)

	var original_filename = scene_path.get_file()
	var temp_upload_path := "user://".path_join(original_filename)

	var err = ResourceSaver.save(clean_packed, temp_upload_path)
	temp_root.free()

	if err != OK:
		upload_finished.emit(false, "Impossible creating temporary clean file.")
		return

	env.nextsave_pwd = pwd.strip_edges()

	env.scene_upload_success.connect(func(_save_name, _url):
		if FileAccess.file_exists(temp_upload_path):
			DirAccess.remove_absolute(temp_upload_path)
		upload_finished.emit(true, "Scene saved with success!")
	, CONNECT_ONE_SHOT)

	env.scene_upload_error.connect(func(err_msg):
		if FileAccess.file_exists(temp_upload_path):
			DirAccess.remove_absolute(temp_upload_path)
		upload_finished.emit(false, "Error: " + err_msg)
	, CONNECT_ONE_SHOT)

	env.upload_scene(temp_upload_path)


func download_and_setup_remote_scene(
	host: Node,
	editor_interface: EditorInterface,
	base_url: String,
	env_id: int,
	remote_file_name: String,
	pwd: String,
	dl_progress
) -> void:
	if host == null or env_id <= 0 or base_url.strip_edges() == "" or remote_file_name.strip_edges() == "":
		workflow_finished.emit(false, "Parameters not valid for download.")
		return

	workflow_progress.emit("Getting the scene URL...")
	var medium_uri = await _resolve_env_medium_uri_async(host, base_url, env_id)
	if medium_uri == "":
		workflow_finished.emit(false, "No medium URI found for this environment.")
		return

	workflow_progress.emit("Downloading Scene...")
	var local_dir := "res://curated_scenes/"
	if not DirAccess.dir_exists_absolute(local_dir):
		DirAccess.make_dir_recursive_absolute(local_dir)

	var scene_download_result = await _download_file_async(host, medium_uri, local_dir, remote_file_name, pwd)
	if not scene_download_result.get("ok", false):
		workflow_finished.emit(false, "Error downloading scene: " + scene_download_result.get("error", "Sconosciuto"))
		return

	var local_scene_path: String = scene_download_result["local_path"]

	workflow_progress.emit("Importing Scene...")
	var fs = EditorInterface.get_resource_filesystem()
	fs.update_file(local_scene_path)
	if not fs.is_scanning():
		fs.scan()

	workflow_progress.emit("Opening Scene...")
	await _safe_open_scene_async(host, fs, local_scene_path)

	workflow_progress.emit("Downloading composition & media...")
	var env := access.get_environment(editor_interface)
	if env != null:
		access.apply_global_url_to_current_scene(editor_interface, base_url)
		dl_progress.reset()
		dl_progress.start(env, host)
		env.rebuild_completed.connect(func(success: bool):
			dl_progress.mark_build_finished(success)
			if success:
				workflow_finished.emit(true, "Scene downloaded and components restored")
			else:
				workflow_finished.emit(false, "Scene downloaded but components restore failed")
		, CONNECT_ONE_SHOT)
		env.rebuild_environment()
	else:
		workflow_finished.emit(false, "Scene downloaded, but no env found")


func fetch_remote_scenes_for_env(host: Node, base_url: String, env_id: int, pwd: String) -> void:
	if host == null:
		fetch_finished.emit(false, [], "Host not valid")
		return
	if env_id <= 0:
		fetch_finished.emit(false, [], "Firstly select a valid environment")
		return
	if base_url.strip_edges() == "":
		fetch_finished.emit(false, [], "Database URL not valid.")
		return

	var medium_uri = await _resolve_env_medium_uri_async(host, base_url, env_id)
	if medium_uri == "":
		fetch_finished.emit(false, [], "No medium found attached to this environment")
		return

	_disconnect_all_signal_slots(_direct_scene_list_success)
	_disconnect_all_signal_slots(_direct_scene_list_error)

	_direct_scene_list_success.connect(func(list):
		fetch_finished.emit(true, list, "Query completed")
	, CONNECT_ONE_SHOT)

	_direct_scene_list_error.connect(func(_reason):
		fetch_finished.emit(false, [], "Connection error")
	, CONNECT_ONE_SHOT)

	var lister := HTTPLister.new(
		medium_uri,
		pwd.strip_edges(),
		_direct_scene_list_success,
		_direct_scene_list_error
	)
	host.add_child(lister)
	lister.do_list()


func _clean_media_recursive(node: Node) -> void:
	for child in node.get_children():
		var is_protected = (
			child is LivingItem
			or child is LivingCamera
			or child is LivingLights
			or child is LivingStargate
			or child is GestureGameController
			or child is ExperienceController
			or child is SketcherGameController
			or child is SketcherGameCoordinator
		)
		if node is LivingItem and not is_protected:
			child.free()
		else:
			_clean_media_recursive(child)


func _resolve_env_medium_uri_async(host: Node, base_url: String, env_id: int) -> String:
	var item_url := base_url.strip_edges().trim_suffix("/") + "/api/items?pretty_print=1&id=" + str(env_id)
	var response = await HTTPDownloader.request_json(host, item_url, 15.0)
	if not response.get("ok", false):
		return ""
	var data = response.get("json", [])
	if typeof(data) != TYPE_ARRAY or data.is_empty():
		return ""
	var item = data[0]
	if typeof(item) != TYPE_DICTIONARY:
		return ""
	if item.has("lcp_form:has_URI"):
		var uri_array: Array = item["lcp_form:has_URI"]
		if not uri_array.is_empty() and typeof(uri_array[0]) == TYPE_DICTIONARY:
			return str(uri_array[0].get("@id", ""))
	return ""


func _download_file_async(host: Node, uri: String, local_dir: String, remote_file: String, pwd: String) -> Dictionary:
	var downloader := HTTPDownloader.new(uri, local_dir, "", _dummy_success, _dummy_error)
	downloader.remote_pwd = pwd.strip_edges()
	downloader.target_remote_file = remote_file.strip_edges()
	host.add_child(downloader)

	var result = {"ok": false, "local_path": "", "error": ""}
	downloader.success_signal.connect(func(_fname, path, _type):
		result["ok"] = true
		result["local_path"] = path
	, CONNECT_ONE_SHOT)
	downloader.error_signal.connect(func(err):
		result["error"] = err
	, CONNECT_ONE_SHOT)
	downloader.do_download()

	while not result["ok"] and result["error"] == "":
		if not is_instance_valid(downloader) or downloader.is_queued_for_deletion():
			if result["error"] == "" and not result["ok"]:
				result["error"] = "Download canceled by the system"
			break
		await host.get_tree().process_frame
	return result


func _safe_open_scene_async(host: Node, fs: EditorFileSystem, path: String) -> void:
	var clean_path = path.simplify_path()
	while fs.is_scanning():
		await host.get_tree().process_frame
	await host.get_tree().create_timer(0.4).timeout

	var current_root = EditorInterface.get_edited_scene_root()
	var current_path = current_root.scene_file_path.simplify_path() if current_root != null else ""
	if current_path == clean_path:
		EditorInterface.reload_scene_from_path(clean_path)
	else:
		EditorInterface.open_scene_from_path(clean_path)
	await host.get_tree().create_timer(0.5).timeout


func _disconnect_all_signal_slots(sig: Signal) -> void:
	for conn in sig.get_connections():
		var cb = conn.get("callable")
		if cb != null:
			sig.disconnect(cb)
