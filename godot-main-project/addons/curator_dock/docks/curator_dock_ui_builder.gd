@tool
extends RefCounted
class_name CuratorDockUIBuilder

# Il Dock accede solo via ui.<campo>
class CuratorDockUI:
	var status_bar: Label
	var status_bar_panel: PanelContainer

	# Sezioni collapsable
	var db_section_btn: Button
	var db_section_content: VBoxContainer
	var env_section_btn: Button
	var env_section_content: VBoxContainer
	var env_section_split: HSplitContainer

	var global_omeka_url: LineEdit

	# Envs
	var env_list: OptionButton
	var fetch_env_btn: Button
	
	# Scenes
	var scene_list: OptionButton
	var scene_fetch_btn: Button
	var download_btn: Button

	# List - COMPONENTS
	var components_list: Tree

	# Right panel - LAYOUT
	var preview: TextureRect
	# State
	var visibility_cb: Button
	var lock_cb: Button
	var face_vis_cb: Button
	# Position
	var reset_pos_btn: Button
	var pos_x: SpinBox
	var pos_y: SpinBox
	var pos_z: SpinBox
	# Rotation
	var reset_rot_btn: Button
	var rot_x: SpinBox
	var rot_y: SpinBox
	var rot_z: SpinBox
	# Scale
	var reset_scale_btn: Button
	var scale_x: SpinBox
	var scale_y: SpinBox
	var scale_z: SpinBox

	# Restore / Save
	var restore_components_btn: Button
	var save_btn: Button

	# Old
	var save_pwd_edit: LineEdit



