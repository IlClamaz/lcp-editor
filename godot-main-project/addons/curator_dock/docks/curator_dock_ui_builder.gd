@tool
extends RefCounted
class_name CuratorDockUIBuilder

# UI incapsulata: il Dock accede solo via ui.<campo>
class CuratorDockUI:
	var global_omeka_url: LineEdit
	var root_item_id: OptionButton
	var fetch_tus_btn: Button
	var refresh_scene_btn: Button
	var instantiate_progress_lbl: Label
	var instantiate_status_bar: PanelContainer
	var last_sync_lbl: Label

	# Sezioni collapsable
	var save_section_btn: Button
	var save_section_content: VBoxContainer
	var scene_section_btn: Button
	var scene_section_content: VBoxContainer
	var scene_split: HSplitContainer

	# Sanity labels
	var sanity_player: Label
	var sanity_lights: Label
	var sanity_floor: Label
	var sanity_env: Label

	# List
	var help_lbl: Label
	var item_list: Tree

	# Right panel
	var preview: TextureRect
	var place_btn: Button
	var offset_x: SpinBox
	var offset_z: SpinBox
	var rot_x: SpinBox
	var rot_y: SpinBox
	var rot_z: SpinBox
	var rot_reset_btn: Button

	# Dangerous
	var auto_layout_btn: Button
	var reset_btn: Button
	var ensure_player_btn: Button
	var ensure_floor_btn: Button
	var ensure_lights_btn: Button

	# Saving
	var save_pwd_edit: LineEdit
	var save_upload_btn: Button
	var save_fetch_btn: Button
	var save_scene_list: OptionButton
	var save_download_btn: Button

	# Optional knobs
	var spacing_edit: SpinBox
	var cols_edit: SpinBox


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
	var color_danger = Color(0.60, 0.25, 0.25)
	var color_standard = Color(0.20, 0.21, 0.22)
	var color_save = Color(0.24, 0.45, 0.30)

	# ------------------------------------------------------------
	# SEZIONE 1: IMPOSTAZIONI (Collassabile)
	# ------------------------------------------------------------
	var settings_container = VBoxContainer.new()
	_create_collapsible_section(parent, "v IMPOSTAZIONI", settings_container, color_action)

	var grid := GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("v_separation", 6)
	settings_container.add_child(grid)

	var url_lbl := Label.new()
	url_lbl.text = "Omeka URL:"
	grid.add_child(url_lbl)

	ui.global_omeka_url = LineEdit.new()
	ui.global_omeka_url.text = "https://omekadev.livingculture.it"
	ui.global_omeka_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ui.global_omeka_url)

	var id_lbl := Label.new()
	id_lbl.text = "Unità Tematica:"
	grid.add_child(id_lbl)

	var env_hbox := HBoxContainer.new()
	env_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(env_hbox)

	ui.root_item_id = OptionButton.new()
	ui.root_item_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.root_item_id.add_item("Inserisci URL e aggiorna...", 0)
	env_hbox.add_child(ui.root_item_id)

	ui.fetch_tus_btn = Button.new()
	ui.fetch_tus_btn.text = "Aggiorna Lista"
	_apply_button_style(ui.fetch_tus_btn, color_action)
	env_hbox.add_child(ui.fetch_tus_btn)

	ui.instantiate_status_bar = PanelContainer.new()
	ui.instantiate_status_bar.visible = false
	ui.instantiate_status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color(0.16, 0.20, 0.26, 0.95)
	status_style.corner_radius_top_left = 6
	status_style.corner_radius_top_right = 6
	status_style.corner_radius_bottom_left = 6
	status_style.corner_radius_bottom_right = 6
	status_style.content_margin_left = 10
	status_style.content_margin_right = 10
	status_style.content_margin_top = 6
	status_style.content_margin_bottom = 6
	ui.instantiate_status_bar.add_theme_stylebox_override("panel", status_style)
	settings_container.add_child(ui.instantiate_status_bar)

	ui.instantiate_progress_lbl = Label.new()
	ui.instantiate_progress_lbl.text = ""
	ui.instantiate_progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ui.instantiate_progress_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.instantiate_status_bar.add_child(ui.instantiate_progress_lbl)

	# ------------------------------------------------------------
	# SEZIONE 2: SALVATAGGIO SCENA (Collassabile)
	# ------------------------------------------------------------
	parent.add_child(HSeparator.new())
	ui.save_section_content = VBoxContainer.new()
	ui.save_section_btn = _create_collapsible_section(parent, "> SALVATAGGIO SCENA", ui.save_section_content, color_action)
	ui.save_section_content.hide()

	var pwd_hbox = HBoxContainer.new()
	var pwd_lbl = Label.new()
	pwd_lbl.text = "Pwd:"
	ui.save_pwd_edit = LineEdit.new()
	ui.save_pwd_edit.secret = true
	ui.save_pwd_edit.placeholder_text = "Da richiedere..."
	ui.save_pwd_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pwd_hbox.add_child(pwd_lbl)
	pwd_hbox.add_child(ui.save_pwd_edit)
	ui.save_section_content.add_child(pwd_hbox)

	var actions_row = HBoxContainer.new()
	actions_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.save_upload_btn = Button.new()
	ui.save_upload_btn.text = "Salva sul DB"
	ui.save_upload_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button_style(ui.save_upload_btn, color_save)
	actions_row.add_child(ui.save_upload_btn)

	ui.save_download_btn = Button.new()
	ui.save_download_btn.text = "Scarica dal DB"
	ui.save_download_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button_style(ui.save_download_btn, color_cta)
	actions_row.add_child(ui.save_download_btn)
	ui.save_section_content.add_child(actions_row)

	var list_row = HBoxContainer.new()
	list_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.save_scene_list = OptionButton.new()
	ui.save_scene_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.save_scene_list.add_item("Nessuna scena trovata", 0)
	ui.save_scene_list.set_item_disabled(0, true)
	list_row.add_child(ui.save_scene_list)
	ui.save_fetch_btn = Button.new()
	ui.save_fetch_btn.text = "Aggiorna lista"
	_apply_button_style(ui.save_fetch_btn, color_action)
	list_row.add_child(ui.save_fetch_btn)
	ui.save_section_content.add_child(list_row)

	# ------------------------------------------------------------
	# SEZIONE 3: GESTIONE SCENA (Collassabile)
	# ------------------------------------------------------------
	parent.add_child(HSeparator.new())
	ui.scene_section_content = VBoxContainer.new()
	ui.scene_section_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.scene_section_btn = _create_collapsible_section(parent, "> GESTIONE SCENA", ui.scene_section_content, color_action)
	ui.scene_section_content.hide()

	var split := HSplitContainer.new()
	ui.scene_split = split
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 340)

	var sync_row := HBoxContainer.new()
	sync_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.scene_section_content.add_child(sync_row)

	ui.refresh_scene_btn = Button.new()
	ui.refresh_scene_btn.text = "Sync da Omeka"
	ui.refresh_scene_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button_style(ui.refresh_scene_btn, color_cta, 8)
	sync_row.add_child(ui.refresh_scene_btn)

	ui.last_sync_lbl = Label.new()
	ui.last_sync_lbl.text = "Ultimo sync: --"
	ui.last_sync_lbl.custom_minimum_size = Vector2(180, 0)
	ui.last_sync_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.last_sync_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sync_row.add_child(ui.last_sync_lbl)

	ui.scene_section_content.add_child(HSeparator.new())
	ui.scene_section_content.add_child(split)

	ui.item_list = Tree.new()
	ui.item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.item_list.columns = 1
	ui.item_list.hide_root = true
	ui.item_list.select_mode = Tree.SELECT_ROW
	split.add_child(ui.item_list)

	var right2 := VBoxContainer.new()
	right2.custom_minimum_size = Vector2(200, 0)
	split.add_child(right2)

	var prev_label := Label.new()
	prev_label.text = "Thumbnail"
	right2.add_child(prev_label)

	ui.preview = TextureRect.new()
	ui.preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	ui.preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ui.preview.custom_minimum_size = Vector2(150, 150)
	right2.add_child(ui.preview)

	right2.add_child(HSeparator.new())

	var off_title := Label.new()
	off_title.text = "Spostamento Globale"
	right2.add_child(off_title)

	var x_hbox := HBoxContainer.new()
	var x_lbl := Label.new()
	x_lbl.text = "X (Rosso):"
	ui.offset_x = SpinBox.new()
	ui.offset_x.min_value = -9999
	ui.offset_x.max_value = 9999
	ui.offset_x.step = 0.1
	ui.offset_x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	x_hbox.add_child(x_lbl)
	x_hbox.add_child(ui.offset_x)
	right2.add_child(x_hbox)

	var z_hbox := HBoxContainer.new()
	var z_lbl := Label.new()
	z_lbl.text = "Z (Blu):"
	ui.offset_z = SpinBox.new()
	ui.offset_z.min_value = -9999
	ui.offset_z.max_value = 9999
	ui.offset_z.step = 0.1
	ui.offset_z.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	z_hbox.add_child(z_lbl)
	z_hbox.add_child(ui.offset_z)
	right2.add_child(z_hbox)

	ui.place_btn = Button.new()
	ui.place_btn.text = "Riposiziona"
	ui.place_btn.disabled = true
	_apply_button_style(ui.place_btn, color_action)
	right2.add_child(ui.place_btn)

	ui.rot_reset_btn = Button.new()
	ui.rot_reset_btn.text = "Reset rotazioni"
	_apply_button_style(ui.rot_reset_btn, color_standard)
	right2.add_child(ui.rot_reset_btn)

	# ------------------------------------------------------------
	# SEZIONE 4: PERICOLI & UTILITIES (Collassabile)
	# ------------------------------------------------------------
	parent.add_child(HSeparator.new())
	var danger_container = VBoxContainer.new()
	_create_collapsible_section(parent, "> PULSANTI PERICOLOSI", danger_container, color_action)
	danger_container.hide()

	var layout_lbl := Label.new()
	layout_lbl.text = "Auto Layout (Griglia):"
	danger_container.add_child(layout_lbl)

	var auto_row := HBoxContainer.new()
	danger_container.add_child(auto_row)

	ui.spacing_edit = SpinBox.new()
	ui.spacing_edit.min_value = 0.1
	ui.spacing_edit.max_value = 100.0
	ui.spacing_edit.step = 0.1
	ui.spacing_edit.value = 2.0
	ui.spacing_edit.prefix = "Dist:"
	ui.spacing_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_row.add_child(ui.spacing_edit)

	ui.cols_edit = SpinBox.new()
	ui.cols_edit.min_value = 1
	ui.cols_edit.max_value = 50
	ui.cols_edit.step = 1
	ui.cols_edit.value = 6
	ui.cols_edit.prefix = "Col:"
	ui.cols_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_row.add_child(ui.cols_edit)

	ui.auto_layout_btn = Button.new()
	ui.auto_layout_btn.text = "Applica Layout"
	_apply_button_style(ui.auto_layout_btn, color_standard)
	danger_container.add_child(ui.auto_layout_btn)

	danger_container.add_child(HSeparator.new())

	ui.reset_btn = Button.new()
	ui.reset_btn.text = "Distruggi tutto (Svuota scena)"
	_apply_button_style(ui.reset_btn, color_danger, 6)
	danger_container.add_child(ui.reset_btn)

	# Nodi vecchi disabilitati per pulizia
	ui.sanity_player = Label.new()
	ui.sanity_lights = Label.new()
	ui.sanity_floor = Label.new()
	ui.sanity_env = Label.new()
	ui.ensure_player_btn = Button.new()
	ui.ensure_floor_btn = Button.new()
	ui.ensure_lights_btn = Button.new()

	return ui


# ==============================================================================
# HELPERS, COLLAPSABLE and BUTTON STYLE
# ==============================================================================

func _create_collapsible_section(parent: Control, title: String, content_container: Control, color: Color) -> Button:
	var btn = Button.new()
	btn.text = title
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


func set_collapsible_state(btn: Button, content_container: Control, is_open: bool) -> void:
	if btn == null or content_container == null:
		return
	content_container.visible = is_open
	var raw_title := btn.text
	if raw_title.begins_with("v ") or raw_title.begins_with("> "):
		raw_title = raw_title.substr(2)
	btn.text = ("v " if is_open else "> ") + raw_title


func _apply_button_style(btn: Button, bg_color: Color, padding_v: int = 4) -> void:
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