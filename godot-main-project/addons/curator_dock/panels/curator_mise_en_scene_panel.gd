@tool
extends RefCounted
class_name CuratorMiseEnScenePanel

## Right column: Thumbnail / State / typed Layout + Appearance / Behavior.

signal state_changed
## Callable(target: Node, is_visible: bool, is_locked: bool) — update editor gizmo selection.
var apply_editor_selection: Callable = Callable()

var ui: CuratorDockUIBuilder.CuratorDockUI
var host: Control
var undo_redo: EditorUndoRedoManager
## Callable() -> Node — resolves the currently selected Living* item.
var resolve_target: Callable = Callable()

var field_binder := CuratorFieldBinder.new()
var field_registry := CuratorFieldRegistry.new()

var _suppress_transform_apply: bool = false


func bind_ui(
	_ui: CuratorDockUIBuilder.CuratorDockUI,
	_host: Control,
	_undo_redo: EditorUndoRedoManager,
	_resolve_target: Callable = Callable()
) -> void:
	ui = _ui
	host = _host
	undo_redo = _undo_redo
	resolve_target = _resolve_target
	field_binder.bind_ui(
		ui.appearance_block,
		ui.appearance_container,
		ui.behavior_block,
		ui.behavior_container
	)
	field_binder.set_undo_redo(undo_redo)
	_wire_layout_controls()
	_wire_state_controls()


func clear() -> void:
	if ui != null:
		if ui.thumbnail_block != null:
			ui.thumbnail_block.visible = false
		if ui.state_block != null:
			ui.state_block.visible = false
		if ui.layout_block != null:
			ui.layout_block.visible = false
	_set_layout_sections_visible(false, false, false, false, false)
	field_binder.clear()


## Sync header + layout + typed fields for the selected Living* node (or null).
func sync_selection(target: Node, has_valid_target: bool, is_node_visible: bool, is_node_locked: bool) -> void:
	if ui == null:
		return

	if not has_valid_target or target == null:
		_reset_header()
		field_binder.clear()
		return

	if ui.thumbnail_block != null:
		ui.thumbnail_block.visible = true
	if ui.selection_name_lbl != null:
		ui.selection_name_lbl.text = str(target.name)
	if ui.selection_type_lbl != null:
		ui.selection_type_lbl.text = _friendly_type_label(target)
	if ui.state_block != null:
		ui.state_block.visible = true

	_sync_state_buttons(is_node_visible, is_node_locked)

	var can_edit_transforms: bool = is_node_visible and not is_node_locked
	if ui.layout_block != null:
		ui.layout_block.visible = can_edit_transforms
	_set_transform_editable(can_edit_transforms)
	_sync_layout_sections(target if can_edit_transforms else null)

	field_binder.refresh(target, is_node_visible)


# ==============================================================================
# Layout — spinbox sync (selection / gizmo)
# ==============================================================================

func sync_transform_fields_from_node(n: Node) -> void:
	if ui == null:
		return

	if n == null or not (n is Node3D):
		_suppress_transform_apply = true
		_set_spin_xyz(ui.pos_x, ui.pos_y, ui.pos_z, Vector3.ZERO)
		_set_spin_xyz(ui.rot_x, ui.rot_y, ui.rot_z, Vector3.ZERO)
		_set_spin_xyz(ui.scale_x, ui.scale_y, ui.scale_z, Vector3.ZERO)
		_set_spin_xyz(ui.visit_pos_x, ui.visit_pos_y, ui.visit_pos_z, Vector3.ZERO)
		_set_spin_xyz(ui.visit_rot_x, ui.visit_rot_y, ui.visit_rot_z, Vector3.ZERO)
		_suppress_transform_apply = false
		return

	var n3d := n as Node3D
	var base_size: Vector3 = _get_item_base_size(n3d)
	var current_size_in_meters: Vector3 = base_size * n3d.scale

	_suppress_transform_apply = true
	_set_spin_xyz(ui.pos_x, ui.pos_y, ui.pos_z, n3d.global_position)
	_set_spin_xyz(ui.rot_x, ui.rot_y, ui.rot_z, n3d.rotation_degrees)
	_set_spin_xyz(ui.scale_x, ui.scale_y, ui.scale_z, current_size_in_meters)
	if n3d is LivingVisitableObject:
		var visitable := n3d as LivingVisitableObject
		_set_spin_xyz(ui.visit_pos_x, ui.visit_pos_y, ui.visit_pos_z, visitable.visit_position)
		_set_spin_xyz(ui.visit_rot_x, ui.visit_rot_y, ui.visit_rot_z, visitable.visit_rotation_degrees)
	else:
		_set_spin_xyz(ui.visit_pos_x, ui.visit_pos_y, ui.visit_pos_z, Vector3.ZERO)
		_set_spin_xyz(ui.visit_rot_x, ui.visit_rot_y, ui.visit_rot_z, Vector3.ZERO)
	_suppress_transform_apply = false


func on_selected_node_transformed(_node: Node3D, global_pos: Vector3, global_rot_deg: Vector3) -> void:
	if ui == null or _node == null:
		return

	_suppress_transform_apply = true

	if ui.pos_x and not ui.pos_x.has_focus():
		ui.pos_x.value = global_pos.x
	if ui.pos_y and not ui.pos_y.has_focus():
		ui.pos_y.value = global_pos.y
	if ui.pos_z and not ui.pos_z.has_focus():
		ui.pos_z.value = global_pos.z

	if ui.rot_x and not ui.rot_x.has_focus():
		ui.rot_x.value = global_rot_deg.x
	if ui.rot_y and not ui.rot_y.has_focus():
		ui.rot_y.value = global_rot_deg.y
	if ui.rot_z and not ui.rot_z.has_focus():
		ui.rot_z.value = global_rot_deg.z

	var base_size: Vector3 = _get_item_base_size(_node)
	var current_size_in_meters: Vector3 = base_size * _node.scale
	if ui.scale_x and not ui.scale_x.has_focus():
		ui.scale_x.value = current_size_in_meters.x
	if ui.scale_y and not ui.scale_y.has_focus():
		ui.scale_y.value = current_size_in_meters.y
	if ui.scale_z and not ui.scale_z.has_focus():
		ui.scale_z.value = current_size_in_meters.z

	_suppress_transform_apply = false


# ==============================================================================
# Header / State / Layout section visibility
# ==============================================================================

func _reset_header() -> void:
	if ui.thumbnail_block != null:
		ui.thumbnail_block.visible = false
	if ui.selection_name_lbl != null:
		ui.selection_name_lbl.text = ""
	if ui.selection_type_lbl != null:
		ui.selection_type_lbl.text = ""
	if ui.state_block != null:
		ui.state_block.visible = false
	if ui.layout_block != null:
		ui.layout_block.visible = false
	_set_transform_editable(false)
	_set_layout_sections_visible(false, false, false, false, false)

	if ui.visibility_cb != null:
		ui.visibility_cb.set_block_signals(true)
		ui.visibility_cb.button_pressed = false
		ui.visibility_cb.disabled = true
		if host != null:
			ui.visibility_cb.icon = host.get_theme_icon("GuiVisibilityVisible", "EditorIcons")
		ui.visibility_cb.set_block_signals(false)
	if ui.lock_cb != null:
		ui.lock_cb.set_block_signals(true)
		ui.lock_cb.button_pressed = false
		ui.lock_cb.disabled = true
		if host != null:
			ui.lock_cb.icon = host.get_theme_icon("Unlock", "EditorIcons")
		ui.lock_cb.set_block_signals(false)


func _sync_state_buttons(is_node_visible: bool, is_node_locked: bool) -> void:
	if ui.visibility_cb == null or ui.lock_cb == null or host == null:
		return
	ui.visibility_cb.set_block_signals(true)
	ui.lock_cb.set_block_signals(true)
	ui.visibility_cb.button_pressed = is_node_visible
	ui.lock_cb.button_pressed = is_node_locked
	var eye_icon: String = "GuiVisibilityVisible" if is_node_visible else "GuiVisibilityHidden"
	ui.visibility_cb.icon = host.get_theme_icon(eye_icon, "EditorIcons")
	var lock_icon: String = "Lock" if is_node_locked else "Unlock"
	ui.lock_cb.icon = host.get_theme_icon(lock_icon, "EditorIcons")
	ui.visibility_cb.set_block_signals(false)
	ui.lock_cb.set_block_signals(false)
	ui.visibility_cb.disabled = false
	ui.lock_cb.disabled = not is_node_visible