func build(parent: Control) -> CuratorDockUI:
	var ui := CuratorDockUI.new()

	# --- STILI PER I TITOLI E COLORI ---
	var header_settings = LabelSettings.new()
	header_settings.font_color = Color(0.70, 0.80, 0.85)
	header_settings.font_size = parent.get_theme_default_font_size() + 2
	header_settings.outline_size = 2
	header_settings.outline_color = Color(0, 0, 0, 0.4)
	header_settings.font = parent.get_theme_font("bold", "EditorFonts")

	var color_cta = Color(0.22, 0.42, 0.60)
	var color_action = Color(0.24, 0.25, 0.27)
	var color_button = Color(0.25, 0.45, 0.65)
	var color_x = Color(0.96, 0.20, 0.32) # Rosso (X) - Hex: #f53351
	var color_y = Color(0.53, 0.84, 0.01) # Verde (Y) - Hex: #87d602
	var color_z = Color(0.16, 0.55, 0.96) # Blu (Z) - Hex: #288cf5

	# ============================================================
	# STATUS BAR GLOBALE (Sempre visibile in cima al Dock)
	# ============================================================
	ui.status_bar_panel = PanelContainer.new()
	ui.status_bar_panel.visible = false # Sarà gestita dal Controller
	ui.status_bar_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color(0.15, 0.25, 0.35, 0.95) # Leggermente azzurrata per spiccare
	status_style.corner_radius_top_left = 6
	status_style.corner_radius_top_right = 6
	status_style.corner_radius_bottom_left = 6
	status_style.corner_radius_bottom_right = 6
	status_style.content_margin_left = 10
	status_style.content_margin_right = 10
	status_style.content_margin_top = 8
	status_style.content_margin_bottom = 8
	ui.status_bar_panel.add_theme_stylebox_override("panel", status_style)
	parent.add_child(ui.status_bar_panel) # <-- Agganciata alla radice!

	ui.status_bar = Label.new()
	ui.status_bar.text = ""
	ui.status_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER # Centrata è più elegante
	ui.status_bar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.status_bar.add_theme_font_override("font", parent.get_theme_font("bold", "EditorFonts"))
	ui.status_bar_panel.add_child(ui.status_bar)
	
	# Un piccolo spazio prima della prima sezione
	parent.add_child(HSeparator.new())

	# ------------------------------------------------------------
	# SEZIONE 1: DATABASE (Collassabile)
	# ------------------------------------------------------------
	ui.db_section_content = VBoxContainer.new()
	ui.db_section_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.db_section_btn = _create_collapsible_section(parent, "DATABASE", ui.db_section_content, color_action)

	var grid := GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("v_separation", 6)
	ui.db_section_content.add_child(grid)

	# DB URL
	var url_lbl := Label.new()
	url_lbl.text = "Database URL:"
	grid.add_child(url_lbl)

	ui.global_omeka_url = LineEdit.new()
	ui.global_omeka_url.text = "omekadev.livingculture.it"
	ui.global_omeka_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ui.global_omeka_url)

	# ENVs LIST
	var env_lbl := Label.new()
	env_lbl.text = "Environment:"
	grid.add_child(env_lbl)

	var env_hbox := HBoxContainer.new()
	env_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(env_hbox)

	ui.env_list = OptionButton.new()
	ui.env_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.env_list.add_item("Insert URL and update...", 0)
	env_hbox.add_child(ui.env_list)

	ui.fetch_env_btn = Button.new()
	ui.fetch_env_btn.text = "Update List"
	_apply_button_style(ui.fetch_env_btn, color_button)
	env_hbox.add_child(ui.fetch_env_btn)

	# SCENES LIST
	var scenes_lbl := Label.new()
	scenes_lbl.text = "Scenes:"
	grid.add_child(scenes_lbl)

	var list_row = HBoxContainer.new()
	list_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(list_row)
	
	ui.scene_list = OptionButton.new()
	ui.scene_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.scene_list.add_item("No scenes found", 0)
	ui.scene_list.set_item_disabled(0, true)
	list_row.add_child(ui.scene_list)
	
	ui.scene_fetch_btn = Button.new()
	ui.scene_fetch_btn.text = "Update List"
	_apply_button_style(ui.scene_fetch_btn, color_button)
	list_row.add_child(ui.scene_fetch_btn)

	# --- OLD ---
	var pwd_hbox = HBoxContainer.new()
	var pwd_lbl = Label.new()
	pwd_lbl.text = "Pwd:"
	# pwd_hbox.add_child(pwd_lbl)
	
	ui.save_pwd_edit = LineEdit.new()
	ui.save_pwd_edit.secret = true
	ui.save_pwd_edit.placeholder_text = "Da richiedere..."
	ui.save_pwd_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pwd_hbox.add_child(ui.save_pwd_edit)
	# grid.add_child(pwd_hbox)

	# DOWNLOAD / CREATE
	ui.download_btn = Button.new()
	ui.download_btn.text = "DOWNLOAD"
	ui.download_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.download_btn.custom_minimum_size = Vector2(0, 26)
	_apply_button_style(ui.download_btn, color_button, 13)
	grid.add_child(ui.download_btn)
	
	# ------------------------------------------------------------
	# SEZIONE 2: ENVIRONMENT
	# ------------------------------------------------------------
	parent.add_child(HSeparator.new())
	
	ui.env_section_content = VBoxContainer.new()
	ui.env_section_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	ui.env_section_btn = _create_collapsible_section(parent, "ENVIRONMENT", ui.env_section_content, color_action)

	# --- SPLIT  ---
	var split := HSplitContainer.new()
	ui.env_section_split = split
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 400)
	ui.env_section_content.add_child(split)

	# ==========================================
	# PARTE SINISTRA: TREE (COMPONENTS) + FOOTER
	# ==========================================
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_vbox)

	# Header: COMPONENTS
	var header_comp = PanelContainer.new()
	var style_comp_h = StyleBoxFlat.new()
	style_comp_h.bg_color = Color(0.18, 0.20, 0.23)
	style_comp_h.border_width_top = 1
	style_comp_h.border_width_bottom = 1
	style_comp_h.border_width_left = 1
	style_comp_h.border_width_right = 1
	style_comp_h.border_color = Color(0.4, 0.45, 0.5)
	style_comp_h.corner_radius_top_left = 4
	style_comp_h.corner_radius_top_right = 4
	style_comp_h.corner_radius_bottom_left = 4
	style_comp_h.corner_radius_bottom_right = 4
	header_comp.add_theme_stylebox_override("panel", style_comp_h)
	
	var lbl_comp = Label.new()
	lbl_comp.text = "COMPONENTS"
	lbl_comp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_comp.add_theme_font_override("font", parent.get_theme_font("bold", "EditorFonts"))
	header_comp.add_child(lbl_comp)
	left_vbox.add_child(header_comp)

	# Tree (3 Colonne) - Questa espandendosi spinge il bottone in basso
	ui.components_list = Tree.new()
	ui.components_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.components_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.components_list.columns = 3
	ui.components_list.hide_root = true
	ui.components_list.select_mode = Tree.SELECT_ROW
	
	ui.components_list.set_column_expand(0, true)
	ui.components_list.set_column_clip_content(0, true)
	ui.components_list.set_column_expand(1, false)
	ui.components_list.set_column_custom_minimum_width(1, 32)
	ui.components_list.set_column_expand(2, false)
	ui.components_list.set_column_custom_minimum_width(2, 32)
	left_vbox.add_child(ui.components_list)

	# --- FOOTER SINISTRO (Sempre allineato alla colonna sx) ---
	left_vbox.add_child(HSeparator.new())
	
	ui.restore_components_btn = Button.new()
	ui.restore_components_btn.text = "RESTORE SAVED COMPONENTS"
	ui.restore_components_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.restore_components_btn.custom_minimum_size = Vector2(0, 32) # Leggermente alzato per combaciare col vecchio box
	_apply_button_style(ui.restore_components_btn, color_button, 13) 
	left_vbox.add_child(ui.restore_components_btn)


	# ==========================================
	# PARTE DESTRA: INSPECTOR (LAYOUT) + FOOTER
	# ==========================================
	var right_vbox := VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(240, 0)
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_vbox)

	# Header: LAYOUT
	var header_lay = PanelContainer.new()
	var style_lay_h = style_comp_h.duplicate()
	header_lay.add_theme_stylebox_override("panel", style_lay_h)
	
	var lbl_lay = Label.new()
	lbl_lay.text = "LAYOUT"
	lbl_lay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_lay.add_theme_font_override("font", parent.get_theme_font("bold", "EditorFonts"))
	header_lay.add_child(lbl_lay)
	right_vbox.add_child(header_lay)

	# Contenuto Inspector
	var prev_label := Label.new()
	prev_label.text = "Thumbnail"
	right_vbox.add_child(prev_label)
	
	ui.preview = TextureRect.new()
	ui.preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	ui.preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ui.preview.custom_minimum_size = Vector2(150, 150)
	right_vbox.add_child(ui.preview)
	
	right_vbox.add_child(HSeparator.new())

	# --- STATE (Visibilità/Blocco/Face) ---
	var state_title := Label.new()
	state_title.text = "State"
	right_vbox.add_child(state_title)
	
	var state_hbox := HBoxContainer.new()
	state_hbox.add_theme_constant_override("separation", 10) # Un po' di respiro tra i bottoni
	
	# Visibility Button
	ui.visibility_cb = _create_icon_button(parent, "GuiVisibilityVisible", "Toggle Visibility", color_button)
	ui.visibility_cb.toggle_mode = true
	ui.visibility_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_hbox.add_child(ui.visibility_cb)
	
	# Lock Button
	ui.lock_cb = _create_icon_button(parent, "Lock", "Toggle Lock", color_button)
	ui.lock_cb.toggle_mode = true
	ui.lock_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_hbox.add_child(ui.lock_cb)
	
	# Face Visibility Button
	ui.face_vis_cb = _create_icon_button(parent, "MeshTexture", "Toggle Face Visibility", color_button)
	ui.face_vis_cb.toggle_mode = true
	ui.face_vis_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_hbox.add_child(ui.face_vis_cb)

	right_vbox.add_child(state_hbox)
	right_vbox.add_child(HSeparator.new())

	var transform_title := Label.new()
	transform_title.text = "Transform"
	right_vbox.add_child(transform_title)

	# POSITIONING
	var pos_content := VBoxContainer.new()
	pos_content.visible = false
	
	ui.reset_pos_btn = _create_icon_button(parent, "Reload", "Reset Position", color_button)
	_create_collapsible_section_with_btn(right_vbox, "Position", pos_content, color_action, ui.reset_pos_btn)
	
	ui.pos_x = _create_axis_spinbox(pos_content, "X:", -9999, 9999, 0.1, color_x)
	ui.pos_y = _create_axis_spinbox(pos_content, "Y:", -9999, 9999, 0.1, color_y)
	ui.pos_z = _create_axis_spinbox(pos_content, "Z:", -9999, 9999, 0.1, color_z)

	# ROTATION
	var rot_content := VBoxContainer.new()
	rot_content.visible = false
	
	ui.reset_rot_btn = _create_icon_button(parent, "Reload", "Reset Rotation", color_button)
	_create_collapsible_section_with_btn(right_vbox, "Rotation", rot_content, color_action, ui.reset_rot_btn)
	
	ui.rot_x = _create_axis_spinbox(rot_content, "X:", -360, 360, 0.1, color_x, "°")
	ui.rot_y = _create_axis_spinbox(rot_content, "Y:", -360, 360, 0.1, color_y, "°")
	ui.rot_z = _create_axis_spinbox(rot_content, "Z:", -360, 360, 0.1, color_z, "°")


	# SCALING
	var scale_content := VBoxContainer.new()
	scale_content.visible = false
	
	ui.reset_scale_btn = _create_icon_button(parent, "Reload", "Reset Scale", color_button)
	_create_collapsible_section_with_btn(right_vbox, "Scale", scale_content, color_action, ui.reset_scale_btn)

	ui.scale_x = _create_axis_spinbox(scale_content, "Width (X):", 0.01, 9999, 0.01, color_x)
	ui.scale_y = _create_axis_spinbox(scale_content, "Height (Y):", 0.01, 9999, 0.01, color_y)
	ui.scale_z = _create_axis_spinbox(scale_content, "Depth (Z):", 0.01, 9999, 0.01, color_z)

	right_vbox.add_child(HSeparator.new())

	# --- SPACER: Spinge il bottone SAVE verso il basso ---
	var right_spacer = Control.new()
	right_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(right_spacer)

	# --- FOOTER DESTRO (Sempre allineato alla colonna dx) ---
	right_vbox.add_child(HSeparator.new())
	
	ui.save_btn = Button.new()
	ui.save_btn.text = "SAVE..."
	ui.save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.save_btn.custom_minimum_size = Vector2(0, 32)
	_apply_button_style(ui.save_btn, color_button, 13) 
	right_vbox.add_child(ui.save_btn)

	return ui


