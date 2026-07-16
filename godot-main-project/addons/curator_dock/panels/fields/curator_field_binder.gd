@tool
extends RefCounted
class_name CuratorFieldBinder

## Builds Appearance / Behavior widgets from CuratorFieldSpec and binds undo-aware edits.

var appearance_block: VBoxContainer
var appearance_container: VBoxContainer
var behavior_block: VBoxContainer
var behavior_container: VBoxContainer
var undo_redo: EditorUndoRedoManager

var _registry := CuratorFieldRegistry.new()
var _syncing: bool = false
var _accent := Color(0.25, 0.45, 0.65)


func bind_ui(
	_appearance_block: VBoxContainer,
	_appearance_container: VBoxContainer,
	_behavior_block: VBoxContainer,
	_behavior_container: VBoxContainer
) -> void:
	appearance_block = _appearance_block
	appearance_container = _appearance_container
	behavior_block = _behavior_block
	behavior_container = _behavior_container


func set_undo_redo(ur: EditorUndoRedoManager) -> void:
	undo_redo = ur


func clear() -> void:
	_clear_container(appearance_container)
	_clear_container(behavior_container)
	if appearance_block != null:
		appearance_block.visible = false
	if behavior_block != null:
		behavior_block.visible = false


func refresh(target: Node, node_visible: bool) -> void:
	clear()
	if target == null or not node_visible:
		return

	var specs: Array[CuratorFieldSpec] = _registry.specs_for(target)
	var has_appearance := false
	var has_behavior := false

	for spec in specs:
		if spec.visible_if.is_valid() and not spec.visible_if.call(target):
			continue
		if not _target_has_property(target, spec.property):
			continue
		match spec.section:
			CuratorFieldSpec.Section.APPEARANCE:
				_add_field_row(appearance_container, target, spec)
				has_appearance = true
			CuratorFieldSpec.Section.BEHAVIOR:
				_add_field_row(behavior_container, target, spec)
				has_behavior = true

	if appearance_block != null:
		appearance_block.visible = has_appearance
	if behavior_block != null:
		behavior_block.visible = has_behavior


func _clear_container(container: Control) -> void:
	if container == null:
		return
	while container.get_child_count() > 0:
		var child := container.get_child(0)
		container.remove_child(child)
		child.free()


func _add_field_row(parent: Control, target: Node, spec: CuratorFieldSpec) -> void:
	match spec.ui:
		CuratorFieldSpec.UiKind.BOOL:
			_add_bool(parent, target, spec)
		CuratorFieldSpec.UiKind.FLOAT:
			_add_float(parent, target, spec)
		CuratorFieldSpec.UiKind.INT:
			_add_int(parent, target, spec)
		CuratorFieldSpec.UiKind.STRING:
			_add_string(parent, target, spec)
		CuratorFieldSpec.UiKind.ENUM:
			_add_enum(parent, target, spec)
		CuratorFieldSpec.UiKind.VECTOR2:
			_add_vector2(parent, target, spec)


func _add_bool(parent: Control, target: Node, spec: CuratorFieldSpec) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = spec.label + ":"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var cb := CheckBox.new()
	cb.button_pressed = bool(target.get(spec.property))
	cb.toggled.connect(func(v: bool): _commit_property(target, spec.property, v, "Change %s" % spec.label))
	row.add_child(cb)
	parent.add_child(row)


func _add_float(parent: Control, target: Node, spec: CuratorFieldSpec) -> void:
	var wrap := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = spec.label + ":"
	wrap.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = spec.min_value
	spin.max_value = spec.max_value
	spin.step = spec.step
	spin.suffix = spec.suffix
	spin.custom_minimum_size = Vector2(70, 0)
	spin.value = float(target.get(spec.property))

	if spec.use_slider:
		var hbox := HBoxContainer.new()
		var slider := HSlider.new()
		slider.min_value = spec.min_value
		slider.max_value = spec.max_value
		slider.step = spec.step
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value = spin.value
		var slider_style := StyleBoxFlat.new()
		slider_style.bg_color = _accent
		slider_style.corner_radius_top_left = 4
		slider_style.corner_radius_top_right = 4
		slider_style.corner_radius_bottom_left = 4
		slider_style.corner_radius_bottom_right = 4
		slider.add_theme_stylebox_override("grabber_area", slider_style)
		slider.add_theme_stylebox_override("grabber_area_highlight", slider_style)
		slider.value_changed.connect(func(v: float):
			if not is_equal_approx(spin.value, v):
				spin.value = v
		)
		spin.value_changed.connect(func(v: float):
			if not is_equal_approx(slider.value, v):
				slider.value = v
			_on_numeric_changed(target, spec.property, v, "Change %s" % spec.label)
		)
		hbox.add_child(slider)
		hbox.add_child(spin)
		wrap.add_child(hbox)
	else:
		spin.value_changed.connect(func(v: float):
			_on_numeric_changed(target, spec.property, v, "Change %s" % spec.label)
		)
		wrap.add_child(spin)

	parent.add_child(wrap)


