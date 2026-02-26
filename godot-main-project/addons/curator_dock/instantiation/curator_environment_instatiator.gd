@tool
extends RefCounted
class_name CuratorEnvironmentInstantiator

signal started()
signal failed(msg: String)
signal opened_new_scene(path: String)
signal rebuild_finished(success: bool, env: LivingEnvironment)

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager
var scene_ctrl: CuratorSceneController
var setup_ctrl: CuratorSetupController

var template_scene_path: String = ""
var curated_scenes_dir: String = ""

# ------------------------------------------------------------
# Setup
# ------------------------------------------------------------
func configure(
	_editor_interface: EditorInterface,
	_undo_redo: EditorUndoRedoManager,
	_scene_ctrl: CuratorSceneController,
	_setup_ctrl: CuratorSetupController,
	_template_scene_path: String,
	_curated_scenes_dir: String
) -> void:
	editor_interface = _editor_interface
	undo_redo = _undo_redo
	scene_ctrl = _scene_ctrl
	setup_ctrl = _setup_ctrl
	template_scene_path = _template_scene_path
	curated_scenes_dir = _curated_scenes_dir

# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------
func run(desired_env_id: int, omeka_url: String) -> void:
	if editor_interface == null or scene_ctrl == null or setup_ctrl == null:
		failed.emit("Instantiator not configured")
		return

	started.emit()

	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		var new_path := _create_copy_from_template(desired_env_id)
		if new_path == "":
			# error already emitted
			return
		opened_new_scene.emit(new_path)
		editor_interface.open_scene_from_path(new_path)
		# root becomes available next frame
		call_deferred("_continue_after_open", desired_env_id, omeka_url)
		return

	_continue_on_env(env, desired_env_id, omeka_url)

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
	scene_ctrl.apply_global_url_to_current_scene(editor_interface, undo_redo, omeka_url)

	# 2) Ensure camera/floor/lights etc
	setup_ctrl.ensure_all(env, undo_redo, scene_ctrl.edited_scene_root(editor_interface))

	# 3) Align Environment item_id
	if int(env.item_id) != desired_env_id:
		if undo_redo != null:
			undo_redo.create_action("Set LivingEnvironment item_id")
			undo_redo.add_do_property(env, "item_id", desired_env_id)
			undo_redo.add_undo_property(env, "item_id", env.item_id)
			undo_redo.commit_action()
		else:
			env.item_id = desired_env_id

	# 4) Hook build_finished once, then rebuild
	if env.build_finished.is_connected(_on_env_build_finished):
		env.build_finished.disconnect(_on_env_build_finished)

	env.build_finished.connect(_on_env_build_finished.bind(env), CONNECT_ONE_SHOT)
	env.rebuild_environment()

func _on_env_build_finished(success: bool, env: LivingEnvironment) -> void:
	rebuild_finished.emit(success, env)

func _create_copy_from_template(desired_env_id: int) -> String:
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

	# Ensure output folder exists
	if curated_scenes_dir.strip_edges() == "":
		failed.emit("Curated scenes dir not set")
		return ""

	if not DirAccess.dir_exists_absolute(curated_scenes_dir):
		var derr := DirAccess.make_dir_recursive_absolute(curated_scenes_dir)
		if derr != OK:
			failed.emit("Cannot create directory: %s" % curated_scenes_dir)
			return ""

	# Unique filename
	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var fname := "env_%s_%s.tscn" % [str(desired_env_id), ts]
	var new_path := "%s/%s" % [curated_scenes_dir, fname]

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