func _sync_layout_sections(target: Node) -> void:
	if target == null:
		_set_layout_sections_visible(false, false, false, false, false)
		return
	var vis: Dictionary = field_registry.layout_visibility(target)
	_set_layout_sections_visible(
		bool(vis.get("position", true)),
		bool(vis.get("rotation", true)),
		bool(vis.get("scale", true)),
		bool(vis.get("visit_position", false)),
		bool(vis.get("visit_rotation", false))
	)


func _set_layout_sections_visible(
	show_pos: bool,
	show_rot: bool,
	show_scale: bool,
	show_visit_pos: bool = false,
	show_visit_rot: bool = false
) -> void:
	if ui == null:
		return
	if ui.layout_pos_section != null:
		ui.layout_pos_section.visible = show_pos
	if ui.layout_rot_section != null:
		ui.layout_rot_section.visible = show_rot
	if ui.layout_scale_section != null:
		ui.layout_scale_section.visible = show_scale
	if ui.layout_visit_pos_section != null:
		ui.layout_visit_pos_section.visible = show_visit_pos
	if ui.layout_visit_rot_section != null:
		ui.layout_visit_rot_section.visible = show_visit_rot


func _set_transform_editable(can_edit: bool) -> void:
	if ui == null:
		return
	if ui.reset_pos_btn: ui.reset_pos_btn.disabled = not can_edit
	if ui.reset_rot_btn: ui.reset_rot_btn.disabled = not can_edit
	if ui.reset_scale_btn: ui.reset_scale_btn.disabled = not can_edit
	if ui.pos_x: ui.pos_x.editable = can_edit
	if ui.pos_y: ui.pos_y.editable = can_edit
	if ui.pos_z: ui.pos_z.editable = can_edit
	if ui.rot_x: ui.rot_x.editable = can_edit
	if ui.rot_y: ui.rot_y.editable = can_edit
	if ui.rot_z: ui.rot_z.editable = can_edit
	if ui.scale_x: ui.scale_x.editable = can_edit
	if ui.scale_y: ui.scale_y.editable = can_edit
	if ui.scale_z: ui.scale_z.editable = can_edit
	if ui.reset_visit_pos_btn: ui.reset_visit_pos_btn.disabled = not can_edit
	if ui.reset_visit_rot_btn: ui.reset_visit_rot_btn.disabled = not can_edit
	if ui.visit_pos_x: ui.visit_pos_x.editable = can_edit
	if ui.visit_pos_y: ui.visit_pos_y.editable = can_edit
	if ui.visit_pos_z: ui.visit_pos_z.editable = can_edit
	if ui.visit_rot_x: ui.visit_rot_x.editable = can_edit
	if ui.visit_rot_y: ui.visit_rot_y.editable = can_edit
	if ui.visit_rot_z: ui.visit_rot_z.editable = can_edit


# ==============================================================================
# Layout — wire + apply
# ==============================================================================