# ==============================================================================
# HELPERS, COLLAPSABLE and BUTTON STYLE
# ==============================================================================

# Helper per creare una sezione collassabile semplice
func _create_collapsible_section(parent: Control, title: String, content_container: Control, color: Color) -> Button:
	var btn = Button.new()
	btn.text = "▶ " + title # <-- Inserisce automaticamente la freccia "chiusa"
	btn.add_theme_font_override("font", parent.get_theme_font("bold", "EditorFonts"))

	var style = StyleBoxFlat.new()
	style.bg_color = color.darkened(0.2)
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.content_margin_left = 10
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)

	btn.pressed.connect(func():
		var is_visible = content_container.visible
		set_collapsible_state(btn, content_container, not is_visible)
	)

	parent.add_child(btn)
	parent.add_child(content_container)
	return btn

# Helper per creare una sezione collassabile con un bottone extra affiancato
func _create_collapsible_section_with_btn(parent: Control, title: String, content_container: Control, color: Color, extra_btn: Button) -> Button:
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var btn = Button.new()
	btn.text = "▶ " + title 
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
	btn.add_theme_font_override("font", parent.get_theme_font("bold", "EditorFonts"))

	var style = StyleBoxFlat.new()
	style.bg_color = color.darkened(0.2)
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.content_margin_left = 10
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)

	btn.pressed.connect(func():
		var is_visible = content_container.visible
		set_collapsible_state(btn, content_container, not is_visible)
	)

	hbox.add_child(btn)
	if extra_btn != null:
		extra_btn.size_flags_vertical = Control.SIZE_FILL 
		hbox.add_child(extra_btn)

	parent.add_child(hbox)
	parent.add_child(content_container)
	return btn

