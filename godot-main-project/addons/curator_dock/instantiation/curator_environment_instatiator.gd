@tool
extends RefCounted
class_name CuratorEnvironmentInstantiator

signal started()
signal failed(msg: String)
signal opened_new_scene(path: String)
signal rebuild_finished(success: bool, env: LivingEnvironment)
signal auto_layout_finished(executed: bool)

var editor_interface: EditorInterface
var scene_ctrl: CuratorSceneController
var setup_ctrl: CuratorSetupController

var template_scene_path: String = ""
var curated_scenes_dir: String = ""

# ------------------------------------------------------------
# Setup
# ------------------------------------------------------------
func configure(
	_editor_interface: EditorInterface,
	_scene_ctrl: CuratorSceneController,
	_setup_ctrl: CuratorSetupController,
	_template_scene_path: String,
	_curated_scenes_dir: String
) -> void:
	editor_interface = _editor_interface
	scene_ctrl = _scene_ctrl
	setup_ctrl = _setup_ctrl
	template_scene_path = _template_scene_path
	curated_scenes_dir = _curated_scenes_dir

# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------
func run(desired_env_id: int, env_name: String, omeka_url: String) -> void:
	if editor_interface == null or scene_ctrl == null or setup_ctrl == null:
		failed.emit("Instantiator not configured")
		return

	started.emit()

	# FORZIAMO LA CREAZIONE DI UNA NUOVA SCENA PASSANDO IL NOME:
	var new_path := _create_copy_from_template(desired_env_id, env_name)
	if new_path == "":
		return
		
	opened_new_scene.emit(new_path)
	
	# Diciamo all'Editor di aprire il nuovo file appena creato
	editor_interface.open_scene_from_path(new_path)
	
	call_deferred("_continue_after_open", desired_env_id, omeka_url)

# ------------------------------------------------------------
# Internals
# ------------------------------------------------------------
func _continue_after_open(desired_env_id: int, omeka_url: String) -> void:
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		failed.emit("Cannot find LivingEnvironment after opening template copy")
		return
	_continue_on_env(env, desired_env_id, omeka_url)

func _continue_on_env(env: LivingEnvironment, desired_env_id: int, omeka_url: String) -> void:
	# 1) Apply URL
	scene_ctrl.apply_global_url_to_current_scene(editor_interface, omeka_url)

	# 2) Ensure camera/floor/lights etc
	setup_ctrl.ensure_all(env, scene_ctrl.edited_scene_root(editor_interface))

	# 3) Align Environment item_id
	if int(env.item_id) != desired_env_id:
		env.item_id = desired_env_id

	# 4) Hook build_finished once, then rebuild
	if env.rebuild_completed.is_connected(_on_env_build_finished):
		env.rebuild_completed.disconnect(_on_env_build_finished)

	env.rebuild_completed.connect(_on_env_build_finished.bind(env), CONNECT_ONE_SHOT)
	env.rebuild_environment()

func _on_env_build_finished(success: bool, env: LivingEnvironment) -> void:
	rebuild_finished.emit(success, env)
	
	# Appena la scena è pronta, chiediamo se si vuole fare l'auto-layout
	if success:
		_prompt_auto_layout(env)

func _create_copy_from_template(desired_env_id: int, env_name: String) -> String:
	if template_scene_path.strip_edges() == "":
		failed.emit("Template scene path not set")
		return ""

	var tpl: PackedScene = load(template_scene_path)
	if tpl == null:
		failed.emit("Template not found: %s" % template_scene_path)
		return ""

	var root := tpl.instantiate()
	if root == null or not (root is LivingEnvironment):
		failed.emit("Template root is not LivingEnvironment")
		return ""

	if curated_scenes_dir.strip_edges() == "":
		failed.emit("Curated scenes dir not set")
		return ""

	if not DirAccess.dir_exists_absolute(curated_scenes_dir):
		var derr := DirAccess.make_dir_recursive_absolute(curated_scenes_dir)
		if derr != OK:
			failed.emit("Cannot create directory: %s" % curated_scenes_dir)
			return ""

	# --- PULIZIA DEL NOME DELL'AMBIENTE ---
	var regex = RegEx.new()
	regex.compile("[^a-zA-Z0-9_\\s-]")
	var sanitized = regex.sub(env_name, "", true) 
	
	# Non usiamo to_snake_case() per preservare i trattini originali
	var safe_name = sanitized.strip_edges().to_lower().replace(" ", "_")
	
	if safe_name == "":
		safe_name = "env_" + str(desired_env_id)

	# Prendiamo solo la data (YYYY-MM-DD)
	var date_str := Time.get_date_string_from_system() 
	
	# Creiamo il file base: usiamo "_-_" che il Dock saprà tradurre in " - "
	var fname := "%s_-_%s_-_xy.tscn" % [safe_name, date_str]
	var new_path := "%s/%s" % [curated_scenes_dir, fname]

	# --- SICUREZZA ANTI-SOVRASCRITTURA ---
	# Se il file esiste già (es. un curatore ha già lavorato oggi su questo ambiente),
	# aggiungiamo un contatore progressivo alla fine per non perdere il lavoro!
	var counter = 1
	while FileAccess.file_exists(new_path):
		counter += 1
		fname = "%s_-_%s_-_xy_-_%d.tscn" % [safe_name, date_str, counter]
		new_path = "%s/%s" % [curated_scenes_dir, fname]

	var ps := PackedScene.new()
	var perr := ps.pack(root)
	if perr != OK:
		failed.emit("PackedScene.pack failed (%s)" % str(perr))
		return ""

	var serr := ResourceSaver.save(ps, new_path)
	if serr != OK:
		failed.emit("ResourceSaver.save failed (%s): %s" % [str(serr), new_path])
		return ""

	return new_path

