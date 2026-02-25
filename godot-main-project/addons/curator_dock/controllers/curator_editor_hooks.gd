@tool
extends RefCounted
class_name CuratorEditorHooks

signal refresh_requested()
signal editor_env_selection_changed(node: Node)

# ✅ NEW: gizmo/move tracking (polling leggero)
signal selected_node_moved(node: Node3D, global_pos: Vector3)

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager
var scene_ctrl: CuratorSceneController
var _selection: EditorSelection
var _suppress_selection := false

# ✅ NEW: host + timer for movement polling
var _host: Node = null
var _move_timer: Timer = null
var _tracked_node: Node3D = null
var _last_pos: Vector3 = Vector3.INF
var _poll_interval_sec: float = 0.10

func bind(
	_editor_interface: EditorInterface,
	_undo_redo: EditorUndoRedoManager,
	_scene_ctrl: CuratorSceneController,
	host: Node = null
) -> void:
	editor_interface = _editor_interface
	undo_redo = _undo_redo
	scene_ctrl = _scene_ctrl
	_host = host

	_selection = editor_interface.get_selection()

	_bind_tree_signals()
	_bind_undo_redo_signals()
	if _selection and not _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.connect(_on_selection_changed, CONNECT_DEFERRED)

	# ✅ setup timer (optional)
	_setup_move_timer()

func set_suppress_selection(v: bool) -> void:
	_suppress_selection = v

# ------------------------------------------------------------
# Editor selection -> dock list sync (existing)
# + start tracking movement (new)
# ------------------------------------------------------------
func _on_selection_changed() -> void:
	if _suppress_selection:
		return

	# Prendi il primo selezionato (selezione multipla: scegli il primo)
	var nodes := _selection.get_selected_nodes()
	var n: Node = null if nodes.is_empty() else nodes[0]

	var env := scene_ctrl.get_environment(editor_interface)
	if env == null or n == null:
		emit_signal("editor_env_selection_changed", null)
		_track_selected_node(null) # ✅ stop tracking
		return

	# Consideriamo solo LivingItem dentro env
	if not (n is LivingItem):
		emit_signal("editor_env_selection_changed", null)
		_track_selected_node(null) # ✅ stop tracking
		return
	if n != env and not env.is_ancestor_of(n):
		emit_signal("editor_env_selection_changed", null)
		_track_selected_node(null) # ✅ stop tracking
		return

	emit_signal("editor_env_selection_changed", n)

	# ✅ start tracking gizmo movement
	if n is Node3D:
		_track_selected_node(n as Node3D)
	else:
		_track_selected_node(null)

func clear_editor_selection() -> void:
	if editor_interface == null:
		return
	var sel := editor_interface.get_selection()
	if sel == null:
		return

	# evita loop: clear -> selection_changed -> dock -> ecc.
	_suppress_selection = true
	sel.clear()
	_suppress_selection = false

	# ferma tracking movimento + notifica dock che non c’è selezione valida
	_track_selected_node(null)
	emit_signal("editor_env_selection_changed", null)

# ------------------------------------------------------------
# Refresh API (existing)
# ------------------------------------------------------------
func _request_refresh() -> void:
	call_deferred("_emit_refresh")

func _emit_refresh() -> void:
	emit_signal("refresh_requested")

# ------------------------------------------------------------
# Tree + undo/redo hooks (existing)
# ------------------------------------------------------------
func _bind_tree_signals() -> void:
	var t := Engine.get_main_loop() as SceneTree
	if t == null:
		return
	if not t.node_added.is_connected(_on_tree_node_added):
		t.node_added.connect(_on_tree_node_added)
	if not t.node_removed.is_connected(_on_tree_node_removed):
		t.node_removed.connect(_on_tree_node_removed)

func _bind_undo_redo_signals() -> void:
	if undo_redo == null:
		return

	if undo_redo.has_signal("version_changed"):
		if not undo_redo.version_changed.is_connected(_on_undo_redo_changed):
			undo_redo.version_changed.connect(_on_undo_redo_changed)
	elif undo_redo.has_signal("history_changed"):
		if not undo_redo.history_changed.is_connected(_on_undo_redo_changed):
			undo_redo.history_changed.connect(_on_undo_redo_changed)

func _on_undo_redo_changed() -> void:
	_request_refresh()

func _on_tree_node_added(n: Node) -> void:
	_on_tree_changed(n)

func _on_tree_node_removed(n: Node) -> void:
	_on_tree_changed(n)

func _on_tree_changed(n: Node) -> void:
	if scene_ctrl == null:
		return

	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		return

	# interessa solo LivingItem
	if not (n is LivingItem):
		return

	# interessa solo se è env o discendente di env
	if n != env and not env.is_ancestor_of(n):
		return

	_request_refresh()

# ------------------------------------------------------------
# Rename watchers (existing)
# ------------------------------------------------------------
func bind_rename_watchers_from_snapshot(snapshot: Array) -> void:
	for row in snapshot:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var iid := int(row.get("instance_id", 0))
		if iid == 0:
			continue

		var obj := instance_from_id(iid)
		if obj == null or not (obj is Node):
			continue
		var n := obj as Node
		if not (n is LivingItem):
			continue

		if not n.renamed.is_connected(_on_any_livingitem_renamed):
			n.renamed.connect(_on_any_livingitem_renamed)

func _on_any_livingitem_renamed() -> void:
	_request_refresh()

# ------------------------------------------------------------
# ✅ NEW: selection movement tracking (gizmo)
# ------------------------------------------------------------
func _setup_move_timer() -> void:
	# timer lives under host (dock) so it runs in editor
	if _host == null:
		return
	if _move_timer != null and is_instance_valid(_move_timer):
		return

	_move_timer = Timer.new()
	_move_timer.one_shot = false
	_move_timer.wait_time = max(0.05, _poll_interval_sec)
	_host.add_child(_move_timer)
	_move_timer.timeout.connect(_poll_selected_node_movement, CONNECT_DEFERRED)

func _track_selected_node(n: Node3D) -> void:
	_setup_move_timer()

	_tracked_node = n
	_last_pos = Vector3.INF

	if _move_timer == null:
		return

	if _tracked_node != null and is_instance_valid(_tracked_node) and _tracked_node.is_inside_tree():
		_move_timer.start()
		_poll_selected_node_movement() # emit immediately
	else:
		_move_timer.stop()

func _poll_selected_node_movement() -> void:
	if _tracked_node == null or not is_instance_valid(_tracked_node) or not _tracked_node.is_inside_tree():
		if _move_timer != null:
			_move_timer.stop()
		_tracked_node = null
		_last_pos = Vector3.INF
		return

	# safety: still must be inside current env
	var env := scene_ctrl.get_environment(editor_interface)
	if env == null:
		_track_selected_node(null)
		return
	if _tracked_node != env and not env.is_ancestor_of(_tracked_node):
		_track_selected_node(null)
		return

	var p := _tracked_node.global_position
	if p.is_equal_approx(_last_pos):
		return

	_last_pos = p
	selected_node_moved.emit(_tracked_node, p)