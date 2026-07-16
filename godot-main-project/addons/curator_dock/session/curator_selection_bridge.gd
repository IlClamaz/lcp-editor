@tool
extends RefCounted
class_name CuratorSelectionBridge

## Keeps COMPONENTS list and editor 3D selection in sync (with suppress shields).

signal ui_refresh_requested

var editor_interface: EditorInterface
var access: CuratorSceneAccess
var inventory_ctrl: CuratorInventoryPanel
var mise_ctrl: CuratorMiseEnScenePanel
var hooks: CuratorEditorHooks

var is_syncing: bool = false


func bind(
	_editor_interface: EditorInterface,
	_access: CuratorSceneAccess,
	_inventory_ctrl: CuratorInventoryPanel,
	_mise_ctrl: CuratorMiseEnScenePanel,
	_hooks: CuratorEditorHooks
) -> void:
	editor_interface = _editor_interface
	access = _access
	inventory_ctrl = _inventory_ctrl
	mise_ctrl = _mise_ctrl
	hooks = _hooks


func on_list_item_selected() -> void:
	if is_syncing:
		return

	var env: LivingEnvironment = access.get_environment(editor_interface)
	inventory_ctrl.on_item_selected(env != null)
	ui_refresh_requested.emit()

	if env == null:
		return

	var node: Node = inventory_ctrl._resolve_item_node_from_selection(env)
	if node == null:
		return

	mise_ctrl.sync_transform_fields_from_node(node)

	var is_vis: bool = node.visible if "visible" in node else true
	var is_loc: bool = node.has_meta("_edit_lock_") and node.get_meta("_edit_lock_")

	is_syncing = true
	hooks.set_suppress_selection(true)
	var ed_sel := editor_interface.get_selection()
	if not is_vis or is_loc:
		ed_sel.clear()
	else:
		var current_sel: Array = ed_sel.get_selected_nodes()
		if current_sel.size() != 1 or current_sel[0] != node:
			ed_sel.clear()
			ed_sel.add_node(node)
	hooks.set_suppress_selection(false)
	is_syncing = false


func on_editor_selection_changed(n: Node) -> void:
	if inventory_ctrl == null or inventory_ctrl.components_list == null:
		return

	if n == null:
		var env: LivingEnvironment = access.get_environment(editor_interface)
		if env != null:
			var target: Node = inventory_ctrl._resolve_item_node_from_selection(env)
			if target != null:
				var is_vis: bool = target.visible if "visible" in target else true
				var is_loc: bool = target.has_meta("_edit_lock_") and target.get_meta("_edit_lock_")
				if not is_vis or is_loc:
					return

		is_syncing = true
		inventory_ctrl.on_clear_selection()
		inventory_ctrl.on_item_selected(access.get_environment(editor_interface) != null)
		mise_ctrl.sync_transform_fields_from_node(null)
		is_syncing = false
		ui_refresh_requested.emit()
		return

	mise_ctrl.sync_transform_fields_from_node(n)

	is_syncing = true
	hooks.set_suppress_selection(true)
	var found: bool = inventory_ctrl.select_by_instance_id(n.get_instance_id())
	if found:
		inventory_ctrl.on_item_selected(true)
	else:
		inventory_ctrl.on_clear_selection()
	hooks.set_suppress_selection(false)
	is_syncing = false
	ui_refresh_requested.emit()


func apply_editor_selection_for_state(target: Node, is_visible: bool, is_locked: bool) -> void:
	if editor_interface == null or target == null:
		return
	var ed_sel := editor_interface.get_selection()
	if not is_visible or is_locked:
		ed_sel.clear()
	else:
		ed_sel.clear()
		ed_sel.add_node(target)


func clear_all() -> void:
	if hooks != null:
		hooks.clear_editor_selection()
	if inventory_ctrl != null:
		inventory_ctrl.on_clear_selection()
	if mise_ctrl != null:
		mise_ctrl.sync_transform_fields_from_node(null)
