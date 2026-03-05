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
	# --- MODIFICA IMPORTANTE: Da ItemList a Tree ---
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

	# --- STILI PER I TITOLI ---
	var header_settings = LabelSettings.new()
	header_settings.font_color = Color(0.35, 0.7, 1.0) # Azzurro acceso
	header_settings.font_size = parent.get_theme_default_font_size() + 3
	header_settings.outline_size = 2
	header_settings.outline_color = Color(0, 0, 0, 0.5)

	var danger_settings = LabelSettings.new()
	danger_settings.font_color = Color(1.0, 0.3, 0.3) # Rosso acceso
	danger_settings.font_size = parent.get_theme_default_font_size() + 3
	danger_settings.outline_size = 2
	danger_settings.outline_color = Color(0, 0, 0, 0.5)
	# --------------------------

	# ------------------------------------------------------------
	# IMPOSTAZIONI (grid) + CTA
	# ------------------------------------------------------------
	var settings_title := Label.new()
	settings_title.text = "IMPOSTAZIONI"
	settings_title.label_settings = header_settings
	parent.add_child(settings_title)

	# “Card” leggera (un VBox con separatori e padding)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 8)
	parent.add_child(card)

	# Grid 2x2: label a sinistra, campo a destra
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
	ui.fetch_envs_btn.text = "Aggiorna Lista"
	env_hbox.add_child(ui.fetch_envs_btn)

	# CTA row: bottone + warning sulla stessa riga
	var cta_row := HBoxContainer.new()
	cta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cta_row.add_theme_constant_override("separation", 10)
	card.add_child(cta_row)

	cta_row.add_spacer(true)

	# Riga CTA: [Istanzia ambiente] [0% (x/y)] [⚠ Sovrascrive...]
	var inst_row := HBoxContainer.new()
	inst_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inst_row.add_theme_constant_override("separation", 8)
	parent.add_child(inst_row)

	ui.instantiate_scene_btn = Button.new()
	ui.instantiate_scene_btn.text = "Istanzia ambiente"
	ui.instantiate_scene_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inst_row.add_child(ui.instantiate_scene_btn)

	ui.instantiate_progress_lbl = Label.new()
	ui.instantiate_progress_lbl.text = ""  # es: "0% (0/0)"
	ui.instantiate_progress_lbl.add_theme_font_size_override("font_size", parent.get_theme_default_font_size() + 5)
	ui.instantiate_progress_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	ui.instantiate_progress_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.instantiate_progress_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inst_row.add_child(ui.instantiate_progress_lbl)

	var instantiate_warning_lbl := Label.new()
	instantiate_warning_lbl.text = "⚠ Sovrascrive se già istanziato"
	instantiate_warning_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	instantiate_warning_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	instantiate_warning_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	instantiate_warning_lbl.modulate = Color(1, 0.75, 0.2) # opzionale
	inst_row.add_child(instantiate_warning_lbl)

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
	ui.sanity_player.name = "SanityPlayer"
	ui.sanity_player.text = "Player: …"
	sanity_row.add_child(ui.sanity_player)

	ui.sanity_lights = Label.new()
	ui.sanity_lights.name = "SanityLights"
	ui.sanity_lights.text = "Luci: …"
	sanity_row.add_child(ui.sanity_lights)

	ui.sanity_floor = Label.new()
	ui.sanity_floor.name = "SanityFloor"
	ui.sanity_floor.text = "Floor: …"
	sanity_row.add_child(ui.sanity_floor)

	ui.sanity_env = Label.new()
	ui.sanity_env.name = "SanityEnv"
	ui.sanity_env.text = "Ambiente: …"
	sanity_row.add_child(ui.sanity_env)

	parent.add_child(HSeparator.new())

	var scene_mgmt := Label.new()
	scene_mgmt.text = "GESTIONE SCENA"
	scene_mgmt.label_settings = header_settings
	parent.add_child(scene_mgmt)
	
	# ------------------------------------------------------------
	# Aggiorna lista + help
	# ------------------------------------------------------------
	# ui.help_lbl = Label.new()
	# ui.help_lbl.text = "Help: Click seleziona / Doppio Click visualizza - nascondi"
	# ui.help_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# parent.add_child(ui.help_lbl)

	# ------------------------------------------------------------
	# Split list | right panel
	# ------------------------------------------------------------
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(split)

	# --- MODIFICA: Inizializzazione del Tree invece che ItemList ---
	ui.item_list = Tree.new()
	ui.item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.item_list.columns = 1
	ui.item_list.hide_root = true # Nasconde la radice finta per sembrare una lista piatta
	ui.item_list.select_mode = Tree.SELECT_ROW
	split.add_child(ui.item_list)
	# ---------------------------------------------------------------

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
	ui.offset_x.name = "Offset Orizzontale (X)"
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
	ui.offset_z.name = "Offset Profondità (Z)"
	ui.offset_z.min_value = -9999
	ui.offset_z.max_value = 9999
	ui.offset_z.step = 0.1
	ui.offset_z.value = 0.0
	ui.offset_z.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	off_row.add_child(ui.offset_z)

	ui.place_btn = Button.new()
	ui.place_btn.text = "Riposiziona"
	ui.place_btn.disabled = true
	right2.add_child(ui.place_btn)

	ui.rot_reset_btn = Button.new()
	ui.rot_reset_btn.text = "Reset rotazioni"
	right2.add_child(ui.rot_reset_btn)

	parent.add_child(HSeparator.new())

	# ------------------------------------------------------------
	# Dangerous buttons
	# ------------------------------------------------------------
	var danger_title := Label.new()
	danger_title.text = "⚠️ PULSANTI PERICOLOSI"
	danger_title.label_settings = danger_settings
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
	auto_row.add_child(ui.auto_layout_btn)

	# --- MODIFICA TASTO DISTRUGGI TUTTO ---
	ui.reset_btn = Button.new()
	ui.reset_btn.text = "💣 Distruggi tutto (Svuota scena) ⚠️"
	ui.reset_btn.modulate = Color(1.0, 0.4, 0.4) # Tinta rossa per renderlo chiaramente pericoloso
	parent.add_child(ui.reset_btn)

	var ensure_row := HBoxContainer.new()
	parent.add_child(ensure_row)

	ui.ensure_player_btn = Button.new()
	ui.ensure_player_btn.text = "Assicura Camera"
	ensure_row.add_child(ui.ensure_player_btn)

	ui.ensure_floor_btn = Button.new()
	ui.ensure_floor_btn.text = "Assicura Pavimento"
	ensure_row.add_child(ui.ensure_floor_btn)

	ui.ensure_lights_btn = Button.new()
	ui.ensure_lights_btn.text = "Assicura Luci"
	ensure_row.add_child(ui.ensure_lights_btn)

	return ui
