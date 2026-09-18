@tool
extends VBoxContainer

const TEMPLATE_ENV_SCENE := "res://addons/living_platform_plugin/scripts/core/living_environment_root.tscn"

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager

# services
var access := CuratorSceneAccess.new()
var remote := CuratorRemoteScenes.new()
var catalog := CuratorOmekaCatalog.new()

# session
var busy := CuratorBusyState.new()
var selection := CuratorSelectionBridge.new()

# panels
var inventory_panel := CuratorInventoryPanel.new()
var events_panel := CuratorEventsPanel.new()
var mise_panel := CuratorMiseEnScenePanel.new()
var database_panel := CuratorDatabasePanel.new()

# shared helpers
var scene_setup := CuratorSceneSetup.new()
var inst := CuratorEnvironmentInstantiator.new()
var dl := CuratorDownloadProgress.new()
var ui_builder := CuratorDockUIBuilder.new()
var hooks := CuratorEditorHooks.new()
var ui: CuratorDockUIBuilder.CuratorDockUI

var _last_scene_root: Node = null
var _had_scene := false
var _env_refresh_pending: bool = false


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	ui = ui_builder.build(content)

	remote.bind_access(access)

	var icon := get_theme_icon("ImportFail", "EditorIcons")
	inventory_panel.bind_ui(ui.components_list, ui.preview, icon)
	events_panel.bind_ui(ui.events_list, ui_builder)
	events_panel.bind_env_list(ui.env_list)

	mise_panel.bind_ui(ui, self, undo_redo, func():
		var env := access.get_environment(editor_interface)
		if env == null:
			return null
		return inventory_panel._resolve_item_node_from_selection(env)
	)
	mise_panel.apply_editor_selection = func(target: Node, is_vis: bool, is_loc: bool):
		selection.apply_editor_selection_for_state(target, is_vis, is_loc)
	mise_panel.state_changed.connect(func():
		_do_ui_refresh()
		_do_env_refresh()
	)

	selection.bind(editor_interface, access, inventory_panel, mise_panel, hooks)
	selection.ui_refresh_requested.connect(_do_ui_refresh)

	database_panel.bind(
		ui, self, editor_interface,
		access, remote, catalog, busy,
		scene_setup, events_panel, inst, dl
	)
	database_panel.wire_ui()
	database_panel.ui_refresh_requested.connect(_do_ui_refresh)
	database_panel.env_refresh_requested.connect(_do_env_refresh)
	database_panel.status_changed.connect(func(text: String):
		if ui != null and ui.status_bar != null:
			ui.status_bar.text = text
	)
	busy.changed.connect(_do_ui_refresh)

	ui.components_list.item_selected.connect(selection.on_list_item_selected)

	ui.global_omeka_url.text = access.load_global_default_url(editor_interface)
	access.apply_global_url_to_current_scene(editor_interface, ui.global_omeka_url.text)

	hooks.bind(editor_interface, undo_redo, access, self)
	hooks.selected_node_transformed.connect(mise_panel.on_selected_node_transformed)
	hooks.refresh_requested.connect(_do_env_refresh)
	hooks.editor_env_selection_changed.connect(selection.on_editor_selection_changed)

	inst.configure(
		editor_interface,
		access,
		scene_setup,
		TEMPLATE_ENV_SCENE,
		CuratorDatabasePanel.CURATED_SCENES_DIR
	)

	_do_ui_refresh()
	_do_env_refresh()

	var initial_env = access.get_environment(editor_interface)
	var has_initial_env = (initial_env != null)
	ui_builder.set_collapsible_state(ui.db_section_btn, ui.db_section_content, not has_initial_env)
	ui_builder.set_collapsible_state(ui.env_section_btn, ui.env_section_content, has_initial_env)

	call_deferred("_startup_deferred")


func _startup_deferred() -> void:
	# await database_panel.sync_dynamic_properties_on_startup()
	await database_panel.fetch_item_sets()
	await database_panel.fetch_environments()