func _add_int(parent: Control, target: Node, spec: CuratorFieldSpec) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = spec.label + ":"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = spec.min_value
	spin.max_value = spec.max_value
	spin.step = maxf(spec.step, 1.0)
	spin.rounded = true
	spin.value = float(int(target.get(spec.property)))
	spin.value_changed.connect(func(v: float):
		_on_numeric_changed(target, spec.property, int(v), "Change %s" % spec.label)
	)
	row.add_child(spin)
	parent.add_child(row)


func _add_string(parent: Control, target: Node, spec: CuratorFieldSpec) -> void:
	var wrap := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = spec.label + ":"
	wrap.add_child(lbl)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = str(target.get(spec.property))
	edit.text_submitted.connect(func(t: String):
		_commit_property(target, spec.property, t, "Change %s" % spec.label)
	)
	edit.focus_exited.connect(func():
		_commit_property(target, spec.property, edit.text, "Change %s" % spec.label)
	)
	wrap.add_child(edit)
	parent.add_child(wrap)


func _add_enum(parent: Control, target: Node, spec: CuratorFieldSpec) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = spec.label + ":"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(spec.enum_keys.size()):
		opt.add_item(String(spec.enum_keys[i]).replace("ATTENUATION_", "").capitalize(), i)
	var current: int = int(target.get(spec.property))
	if current >= 0 and current < spec.enum_keys.size():
		opt.select(current)
	opt.item_selected.connect(func(idx: int):
		_commit_property(target, spec.property, idx, "Change %s" % spec.label)
	)
	row.add_child(opt)
	parent.add_child(row)


func _add_vector2(parent: Control, target: Node, spec: CuratorFieldSpec) -> void:
	var wrap := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = spec.label + ":"
	wrap.add_child(lbl)
	var current: Vector2 = target.get(spec.property) as Vector2
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var spin_x := _make_axis_spin("X", current.x, spec)
	var spin_y := _make_axis_spin("Y", current.y, spec)
	var apply_xy := func():
		if _syncing:
			return
		var next := Vector2(spin_x.value, spin_y.value)
		_commit_property(target, spec.property, next, "Change %s" % spec.label)
	spin_x.value_changed.connect(func(_v): apply_xy.call())
	spin_y.value_changed.connect(func(_v): apply_xy.call())
	row.add_child(spin_x)
	row.add_child(spin_y)
	wrap.add_child(row)
	parent.add_child(wrap)


func _make_axis_spin(axis: String, value: float, spec: CuratorFieldSpec) -> SpinBox:
	var spin := SpinBox.new()
	spin.prefix = axis + " "
	spin.min_value = spec.min_value
	spin.max_value = spec.max_value
	spin.step = spec.step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _on_numeric_changed(target: Node, property: String, new_val: Variant, action_name: String) -> void:
	if _syncing:
		return
	_commit_property(target, property, new_val, action_name)


func _commit_property(target: Node, property: String, new_val: Variant, action_name: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _syncing:
		return
	var old_val: Variant = target.get(property)
	if typeof(old_val) == typeof(new_val) and old_val == new_val:
		return
	# Float compare
	if typeof(old_val) == TYPE_FLOAT and typeof(new_val) == TYPE_FLOAT:
		if is_equal_approx(float(old_val), float(new_val)):
			return

	if undo_redo != null:
		undo_redo.create_action(action_name)
		undo_redo.add_do_property(target, property, new_val)
		undo_redo.add_undo_property(target, property, old_val)
		undo_redo.commit_action()
	else:
		target.set(property, new_val)

	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _target_has_property(target: Object, property: String) -> bool:
	if target == null or property.is_empty():
		return false
	for p in target.get_property_list():
		if str(p.get("name", "")) == property:
			return true
	return false
