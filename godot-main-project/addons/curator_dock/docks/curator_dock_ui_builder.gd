@tool
extends RefCounted
class_name CuratorDockUIBuilder

# UI “incapsulata”: il Dock accede solo via ui.<campo>
class CuratorDockUI:
	var global_omeka_url: LineEdit
	var root_item_id: OptionButton 
	var fetch_envs_btn: Button
	var instantiate_scene_btn: Button
	var instantiate_progress_lbl: Label

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

	# Optional knobs
	var spacing_edit: SpinBox
	var cols_edit: SpinBox


func build(parent: Control) -> CuratorDockUI:
	var ui := CuratorDockUI.new()

	# --- STILI PER I TITOLI (Eleganti e tenui) ---
	var header_settings = LabelSettings.new()
	header_settings.font_color = Color(0.70, 0.80, 0.85) # Azzurro polvere / ghiaccio
	header_settings.font_size = parent.get_theme_default_font_size() + 2
	header_settings.outline_size = 2
	header_settings.outline_color = Color(0, 0, 0, 0.4) # Ombra leggera
	header_settings.font = parent.get_theme_font("bold", "EditorFonts")
	# --------------------------
	
	# --- PALETTE COLORI BOTTONI (Godot-Native Feel) ---
	var color_cta = Color(0.22, 0.42, 0.60)      # Blu Petrolio/Desaturato (Professionale)
	var color_action = Color(0.24, 0.25, 0.27)   # Grigio neutro leggermente sporgente
	var color_danger = Color(0.60, 0.25, 0.25)   # Rosso mattone/bordeaux
	var color_standard = Color(0.20, 0.21, 0.22) # Grigio scuro (come lo sfondo di Godot)
	# ------------------------------

	# ------------------------------------------------------------
	# IMPOSTAZIONI (grid) + CTA
	# ------------------------------------------------------------
	var settings_title := Label.new()
	settings_title.text = "IMPOSTAZIONI"
	settings_title.label_settings = header_settings
	parent.add_child(settings_title)

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 8)
	parent.add_child(card)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)

	# --- Omeka URL ---
	var url_lbl := Label.new()
	url_lbl.text = "Omeka URL"
	grid.add_child(url_lbl)

	ui.global_omeka_url = LineEdit.new()
	ui.global_omeka_url.text = "https://omekadev.livingculture.it"
	ui.global_omeka_url.placeholder_text = "https://omekas.livingculture.it o omekadev"
	ui.global_omeka_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ui.global_omeka_url)

	# --- Environment ID ---
	var id_lbl := Label.new()
	id_lbl.text = "Environment"
	grid.add_child(id_lbl)

	var env_hbox := HBoxContainer.new()
	env_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(env_hbox)

	ui.root_item_id = OptionButton.new()
	ui.root_item_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.root_item_id.add_item("Inserisci URL e aggiorna...", 0)
	env_hbox.add_child(ui.root_item_id)

	ui.fetch_envs_btn = Button.new()
	ui.fetch_envs_btn.text = "🔄 Aggiorna Lista"
	_apply_button_style(ui.fetch_envs_btn, color_action) 
	env_hbox.add_child(ui.fetch_envs_btn)

	var cta_row := HBoxContainer.new()
	cta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cta_row.add_theme_constant_override("separation", 10)
	card.add_child(cta_row)
	cta_row.add_spacer(true)

	var inst_row := HBoxContainer.new()
	inst_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inst_row.add_theme_constant_override("separation", 8)
	parent.add_child(inst_row)

	ui.instantiate_scene_btn = Button.new()
	ui.instantiate_scene_btn.text = "Istanzia ambiente"
	ui.instantiate_scene_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button_style(ui.instantiate_scene_btn, color_cta, 6) # Leggermente più spesso
	inst_row.add_child(ui.instantiate_scene_btn)

	ui.instantiate_progress_lbl = Label.new()
	ui.instantiate_progress_lbl.text = "" 
	ui.instantiate_progress_lbl.add_theme_font_size_override("font_size", parent.get_theme_default_font_size() + 3)
	ui.instantiate_progress_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	ui.instantiate_progress_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.instantiate_progress_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inst_row.add_child(ui.instantiate_progress_lbl)

	var instantiate_warning_lbl := Label.new()
	instantiate_warning_lbl.text = "⚠ Sovrascrive se già istanziato"
	instantiate_warning_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	instantiate_warning_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	instantiate_warning_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	instantiate_warning_lbl.modulate = Color(0.8, 0.7, 0.4) # Giallo desaturato
	inst_row.add_child(instantiate_warning_lbl)

	parent.add_child(HSeparator.new())

	# ------------------------------------------------------------
	# GESTIONE SCENA Split list | right panel
	# ------------------------------------------------------------
	
	var scene_mgmt := Label.new()
	scene_mgmt.text = "GESTIONE SCENA"
	scene_mgmt.label_settings = header_settings
	parent.add_child(scene_mgmt)

	# ui.help_lbl = Label.new()
	# ui.help_lbl.text = "Help: Click seleziona / Doppio Click visualizza - nascondi"
	# ui.help_lbl.modulate = Color(1, 1, 1, 0.6) # Rende il testo di help più discreto
	# ui.help_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# parent.add_child(ui.help_lbl)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(split)

	ui.item_list = Tree.new()
	ui.item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.item_list.columns = 1
	ui.item_list.hide_root = true 
	ui.item_list.select_mode = Tree.SELECT_ROW
	split.add_child(ui.item_list)

	var right2 := VBoxContainer.new()
	right2.custom_minimum_size = Vector2(230, 0)
	split.add_child(right2)

	var prev_label := Label.new()
	prev_label.text = "Thumbnail"
	right2.add_child(prev_label)

	ui.preview = TextureRect.new()
	ui.preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	ui.preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ui.preview.custom_minimum_size = Vector2(200, 200)
	right2.add_child(ui.preview)

	right2.add_child(HSeparator.new())

	var off_title := Label.new()
	off_title.text = "Offset dall'origine (Orizzontale / Profondità)"
	right2.add_child(off_title)

	var off_row := HBoxContainer.new()
	right2.add_child(off_row)

	var x_lbl := Label.new()
	x_lbl.text = "X (Rossa):"
	off_row.add_child(x_lbl)

	ui.offset_x = SpinBox.new()
	ui.offset_x.min_value = -9999
	ui.offset_x.max_value = 9999
	ui.offset_x.step = 0.1
	ui.offset_x.value = 0.0
	ui.offset_x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	off_row.add_child(ui.offset_x)

	var z_lbl := Label.new()
	z_lbl.text = "Z (Blu):"
	off_row.add_child(z_lbl)

	ui.offset_z = SpinBox.new()
	ui.offset_z.min_value = -9999
	ui.offset_z.max_value = 9999
	ui.offset_z.step = 0.1
	ui.offset_z.value = 0.0
	ui.offset_z.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	off_row.add_child(ui.offset_z)

	ui.place_btn = Button.new()
	ui.place_btn.text = "Riposiziona"
	ui.place_btn.disabled = true
	_apply_button_style(ui.place_btn, color_action) 
	right2.add_child(ui.place_btn)

	ui.rot_reset_btn = Button.new()
	ui.rot_reset_btn.text = "Reset rotazioni"
	_apply_button_style(ui.rot_reset_btn, color_standard) 
	right2.add_child(ui.rot_reset_btn)

	parent.add_child(HSeparator.new())

	# ------------------------------------------------------------
	# Sanity Check row
	# ------------------------------------------------------------
	var sanity_title := Label.new()
	sanity_title.text = "SANITY CHECK"
	sanity_title.label_settings = header_settings
	parent.add_child(sanity_title)

	var sanity_row := HBoxContainer.new()
	sanity_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sanity_row)

	ui.sanity_player = Label.new()
	ui.sanity_player.text = "Player: …"
	sanity_row.add_child(ui.sanity_player)

	ui.sanity_lights = Label.new()
	ui.sanity_lights.text = "Luci: …"
	sanity_row.add_child(ui.sanity_lights)

	ui.sanity_floor = Label.new()
	ui.sanity_floor.text = "Floor: …"
	sanity_row.add_child(ui.sanity_floor)

	ui.sanity_env = Label.new()
	ui.sanity_env.text = "Ambiente: …"
	sanity_row.add_child(ui.sanity_env)

	ui.ensure_player_btn = Button.new()
	ui.ensure_player_btn.text = "Assicura Camera"
	_apply_button_style(ui.ensure_player_btn, color_standard) 
	sanity_row.add_child(ui.ensure_player_btn)

	ui.ensure_floor_btn = Button.new()
	ui.ensure_floor_btn.text = "Assicura Pavimento"
	_apply_button_style(ui.ensure_floor_btn, color_standard) 
	sanity_row.add_child(ui.ensure_floor_btn)

	ui.ensure_lights_btn = Button.new()
	ui.ensure_lights_btn.text = "Assicura Luci"
	_apply_button_style(ui.ensure_lights_btn, color_standard) 
	sanity_row.add_child(ui.ensure_lights_btn)

	parent.add_child(HSeparator.new())

	# ------------------------------------------------------------
	# Dangerous buttons
	# ------------------------------------------------------------
	var danger_title := Label.new()
	danger_title.text = "⚠ PULSANTI PERICOLOSI ⚠"
	danger_title.label_settings = header_settings
	parent.add_child(danger_title)

	var auto_row := HBoxContainer.new()
	parent.add_child(auto_row)

	var sp_lbl := Label.new()
	sp_lbl.text = "Distanza tra gli oggetti:"
	auto_row.add_child(sp_lbl)

	ui.spacing_edit = SpinBox.new()
	ui.spacing_edit.min_value = 0.1
	ui.spacing_edit.max_value = 100.0
	ui.spacing_edit.step = 0.1
	ui.spacing_edit.value = 2.0
	ui.spacing_edit.custom_minimum_size = Vector2(70, 0)
	auto_row.add_child(ui.spacing_edit)

	var cols_lbl := Label.new()
	cols_lbl.text = "Oggetti per riga:"
	auto_row.add_child(cols_lbl)

	ui.cols_edit = SpinBox.new()
	ui.cols_edit.min_value = 1
	ui.cols_edit.max_value = 50
	ui.cols_edit.step = 1
	ui.cols_edit.value = 6
	ui.cols_edit.custom_minimum_size = Vector2(55, 0)
	auto_row.add_child(ui.cols_edit)

	ui.auto_layout_btn = Button.new()
	ui.auto_layout_btn.text = "Auto Layout (Posiziona in griglia)"
	_apply_button_style(ui.auto_layout_btn, color_standard) 
	auto_row.add_child(ui.auto_layout_btn)

	ui.reset_btn = Button.new()
	ui.reset_btn.text = "⚠ Distruggi tutto (Svuota scena) ⚠"
	_apply_button_style(ui.reset_btn, color_danger, 6) 
	parent.add_child(ui.reset_btn)

	return ui


# ==============================================================================
# FUNZIONE DI UTILITÀ PER STILIZZARE I BOTTONI E SMUSSARE GLI ANGOLI
# ==============================================================================
func _apply_button_style(btn: Button, bg_color: Color, padding_v: int = 4) -> void:
	# Stato NORMALE
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 8     # Abbassato a 4 per un look più tecnico
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.corner_radius_bottom_right = 8
	style_normal.content_margin_top = padding_v
	style_normal.content_margin_bottom = padding_v
	style_normal.content_margin_left = 12
	style_normal.content_margin_right = 12
	
	# Stato MOUSE SOPRA (Hover) -> Colore leggermente più chiaro
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.12)
	
	# Stato CLICCATO (Pressed) -> Colore leggermente più scuro
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.15)
	
	# Stato DISABILITATO -> Grigio semitrasparente che si fonde col background
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.2, 0.2, 0.2, 0.4) 
	
	# Applichiamo gli stili al bottone
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	
	# Assicuriamoci che il testo sia bianco off-white (più elegante)
	var text_color = Color(0.9, 0.9, 0.9)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.7, 0.7, 0.7))
	btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND