@tool
extends RefCounted
class_name CuratorDatabasePanel

## DATABASE panel UI: dropdowns, save/download/create/restore. Uses services.

signal ui_refresh_requested
signal env_refresh_requested
signal status_changed(text: String)

const CURATED_SCENES_DIR := "res://curated_scenes"

var ui: CuratorDockUIBuilder.CuratorDockUI
var host: Control
var editor_interface: EditorInterface
var access: CuratorSceneAccess
var remote: CuratorRemoteScenes
var catalog: CuratorOmekaCatalog
var busy: CuratorBusyState
var scene_setup: CuratorSceneSetup
var events_panel: CuratorEventsPanel
var inst: CuratorEnvironmentInstantiator
var dl: CuratorDownloadProgress

var pending_post_open_sync: bool = false


func bind(
	_ui: CuratorDockUIBuilder.CuratorDockUI,
	_host: Control,
	_editor_interface: EditorInterface,
	_access: CuratorSceneAccess,
	_remote: CuratorRemoteScenes,
	_catalog: CuratorOmekaCatalog,
	_busy: CuratorBusyState,
	_scene_setup: CuratorSceneSetup,
	_events_panel: CuratorEventsPanel,
	_inst: CuratorEnvironmentInstantiator,
	_dl: CuratorDownloadProgress
) -> void:
	ui = _ui
	host = _host
	editor_interface = _editor_interface
	access = _access
	remote = _remote
	catalog = _catalog
	busy = _busy
	scene_setup = _scene_setup
	events_panel = _events_panel
	inst = _inst
	dl = _dl

	remote.upload_finished.connect(_on_upload_finished)
	remote.fetch_finished.connect(_on_fetch_finished)
	remote.workflow_progress.connect(func(msg: String):
		status_changed.emit(msg)
	)
	remote.workflow_finished.connect(_on_workflow_finished)

	inst.rebuild_finished.connect(_on_inst_rebuild_finished)
	inst.auto_layout_finished.connect(_on_inst_auto_layout_finished)
	inst.failed.connect(_on_inst_failed)
	dl.progress_changed.connect(_on_dl_progress)


func wire_ui() -> void:
	if ui == null:
		return
	ui.global_omeka_url.text_changed.connect(func(t: String):
		access.save_global_default_url(editor_interface, t)
		access.apply_global_url_to_current_scene(editor_interface, t)
	)
	ui.fetch_env_btn.pressed.connect(fetch_environments)
	ui.env_list.item_selected.connect(_on_env_selected)
	ui.item_set_fetch_btn.pressed.connect(fetch_item_sets)
	ui.item_set_list.item_selected.connect(_on_item_set_selected)
	ui.scene_list.item_selected.connect(func(_idx: int):
		ui_refresh_requested.emit()
	)
	ui.save_btn.pressed.connect(save_pressed)
	ui.scene_fetch_btn.pressed.connect(fetch_scenes)
	ui.download_btn.pressed.connect(download_or_create_pressed)
	ui.restore_components_btn.pressed.connect(restore_components_pressed)


func refresh_controls(has_valid_open_env: bool) -> void:
	if ui == null:
		return
	var selected_env_id := 0
	if ui.env_list != null and ui.env_list.item_count > 0:
		selected_env_id = int(ui.env_list.get_selected_id())
	var has_valid_dropdown_env := selected_env_id > 0

	ui.item_set_fetch_btn.disabled = busy.is_busy
	ui.fetch_env_btn.disabled = busy.is_busy
	ui.scene_fetch_btn.disabled = busy.is_busy or not has_valid_dropdown_env

	var has_valid_scene_selected := false
	var is_create_selected := false
	if ui.scene_list != null:
		var sel_idx: int = ui.scene_list.get_selected()
		if sel_idx > 0 and not ui.scene_list.is_item_disabled(sel_idx):
			has_valid_scene_selected = true
			var meta: Variant = ui.scene_list.get_item_metadata(sel_idx)
			if typeof(meta) == TYPE_STRING and meta == "CREATE_ACTION":
				is_create_selected = true

	ui.download_btn.disabled = busy.is_busy or not has_valid_dropdown_env or not has_valid_scene_selected
	ui.download_btn.text = "CREATE" if is_create_selected else "DOWNLOAD"
	ui.save_btn.disabled = not has_valid_open_env or busy.is_busy
	ui.restore_components_btn.disabled = busy.is_busy or not has_valid_open_env