func _wire_layout_controls() -> void:
	if ui == null:
		return
	if ui.pos_x: ui.pos_x.value_changed.connect(_on_position_changed.unbind(1))
	if ui.pos_y: ui.pos_y.value_changed.connect(_on_position_changed.unbind(1))
	if ui.pos_z: ui.pos_z.value_changed.connect(_on_position_changed.unbind(1))

	if ui.rot_x: ui.rot_x.value_changed.connect(_on_rotation_changed.unbind(1))
	if ui.rot_y: ui.rot_y.value_changed.connect(_on_rotation_changed.unbind(1))
	if ui.rot_z: ui.rot_z.value_changed.connect(_on_rotation_changed.unbind(1))

	if ui.scale_x: ui.scale_x.value_changed.connect(_on_scale_changed.bind(Vector3.AXIS_X))
	if ui.scale_y: ui.scale_y.value_changed.connect(_on_scale_changed.bind(Vector3.AXIS_Y))
	if ui.scale_z: ui.scale_z.value_changed.connect(_on_scale_changed.bind(Vector3.AXIS_Z))

	if ui.reset_pos_btn: ui.reset_pos_btn.pressed.connect(_on_reset_position_pressed)
	if ui.reset_rot_btn: ui.reset_rot_btn.pressed.connect(_on_reset_rotation_pressed)
	if ui.reset_scale_btn: ui.reset_scale_btn.pressed.connect(_on_reset_scale_pressed)

	if ui.visit_pos_x: ui.visit_pos_x.value_changed.connect(_on_visit_position_changed.unbind(1))
	if ui.visit_pos_y: ui.visit_pos_y.value_changed.connect(_on_visit_position_changed.unbind(1))
	if ui.visit_pos_z: ui.visit_pos_z.value_changed.connect(_on_visit_position_changed.unbind(1))
	if ui.visit_rot_x: ui.visit_rot_x.value_changed.connect(_on_visit_rotation_changed.unbind(1))
	if ui.visit_rot_y: ui.visit_rot_y.value_changed.connect(_on_visit_rotation_changed.unbind(1))
	if ui.visit_rot_z: ui.visit_rot_z.value_changed.connect(_on_visit_rotation_changed.unbind(1))
	if ui.reset_visit_pos_btn: ui.reset_visit_pos_btn.pressed.connect(_on_reset_visit_position_pressed)
	if ui.reset_visit_rot_btn: ui.reset_visit_rot_btn.pressed.connect(_on_reset_visit_rotation_pressed)


func _wire_state_controls() -> void:
	if ui == null:
		return
	if ui.visibility_cb:
		ui.visibility_cb.toggled.connect(_on_visibility_toggled)
	if ui.lock_cb:
		ui.lock_cb.toggled.connect(_on_lock_toggled)


func _on_visibility_toggled(is_visible: bool) -> void:
	var target: Node = _resolve_any_target()
	if target == null:
		return
	if not (target is Node3D or target is CanvasItem):
		return

	if undo_redo != null:
		undo_redo.create_action("Toggle visibility")
		undo_redo.add_do_property(target, "visible", is_visible)
		undo_redo.add_undo_property(target, "visible", not is_visible)
		undo_redo.commit_action()
	else:
		target.visible = is_visible

	var is_loc: bool = target.has_meta("_edit_lock_") and target.get_meta("_edit_lock_")
	if apply_editor_selection.is_valid():
		apply_editor_selection.call(target, is_visible, is_loc)

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
	state_changed.emit()


func _on_lock_toggled(is_locked: bool) -> void:
	var target: Node = _resolve_any_target()
	if target == null:
		return

	if is_locked:
		target.set_meta("_edit_lock_", true)
	else:
		target.remove_meta("_edit_lock_")

	var is_vis: bool = target.visible if "visible" in target else true
	if apply_editor_selection.is_valid():
		apply_editor_selection.call(target, is_vis, is_locked)

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
	state_changed.emit()


func _resolve_any_target() -> Node:
	if not resolve_target.is_valid():
		return null
	var n: Variant = resolve_target.call()
	if n is Node:
		return n as Node
	return null


func _resolve_target_3d() -> Node3D:
	if not resolve_target.is_valid():
		return null
	var n: Variant = resolve_target.call()
	if n is Node3D:
		return n as Node3D
	return null


func _on_position_changed() -> void:
	if _suppress_transform_apply:
		return
	var target := _resolve_target_3d()
	if target == null:
		return

	var old_pos := target.global_position
	var new_pos := Vector3(ui.pos_x.value, ui.pos_y.value, ui.pos_z.value)

	if undo_redo != null:
		undo_redo.create_action("Change Position")
		undo_redo.add_do_property(target, "global_position", new_pos)
		undo_redo.add_undo_property(target, "global_position", old_pos)
		undo_redo.commit_action()
	else:
		target.global_position = new_pos


func _on_rotation_changed() -> void:
	if _suppress_transform_apply:
		return
	var target := _resolve_target_3d()
	if target == null:
		return

	var old_rot := target.rotation_degrees
	var new_rot := Vector3(ui.rot_x.value, ui.rot_y.value, ui.rot_z.value)

	if undo_redo != null:
		undo_redo.create_action("Change Rotation")
		undo_redo.add_do_property(target, "rotation_degrees", new_rot)
		undo_redo.add_undo_property(target, "rotation_degrees", old_rot)
		undo_redo.commit_action()
	else:
		target.rotation_degrees = new_rot