# ------------------------------------------------------------
# Auto-Layout Logics
# ------------------------------------------------------------
func _prompt_auto_layout(env: LivingEnvironment) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "Auto Layout"
	
	var vbox = VBoxContainer.new()
	var lbl = Label.new()
	lbl.text = "Would you like to layout all the objects on a grid?"
	vbox.add_child(lbl)
	
	# Riga Colonne
	var hbox_cols = HBoxContainer.new()
	var cols_lbl = Label.new()
	cols_lbl.text = "Number of columns:"
	cols_lbl.custom_minimum_size = Vector2(80, 0)
	var cols_spin = SpinBox.new()
	cols_spin.min_value = 1
	cols_spin.value = 3
	hbox_cols.add_child(cols_lbl)
	hbox_cols.add_child(cols_spin)
	vbox.add_child(hbox_cols)
	
	# Riga Spaziatura
	var hbox_space = HBoxContainer.new()
	var space_lbl = Label.new()
	space_lbl.text = "Spacing between objects:"
	space_lbl.custom_minimum_size = Vector2(80, 0)
	var space_spin = SpinBox.new()
	space_spin.min_value = 0.1
	space_spin.step = 0.1
	space_spin.value = 2.0
	hbox_space.add_child(space_lbl)
	hbox_space.add_child(space_spin)
	vbox.add_child(hbox_space)
	
	dialog.add_child(vbox)
	editor_interface.get_base_control().add_child(dialog)
	
	dialog.confirmed.connect(func():
		_apply_auto_layout(env, int(cols_spin.value), float(space_spin.value))
		dialog.queue_free()
		auto_layout_finished.emit(true)
	)
	
	dialog.canceled.connect(func():
		dialog.queue_free()
		auto_layout_finished.emit(false)
	)
	
	dialog.popup_centered(Vector2(350, 100))

func _apply_auto_layout(env: LivingEnvironment, ccols: int, spacing: float) -> void:
	var areas: Array[LivingArea] = []
	_find_living_areas(env, areas)
	
	if areas.is_empty():
		return
		
	var all_elems: Array[LivingElement] = []
	
	# 1. Raccogliamo TUTTI i LivingElement da tutte le aree in un'unica grande lista
	for area in areas:
		for c in area.get_children():
			if c is LivingElement:
				all_elems.append(c as LivingElement)
				
	if all_elems.is_empty():
		return
		
	var elements_moved = 0
	
	# 2. Applichiamo il layout a scorrimento continuo sull'intera lista
	for i in range(all_elems.size()):
		var le := all_elems[i] as Node3D
		var col = i % ccols
		var row = i / ccols
		
		var target := Vector3(col * spacing, le.position.y, row * spacing)
		
		le.position = target
		le.visible = true
		elements_moved += 1
		
	if elements_moved > 0:
		print("Auto-layout eseguito su %d elementi totali (colonne=%d, spazio=%.2f)" % [elements_moved, ccols, spacing])
		EditorInterface.mark_scene_as_unsaved()

# Funzione ricorsiva per trovare tutte le LivingArea nell'ambiente
func _find_living_areas(node: Node, areas: Array[LivingArea]) -> void:
	if node is LivingArea:
		areas.append(node)
	for child in node.get_children():
		_find_living_areas(child, areas)