func on_scene_changed(env: LivingEnvironment) -> void:
	if ui == null:
		return
	if env != null:
		var saved_pwd: String = access.load_env_password(editor_interface, env.item_id)
		env.nextsave_pwd = saved_pwd
		ui.save_pwd_edit.text = saved_pwd
		if ui.env_list != null:
			var option_index: int = ui.env_list.get_item_index(env.item_id)
			if option_index != -1 and ui.env_list.get_selected_id() != env.item_id:
				ui.env_list.select(option_index)
				load_pwd_for_selected_env()
				fetch_scenes()
	else:
		if ui.env_list != null and ui.env_list.item_count > 0:
			ui.env_list.select(0)
		_reset_scene_list_placeholder()
		status_changed.emit("")
		load_pwd_for_selected_env()


func load_pwd_for_selected_env() -> void:
	if ui == null or ui.env_list == null:
		return
	var selected_id := int(ui.env_list.get_selected_id())
	if selected_id <= 0:
		ui.save_pwd_edit.text = ""
		return
	ui.save_pwd_edit.text = access.load_env_password(editor_interface, selected_id)


func sync_dynamic_properties_on_startup() -> void:
	var base_url := ui.global_omeka_url.text.strip_edges()
	var result: Dictionary = await catalog.fetch_and_save_dynamic_properties(host, base_url, editor_interface)
	if not result.get("ok", false):
		push_warning(
			"Curator Dock: dynamic properties sync failed (%s)."
			% str(result.get("error", "unknown error"))
		)
		return
	print(
		"Curator Dock: wrote %d dynamic property table row(s) to %s."
		% [int(result.get("count", 0)), str(result.get("path", ""))]
	)


# --- Item sets / environments / scenes ----------------------------------------

func fetch_item_sets() -> void:
	var base_url: String = ui.global_omeka_url.text.strip_edges()
	if base_url == "":
		push_error("First insert the OmekaS URL")
		return

	var prev_selected_id := 0
	if ui.item_set_list != null and ui.item_set_list.item_count > 0:
		prev_selected_id = int(ui.item_set_list.get_selected_id())

	ui.item_set_list.clear()
	ui.item_set_list.add_item("Loading item sets...", 0)
	ui.item_set_list.disabled = true
	ui.item_set_fetch_btn.disabled = true
	ui.item_set_fetch_btn.text = "Loading..."

	var result: Dictionary = await catalog.list_item_sets(host, base_url)
	if not result.get("ok", false):
		_finish_item_set_fetch_error(str(result.get("error", "Connection Error")))
		return

	var item_sets: Array = result.get("items", [])
	ui.item_set_list.clear()
	ui.item_set_list.add_item("None", 0)

	for s in item_sets:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var s_id := int(s.get("id", 0))
		if s_id <= 0:
			continue
		ui.item_set_list.add_item(str(s.get("title", "No Title")), s_id)

	var reselect_idx := ui.item_set_list.get_item_index(prev_selected_id)
	if reselect_idx != -1:
		ui.item_set_list.select(reselect_idx)
	else:
		ui.item_set_list.select(0)

	ui.item_set_list.disabled = false
	ui.item_set_fetch_btn.disabled = false
	ui.item_set_fetch_btn.text = "Update List"
	print("Curator Dock: Found %d Item Sets." % item_sets.size())