func _on_scale_changed(new_value: float, modified_axis: int) -> void:
	if _suppress_transform_apply:
		return
	var target := _resolve_target_3d()
	if target == null:
		return

	var base_size: Vector3 = _get_item_base_size(target)
	var base_val: float = base_size[modified_axis]
	if base_val <= 0.0001:
		return

	var old_scale := target.scale
	var axis_scale: float = new_value / base_val
	var new_scale := old_scale
	var uniform := not (target is LivingTargetObject)
	if uniform:
		new_scale = Vector3(axis_scale, axis_scale, axis_scale)
		var target_size: Vector3 = base_size * axis_scale
		_suppress_transform_apply = true
		if modified_axis != Vector3.AXIS_X and ui.scale_x:
			ui.scale_x.value = target_size.x
		if modified_axis != Vector3.AXIS_Y and ui.scale_y:
			ui.scale_y.value = target_size.y
		if modified_axis != Vector3.AXIS_Z and ui.scale_z:
			ui.scale_z.value = target_size.z
		_suppress_transform_apply = false
	else:
		new_scale[modified_axis] = axis_scale

	if undo_redo != null:
		undo_redo.create_action("Scale Object (Uniform)" if uniform else "Scale Object")
		undo_redo.add_do_property(target, "scale", new_scale)
		undo_redo.add_undo_property(target, "scale", old_scale)
		undo_redo.commit_action()
	else:
		target.scale = new_scale

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _on_reset_position_pressed() -> void:
	if _suppress_transform_apply:
		return
	var target := _resolve_target_3d()
	if target == null:
		return

	var old_pos := target.global_position
	var new_pos := Vector3.ZERO
	if old_pos.is_equal_approx(new_pos):
		return

	if undo_redo != null:
		undo_redo.create_action("Reset Position")
		undo_redo.add_do_property(target, "global_position", new_pos)
		undo_redo.add_undo_property(target, "global_position", old_pos)
		undo_redo.commit_action()
	else:
		target.global_position = new_pos

	sync_transform_fields_from_node(target)


func _on_reset_rotation_pressed() -> void:
	if _suppress_transform_apply:
		return
	var target := _resolve_target_3d()
	if target == null:
		return

	var old_rot := target.rotation_degrees
	var new_rot := Vector3.ZERO
	if old_rot.is_equal_approx(new_rot):
		return

	if undo_redo != null:
		undo_redo.create_action("Reset Rotation")
		undo_redo.add_do_property(target, "rotation_degrees", new_rot)
		undo_redo.add_undo_property(target, "rotation_degrees", old_rot)
		undo_redo.commit_action()
	else:
		target.rotation_degrees = new_rot

	sync_transform_fields_from_node(target)


func _on_reset_scale_pressed() -> void:
	if _suppress_transform_apply:
		return
	var target := _resolve_target_3d()
	if target == null:
		return

	var old_scale := target.scale
	var new_scale := Vector3.ONE
	if old_scale.is_equal_approx(new_scale):
		return

	if undo_redo != null:
		undo_redo.create_action("Reset Scale")
		undo_redo.add_do_property(target, "scale", new_scale)
		undo_redo.add_undo_property(target, "scale", old_scale)
		undo_redo.commit_action()
	else:
		target.scale = new_scale

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
	sync_transform_fields_from_node(target)