func _process(_delta: float) -> void:
	_do_status_bar_refresh()
	var sr := access.edited_scene_root(editor_interface)
	var has_scene := (sr != null)

	if sr != _last_scene_root or has_scene != _had_scene:
		_last_scene_root = sr
		_had_scene = has_scene

		var env := access.get_environment(editor_interface)
		if env != null:
			ui_builder.set_collapsible_state(ui.db_section_btn, ui.db_section_content, false)
			ui_builder.set_collapsible_state(ui.env_section_btn, ui.env_section_content, true)
			database_panel.on_scene_changed(env)
			if not busy.is_busy:
				if not busy.has_error:
					if ui.status_bar.text.strip_edges() == "":
						ui.status_bar.text = "Completed"
				else:
					if ui.status_bar.text not in ["Connection Error", "Error"]:
						ui.status_bar.text = "Error"
		else:
			ui_builder.set_collapsible_state(ui.db_section_btn, ui.db_section_content, true)
			ui_builder.set_collapsible_state(ui.env_section_btn, ui.env_section_content, false)
			database_panel.on_scene_changed(null)

		selection.clear_all()
		_do_ui_refresh()
		_do_env_refresh()


func _do_env_refresh() -> void:
	if _env_refresh_pending:
		return
	_env_refresh_pending = true
	call_deferred("_flush_env_refresh")


func _flush_env_refresh() -> void:
	_env_refresh_pending = false
	_do_env_refresh_now()


func _do_env_refresh_now() -> void:
	var env := access.get_environment(editor_interface)
	if env == null:
		events_panel.refresh(null)
		return

	var snap := access.scan_environment(env)

	selection.is_syncing = true
	inventory_panel.set_snapshot(snap, env, editor_interface)
	var render_ok := inventory_panel.render_list()
	if not busy.is_busy:
		busy.set_error(not render_ok)
	selection.is_syncing = false

	hooks.bind_rename_watchers_from_snapshot(snap)
	events_panel.refresh(env)
	_do_ui_refresh()


func _do_ui_refresh() -> void:
	var env := access.get_environment(editor_interface)
	var has_valid_open_env := (env != null) and int(env.item_id) > 0
	var has_selection := ui.components_list != null and ui.components_list.get_selected() != null
	var can_inspect := has_valid_open_env and has_selection and not busy.is_busy and not busy.has_error
	var disable_inventory := busy.is_busy or not has_valid_open_env

	if not has_valid_open_env:
		inventory_panel.clear_ui()

	database_panel.refresh_controls(has_valid_open_env)

	if ui.components_list:
		ui.components_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if disable_inventory else Control.MOUSE_FILTER_STOP
		ui.components_list.modulate.a = 0.45 if disable_inventory else 1.0

	ui.env_section_content.mouse_filter = Control.MOUSE_FILTER_IGNORE if busy.is_busy else Control.MOUSE_FILTER_STOP
	ui.env_section_content.modulate.a = 0.65 if busy.is_busy else 1.0

	var target: Node = null
	var is_node_visible: bool = false
	var is_node_locked: bool = false
	var has_valid_target: bool = false
	if can_inspect:
		target = inventory_panel._resolve_item_node_from_selection(env)
		if target != null:
			has_valid_target = true
			is_node_visible = target.visible if "visible" in target else true
			is_node_locked = target.has_meta("_edit_lock_") and target.get_meta("_edit_lock_")
	mise_panel.sync_selection(
		target if has_valid_target else null,
		has_valid_target,
		is_node_visible,
		is_node_locked
	)


func _do_status_bar_refresh() -> void:
	if ui == null or ui.status_bar == null:
		return

	var raw := ui.status_bar.text.strip_edges()
	var normalized := raw
	var is_error := false

	if normalized == "":
		if ui.status_bar_panel != null:
			ui.status_bar_panel.visible = false
		return

	if normalized == "Completed":
		normalized = "Scene Successfully Loaded"
	elif normalized == "Error":
		normalized = "Operation Failed"
		is_error = true
	elif normalized == "Connection Error":
		normalized = "Connection Error During Operation"
		is_error = true
	elif normalized == "Elaborating...":
		normalized = "Elaborating..."

	if "Error" in normalized.to_lower():
		is_error = true

	if normalized != ui.status_bar.text:
		ui.status_bar.text = normalized
		if normalized == "Scene Successfully Loaded":
			_schedule_status_bar_clear()

	if ui.status_bar_panel != null:
		ui.status_bar_panel.visible = true

	if is_error:
		ui.status_bar.add_theme_color_override("font_color", Color(1.0, 0.78, 0.78))
	else:
		ui.status_bar.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))


func _schedule_status_bar_clear() -> void:
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(ui) or not is_instance_valid(ui.status_bar):
		return
	if ui.status_bar.text == "Scene Successfully Loaded":
		ui.status_bar.text = ""
		if is_instance_valid(ui.status_bar_panel):
			ui.status_bar_panel.visible = false