func _finish_item_set_fetch_error(msg: String) -> void:
	ui.item_set_list.clear()
	ui.item_set_list.add_item("None", 0)
	ui.item_set_list.add_item("(%s)" % msg, -1)
	ui.item_set_list.set_item_disabled(1, true)
	ui.item_set_list.select(0)
	ui.item_set_list.disabled = false
	ui.item_set_fetch_btn.disabled = false
	ui.item_set_fetch_btn.text = "Update List"


func _on_item_set_selected(_idx: int) -> void:
	await fetch_environments()


func fetch_environments() -> void:
	var base_url: String = ui.global_omeka_url.text.strip_edges()
	if base_url == "":
		push_error("First insert the OmekaS URL")
		return

	var selected_item_set_id := 0
	if ui.item_set_list != null and ui.item_set_list.item_count > 0:
		selected_item_set_id = int(ui.item_set_list.get_selected_id())

	busy.set_error(false)
	status_changed.emit("")

	ui.env_list.clear()
	ui.env_list.add_item("Querying the database...", 0)
	ui.env_list.disabled = true
	ui.fetch_env_btn.disabled = true
	ui.fetch_env_btn.text = "Loading..."

	var envs_result: Dictionary = await catalog.list_environments(host, base_url, selected_item_set_id)
	if not envs_result.get("ok", false):
		_finish_env_fetch_error(str(envs_result.get("error", "Connection Error")))
		return

	var envs: Array = envs_result.get("items", [])
	ui.env_list.clear()
	ui.env_list.add_item("Select an Environment...", 0)
	ui.env_list.set_item_disabled(0, true)

	for env_item in envs:
		if typeof(env_item) != TYPE_DICTIONARY:
			continue
		var env_id := int(env_item.get("id", 0))
		if env_id <= 0:
			continue
		ui.env_list.add_item(str(env_item.get("title", "No Title")), env_id)

	if envs.is_empty():
		ui.env_list.set_item_text(0, "No Environments Found")

	var env: LivingEnvironment = access.get_environment(editor_interface)
	var has_valid_open_env := (env != null) and int(env.item_id) > 0
	var found_open_env := false

	if has_valid_open_env:
		var option_index: int = ui.env_list.get_item_index(env.item_id)
		if option_index != -1:
			ui.env_list.select(option_index)
			found_open_env = true
			fetch_scenes()

	if not found_open_env:
		if ui.env_list.item_count > 0:
			ui.env_list.select(0)
		_reset_scene_list_placeholder()

	ui.env_list.disabled = false
	ui.fetch_env_btn.disabled = false
	ui.fetch_env_btn.text = "Update List"
	print("Curator Dock: Found %d Environments." % envs.size())
	events_panel.refresh(env)
	ui_refresh_requested.emit()


func fetch_scenes() -> void:
	var selected_env_id := int(ui.env_list.get_selected_id())
	if selected_env_id <= 0:
		_reset_scene_list_placeholder()
		ui_refresh_requested.emit()
		return

	ui.scene_fetch_btn.disabled = true
	ui.scene_fetch_btn.text = "Updating..."
	ui.scene_list.clear()
	ui.scene_list.add_item("Looking for scenes...", 0)
	ui.scene_list.set_item_disabled(0, true)
	ui.scene_list.select(0)

	remote.fetch_remote_scenes_for_env(
		host,
		ui.global_omeka_url.text.strip_edges(),
		selected_env_id,
		ui.save_pwd_edit.text
	)