func _on_visit_position_changed() -> void:
	if _suppress_transform_apply:
		return
	var visitable := _resolve_visitable()
	if visitable == null:
		return

	var old_pos := visitable.visit_position
	var new_pos := Vector3(ui.visit_pos_x.value, ui.visit_pos_y.value, ui.visit_pos_z.value)

	if undo_redo != null:
		undo_redo.create_action("Change Visit Position")
		undo_redo.add_do_property(visitable, "visit_position", new_pos)
		undo_redo.add_undo_property(visitable, "visit_position", old_pos)
		undo_redo.commit_action()
	else:
		visitable.visit_position = new_pos

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _on_visit_rotation_changed() -> void:
	if _suppress_transform_apply:
		return
	var visitable := _resolve_visitable()
	if visitable == null:
		return

	var old_rot := visitable.visit_rotation_degrees
	var new_rot := Vector3(ui.visit_rot_x.value, ui.visit_rot_y.value, ui.visit_rot_z.value)

	if undo_redo != null:
		undo_redo.create_action("Change Visit Rotation")
		undo_redo.add_do_property(visitable, "visit_rotation_degrees", new_rot)
		undo_redo.add_undo_property(visitable, "visit_rotation_degrees", old_rot)
		undo_redo.commit_action()
	else:
		visitable.visit_rotation_degrees = new_rot

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _on_reset_visit_position_pressed() -> void:
	if _suppress_transform_apply:
		return
	var visitable := _resolve_visitable()
	if visitable == null:
		return

	var old_pos := visitable.visit_position
	var new_pos := Vector3.ZERO
	if old_pos.is_equal_approx(new_pos):
		return

	if undo_redo != null:
		undo_redo.create_action("Reset Visit Position")
		undo_redo.add_do_property(visitable, "visit_position", new_pos)
		undo_redo.add_undo_property(visitable, "visit_position", old_pos)
		undo_redo.commit_action()
	else:
		visitable.visit_position = new_pos

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
	sync_transform_fields_from_node(visitable)


func _on_reset_visit_rotation_pressed() -> void:
	if _suppress_transform_apply:
		return
	var visitable := _resolve_visitable()
	if visitable == null:
		return

	var old_rot := visitable.visit_rotation_degrees
	var new_rot := Vector3.ZERO
	if old_rot.is_equal_approx(new_rot):
		return

	if undo_redo != null:
		undo_redo.create_action("Reset Visit Rotation")
		undo_redo.add_do_property(visitable, "visit_rotation_degrees", new_rot)
		undo_redo.add_undo_property(visitable, "visit_rotation_degrees", old_rot)
		undo_redo.commit_action()
	else:
		visitable.visit_rotation_degrees = new_rot

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
	sync_transform_fields_from_node(visitable)


func _resolve_visitable() -> LivingVisitableObject:
	var n := _resolve_any_target()
	if n is LivingVisitableObject:
		return n as LivingVisitableObject
	return null


func _set_spin_xyz(sx: SpinBox, sy: SpinBox, sz: SpinBox, v: Vector3) -> void:
	if sx: sx.value = v.x
	if sy: sy.value = v.y
	if sz: sz.value = v.z


func _get_item_base_size(root: Node3D) -> Vector3:
	var aabb: AABB = LivingUtils.get_volume_aabb(root)
	if aabb.size.is_zero_approx():
		aabb = LivingUtils.get_node_aabb(root)
	if aabb.size.is_zero_approx():
		return Vector3.ONE
	return aabb.size


## LivingImageObject -> Image, Living3DModelAnimatedObject -> 3D Animated, LivingArea -> Area
func _friendly_type_label(target: Node) -> String:
	if target == null:
		return ""
	if target is LivingArea:
		return "Area"
	if target is LivingImageObject:
		return "Image"
	if target is LivingVideoObject:
		return "Video"
	if target is LivingSlideShowObject:
		return "Slideshow"
	if target is LivingVideo360Object:
		return "Video 360°"
	if target is LivingAudioObject:
		return "Audio"
	if target is Living3DModelAnimatedObject:
		return "3D Animated"
	if target is LivingTargetObject:
		return "Target"
	if target is Living3DModelObject:
		return "3D Model"
	if target is LivingCrowdObject:
		return "Crowd"
	if target is LivingStargateObject:
		return "Stargate"
	if target is LivingContainerModelObject:
		return "Container"
	if target is LivingFlatMediaObject:
		return "Flat Media"
	if target is LivingObject:
		return "Object"

	var script: Script = target.get_script() as Script
	if script != null:
		var gn: String = script.get_global_name()
		if gn.begins_with("Living") and gn.ends_with("Object"):
			return gn.substr(6, gn.length() - 12)
		if gn != "":
			return gn
	return target.get_class()