# La logica di scambio dei nuovi simboli
func set_collapsible_state(btn: Button, content_container: Control, is_open: bool) -> void:
	if btn == null or content_container == null:
		return
	content_container.visible = is_open
	
	var raw_title := btn.text
	# Riconosce i nuovi simboli e li toglie prima di aggiornarli
	if raw_title.begins_with("▼ ") or raw_title.begins_with("▶ "):
		raw_title = raw_title.substr(2)
		
	# Riapplica il simbolo corretto in base allo stato
	btn.text = ("▼ " if is_open else "▶ ") + raw_title


func _apply_button_style(btn: Button, bg_color: Color, padding_v: int = 4) -> void:
	var editor_font_bold = btn.get_theme_font("bold", "EditorFonts")
	btn.add_theme_font_override("font", editor_font_bold)

	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.corner_radius_bottom_right = 8
	style_normal.content_margin_top = padding_v
	style_normal.content_margin_bottom = padding_v
	style_normal.content_margin_left = 12
	style_normal.content_margin_right = 12

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.12)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.15)

	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.2, 0.2, 0.2, 0.4)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("disabled", style_disabled)

	var text_color = Color(0.9, 0.9, 0.9)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.7, 0.7, 0.7))
	btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

# Helper per generare gli SpinBox
# Helper per generare gli SpinBox con suffisso dinamico
func _create_axis_spinbox(parent: Control, label_text: String, min_val: float, max_val: float, step_val: float, text_color: Color = Color.WHITE, suffix_text: String = "m") -> SpinBox:
	var hbox := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(80, 0)
	lbl.add_theme_color_override("font_color", text_color)
	
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step_val
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.suffix = suffix_text
	
	hbox.add_child(lbl)
	hbox.add_child(spin)
	parent.add_child(hbox)
	return spin

# Helper per creare velocemente un pulsante con un'icona dell'Editor
func _create_icon_button(parent: Control, icon_name: String, tooltip: String, bg_color: Color) -> Button:
	var btn = Button.new()
	btn.tooltip_text = tooltip
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	if Engine.is_editor_hint():
		var theme = EditorInterface.get_editor_theme() 
		if theme.has_icon(icon_name, "EditorIcons"):
			btn.icon = theme.get_icon(icon_name, "EditorIcons") 
	
	btn.add_theme_color_override("icon_normal_color", Color.WHITE)
	btn.add_theme_color_override("icon_pressed_color", Color.WHITE)
	btn.add_theme_color_override("icon_hover_color", Color.WHITE)
	btn.add_theme_color_override("icon_hover_pressed_color", Color.WHITE)
	
	_apply_button_style(btn, bg_color, 4)
	return btn