func save_pressed() -> void:
	var root_node: Node = access.edited_scene_root(editor_interface)
	if root_node == null:
		_toast("No open scenes to save.", 2.0)
		return

	var current_path: String = root_node.scene_file_path
	var display_name: String = to_pretty_name(current_path.get_file())

	var dialog := ConfirmationDialog.new()
	dialog.title = "Save & Upload"

	var vbox := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Type a name for this scene (e.g. Environment Name - Date - Your Initials) \n ⚠️ If you don't change the name, the existing scene will be overwritten ⚠️"
	vbox.add_child(lbl)

	var name_edit := LineEdit.new()
	name_edit.text = display_name
	name_edit.custom_minimum_size = Vector2(350, 0)
	vbox.add_child(name_edit)

	var error_lbl := Label.new()
	error_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	error_lbl.hide()
	vbox.add_child(error_lbl)

	dialog.add_child(vbox)
	host.add_child(dialog)

	name_edit.text_changed.connect(func(new_text: String):
		var check_name: String = to_safe_filename(new_text)
		var base_dir: String = current_path.get_base_dir() if current_path != "" else CURATED_SCENES_DIR
		var check_path: String = base_dir.path_join(check_name)
		if check_path != current_path and FileAccess.file_exists(check_path):
			error_lbl.text = "⚠️ Attention: a scene with this name already exists and will be overwritten"
			error_lbl.show()
		else:
			error_lbl.hide()
	)

	dialog.confirmed.connect(func():
		var safe_name: String = to_safe_filename(name_edit.text)
		var base_dir: String = current_path.get_base_dir() if current_path != "" else CURATED_SCENES_DIR
		var new_path: String = base_dir.path_join(safe_name)
		var needs_rename: bool = (current_path == "" or new_path != current_path)
		dialog.hide()
		_execute_save_and_upload.call_deferred(current_path, new_path, needs_rename)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	name_edit.text_submitted.connect(func(_t):
		dialog.hide()
		dialog.emit_signal("confirmed")
	)

	dialog.popup_centered(Vector2(400, 100))
	name_edit.grab_focus()
	name_edit.select_all()


func download_or_create_pressed() -> void:
	var selected_env_id := int(ui.env_list.get_selected_id())
	if selected_env_id <= 0:
		_toast("Select a valid environment first", 2.0)
		return

	var selected_idx: int = ui.scene_list.get_selected()
	if selected_idx < 0 or ui.scene_list.is_item_disabled(selected_idx):
		_toast("Select a valid scene in the list or create a new one +", 2.0)
		return

	var meta: Variant = ui.scene_list.get_item_metadata(selected_idx)
	if typeof(meta) == TYPE_STRING and meta == "CREATE_ACTION":
		fetch_scenes()
		create_new_scene()
		return

	if typeof(meta) != TYPE_STRING or str(meta) == "":
		return

	ui.download_btn.disabled = true
	ui.download_btn.text = "Initializing..."
	busy.begin_work()
	ui_refresh_requested.emit()

	remote.download_and_setup_remote_scene(
		host,
		editor_interface,
		ui.global_omeka_url.text.strip_edges(),
		selected_env_id,
		str(meta),
		ui.save_pwd_edit.text.strip_edges(),
		dl
	)


func create_new_scene() -> void:
	var selected_idx := ui.env_list.get_selected() if ui.env_list != null else -1
	var selected_env_id := int(ui.env_list.get_selected_id()) if ui.env_list != null else 0

	if selected_env_id <= 0 or selected_idx < 0:
		_toast("Firstly select an environment", 2.0)
		return

	busy.begin_work()
	status_changed.emit("Creating a new scene...")
	dl.reset()
	_start_dl_when_env_ready()
	ui_refresh_requested.emit()
	inst.run(selected_env_id, ui.env_list.get_item_text(selected_idx), ui.global_omeka_url.text.strip_edges())


func restore_components_pressed() -> void:
	if busy.is_busy:
		return
	pending_post_open_sync = false

	var env: LivingEnvironment = access.get_environment(editor_interface)
	busy.begin_work()
	status_changed.emit("Elaborating...")
	ui_refresh_requested.emit()

	dl.reset()
	dl.start(env, host)
	_bind_env_import_progress(env)

	env.rebuild_completed.connect(func(success: bool):
		dl.mark_build_finished(success)
		busy.end_work(success)
		if success:
			status_changed.emit("Completed")
		else:
			var err_msg: String = env.title if env.title != null else ""
			if "404" in err_msg or "HTTP" in err_msg:
				status_changed.emit("Connection Error")
			else:
				status_changed.emit("Error")
		ui_refresh_requested.emit()
		env_refresh_requested.emit()
	, CONNECT_ONE_SHOT)

	env.rebuild_environment()


# --- Naming -------------------------------------------------------------------

func to_pretty_name(file_name: String) -> String:
	if file_name == "":
		return "New Scene"
	var base: String = file_name.get_basename()
	base = base.replace("_-_", " - ")
	base = base.replace("_", " ")
	var words: PackedStringArray = base.split(" ")
	for i in range(words.size()):
		if words[i].length() > 0:
			if i == words.size() - 1 and words[i].length() <= 3:
				words[i] = words[i].to_upper()
			else:
				words[i] = words[i].substr(0, 1).to_upper() + words[i].substr(1)
	return " ".join(words)


func to_safe_filename(pretty_name: String) -> String:
	var regex := RegEx.new()
	# Keep letters, numbers, spaces and dashes only.
	regex.compile("[^a-zA-Z0-9_\\s-]")
	var sanitized: String = regex.sub(pretty_name, "", true)

	# Must lowercase: display names are Title Case, on-disk names are snake/lower.
	var safe: String = sanitized.strip_edges().to_lower()

	safe = safe.replace(" - ", "_-_")
	safe = safe.replace(" ", "_")

	while safe.find("__") != -1:
		safe = safe.replace("__", "_")

	if safe == "" or safe == ".tscn":
		safe = "new_scene"

	if not safe.ends_with(".tscn"):
		safe += ".tscn"

	return safe


# --- Internals ----------------------------------------------------------------

func _on_env_selected(_idx: int) -> void:
	load_pwd_for_selected_env()
	var selected_env_id := int(ui.env_list.get_selected_id())
	if selected_env_id > 0:
		fetch_scenes()
	else:
		_reset_scene_list_placeholder()
	ui_refresh_requested.emit()


func _execute_save_and_upload(old_path: String, new_path: String, needs_rename: bool) -> void:
	await host.get_tree().create_timer(0.1).timeout

	ui.save_btn.disabled = true
	ui.save_btn.text = "SAVING..."

	if needs_rename:
		editor_interface.save_scene_as(new_path)
		await host.get_tree().create_timer(0.5).timeout
		if old_path != "" and FileAccess.file_exists(old_path):
			var da := DirAccess.open(old_path.get_base_dir())
			if da:
				da.remove(old_path.get_file())
		EditorInterface.get_resource_filesystem().scan()
		await host.get_tree().create_timer(0.5).timeout
	else:
		editor_interface.save_scene()
		await host.get_tree().create_timer(0.5).timeout

	remote.upload_scene(editor_interface, ui.save_pwd_edit.text)


func _on_upload_finished(success: bool, msg: String) -> void:
	_toast(msg, 2.0)
	if not success:
		push_error("Curator Dock: " + msg)
	ui.save_btn.text = "SAVE..."
	ui.save_btn.disabled = false


func _on_fetch_finished(success: bool, file_list: Array, msg: String) -> void:
	ui.scene_fetch_btn.disabled = false
	ui.scene_fetch_btn.text = "Update List"
	ui.scene_list.clear()
	ui.scene_list.add_item("Select a scene...", 0)
	ui.scene_list.set_item_disabled(0, true)

	var count := 1
	if not success:
		ui.scene_list.set_item_text(0, "Connection Error or missing password")
		_toast(msg, 3.5)
	else:
		for f in file_list:
			if typeof(f) == TYPE_DICTIONARY:
				var fname := str(f.get("name", ""))
				if fname.ends_with(".tscn"):
					ui.scene_list.add_item(to_pretty_name(fname), count)
					ui.scene_list.set_item_metadata(count, fname)
					count += 1
		if count == 1:
			ui.scene_list.set_item_text(0, "No scenes found, create one")

	var create_idx: int = ui.scene_list.item_count
	ui.scene_list.add_item("+", create_idx)
	ui.scene_list.set_item_metadata(create_idx, "CREATE_ACTION")
	ui.scene_list.disabled = false
	ui.scene_list.select(0)
	ui_refresh_requested.emit()


func _on_workflow_finished(success: bool, msg: String) -> void:
	busy.end_work(success)
	_toast(msg, 3.0)
	ui.download_btn.text = "DOWNLOAD"
	status_changed.emit("Completed" if success else "Error")
	if success:
		var env: LivingEnvironment = access.get_environment(editor_interface)
		scene_setup.ensure_all(env, access.edited_scene_root(editor_interface))
	ui_refresh_requested.emit()
	env_refresh_requested.emit()


func _on_inst_rebuild_finished(success: bool, _env: Variant) -> void:
	dl.mark_build_finished(success)
	if not success:
		busy.end_work(false)
		status_changed.emit("Connection Error")
		ui_refresh_requested.emit()
		return
	busy.end_work(true)
	status_changed.emit("Completed")
	ui_refresh_requested.emit()


func _on_inst_auto_layout_finished(executed: bool) -> void:
	if executed:
		env_refresh_requested.emit()
	ui_refresh_requested.emit()


func _on_inst_failed(msg: Variant) -> void:
	busy.end_work(false)
	if "404" in str(msg) or "HTTP" in str(msg):
		status_changed.emit("Connection Error")
	else:
		status_changed.emit("Error")
	ui_refresh_requested.emit()
	push_warning(msg)


func _on_dl_progress(pct: Variant, done: Variant, total: Variant) -> void:
	if int(total) == 0:
		return
	if int(done) < int(total):
		status_changed.emit("Download: %d%% (%d/%d)" % [int(pct), int(done), int(total)])


func _start_dl_when_env_ready() -> void:
	_start_dl_when_env_ready_async()


func _start_dl_when_env_ready_async() -> void:
	while busy.is_busy and host != null and host.is_inside_tree():
		var env: LivingEnvironment = access.get_environment(editor_interface)
		if env != null:
			dl.reset()
			dl.start(env, host)
			_bind_env_import_progress(env)
			return
		await host.get_tree().process_frame


func _bind_env_import_progress(env: LivingEnvironment) -> void:
	if env == null:
		return
	var cb := Callable(self, "_on_env_import_progress")
	if not env.import_progress.is_connected(cb):
		env.import_progress.connect(cb)


func _on_env_import_progress(txt: String) -> void:
	status_changed.emit(txt)


func _finish_env_fetch_error(msg: String) -> void:
	ui.env_list.clear()
	ui.env_list.add_item(msg, 0)
	ui.env_list.disabled = false
	ui.fetch_env_btn.disabled = false
	ui.fetch_env_btn.text = "Update List"


func _reset_scene_list_placeholder() -> void:
	if ui == null or ui.scene_list == null:
		return
	ui.scene_list.clear()
	ui.scene_list.add_item("Firstly select an environment...", 0)
	ui.scene_list.set_item_disabled(0, true)
	ui.scene_list.select(0)


func _notify_resource_filesystem(res_path: String) -> void:
	if editor_interface == null:
		return
	var fs = editor_interface.get_resource_filesystem()
	if fs != null:
		fs.update_file(res_path)


func _toast(msg: String, sec: float = 1.2) -> void:
	if host == null or not host.is_inside_tree():
		return
	var d := AcceptDialog.new()
	d.title = ""
	d.dialog_text = msg
	d.exclusive = false
	d.unresizable = true
	d.get_ok_button().visible = false
	host.add_child(d)
	d.popup_centered()
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = sec
	host.add_child(t)
	t.timeout.connect(func():
		if is_instance_valid(d):
			d.hide()
			d.queue_free()
		if is_instance_valid(t):
			t.queue_free()
	, CONNECT_ONE_SHOT)
	t.start()
