@tool
extends RefCounted
class_name CuratorEditorHooks

signal refresh_requested()
signal editor_env_selection_changed(node: Node)

signal selected_node_transformed(node: Node3D, global_pos: Vector3, global_rot_deg: Vector3)

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager
var access: CuratorSceneAccess
var _selection: EditorSelection
var _suppress_selection := false


var _host: Node = null
var _move_timer: Timer = null
var _tracked_node: Node3D = null
var _last_pos: Vector3 = Vector3.INF
var _last_rot: Vector3 = Vector3.INF
var _last_scale := Vector3.INF
var _poll_interval_sec: float = 0.10


func bind(
	_editor_interface: EditorInterface,
	_undo_redo: EditorUndoRedoManager,
	_access: CuratorSceneAccess,
	host: Node = null
) -> void:
	editor_interface = _editor_interface
	undo_redo = _undo_redo
	access = _access
	_host = host

	_selection = editor_interface.get_selection()

	_bind_tree_signals()
	_bind_undo_redo_signals()
	if _selection and not _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.connect(_on_selection_changed, CONNECT_DEFERRED)

	_setup_move_timer()


func set_suppress_selection(v: bool) -> void:
	_suppress_selection = v


func _on_selection_changed() -> void:
	if _suppress_selection:
		return

	var nodes := _selection.get_selected_nodes()
	var n: Node = null if nodes.is_empty() else nodes[0]

	var env := access.get_environment(editor_interface)
	if env == null or n == null:
		editor_env_selection_changed.emit(null)
		_track_selected_node(null)
		return

	if not (n is LivingItem):
		editor_env_selection_changed.emit(null)
		_track_selected_node(null)
		return
	if n != env and not env.is_ancestor_of(n):
		editor_env_selection_changed.emit(null)
		_track_selected_node(null)
		return

	editor_env_selection_changed.emit(n)

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

	_suppress_selection = true
	sel.clear()
	_suppress_selection = false

	_track_selected_node(null)
	editor_env_selection_changed.emit(null)


func request_refresh() -> void:
	call_deferred("_emit_refresh")

func _emit_refresh() -> void:
	refresh_requested.emit()


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
	request_refresh()

func _on_tree_node_added(n: Node) -> void:
	_on_tree_changed(n)

func _on_tree_node_removed(n: Node) -> void:
	_on_tree_changed(n)

func _on_tree_changed(n: Node) -> void:
	if access == null:
		return

	var env := access.get_environment(editor_interface)
	if env == null:
		return

	if n != env and not env.is_ancestor_of(n):
		return

	request_refresh()


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
	request_refresh()


# ------------------------------------------------------------
# Selection transform tracking (gizmo)
# ------------------------------------------------------------
func _setup_move_timer() -> void:
	if _host == null:
		return
	if _move_timer != null and is_instance_valid(_move_timer):
		return

	_move_timer = Timer.new()
	_move_timer.one_shot = false
	_move_timer.wait_time = max(0.05, _poll_interval_sec)
	_host.add_child(_move_timer)
	_move_timer.timeout.connect(_poll_selected_node_transform, CONNECT_DEFERRED)


func _track_selected_node(n: Node3D) -> void:
	_setup_move_timer()

	_tracked_node = n
	_last_pos = Vector3.INF
	_last_rot = Vector3.INF
	_last_scale = Vector3.INF 

	if _move_timer == null:
		return

	if _tracked_node != null and is_instance_valid(_tracked_node) and _tracked_node.is_inside_tree():
		_move_timer.start()
		_poll_selected_node_transform() # emit immediately
	else:
		_move_timer.stop()


func _poll_selected_node_transform() -> void:
	if _tracked_node == null or not is_instance_valid(_tracked_node) or not _tracked_node.is_inside_tree():
		if _move_timer != null:
			_move_timer.stop()
		_tracked_node = null
		_last_pos = Vector3.INF
		_last_rot = Vector3.INF
		_last_scale = Vector3.INF
		return

	var env := access.get_environment(editor_interface)
	if env == null:
		_track_selected_node(null)
		return
	if _tracked_node != env and not env.is_ancestor_of(_tracked_node):
		_track_selected_node(null)
		return

	var p := _tracked_node.global_position
	var r := _tracked_node.rotation_degrees
	var s := _tracked_node.scale # Usiamo la scala locale

	var pos_changed := not p.is_equal_approx(_last_pos)
	var rot_changed := not r.is_equal_approx(_last_rot)
	var scale_changed := not s.is_equal_approx(_last_scale)

	# Se non si è mosso nulla, usciamo
	if not pos_changed and not rot_changed and not scale_changed:
		return

	# --- FORZA LA SCALA UNIFORME ---
	if scale_changed and _last_scale != Vector3.INF:
		# Se gli assi non sono tutti e 3 identici, l'utente sta usando il gizmo per deformare!
		if not is_equal_approx(s.x, s.y) or not is_equal_approx(s.y, s.z):
			
			# Troviamo quale asse ha tirato l'utente confrontandolo col frame precedente
			var diff = (s - _last_scale).abs()
			var uniform_val = s.x
			
			if diff.y > diff.x and diff.y > diff.z:
				uniform_val = s.y
			elif diff.z > diff.x and diff.z > diff.y:
				uniform_val = s.z
			
			# Creiamo un vettore uniforme con l'asse che ha subito la modifica maggiore
			s = Vector3(uniform_val, uniform_val, uniform_val)
			
			# Sovrascriviamo la trasformazione "sbagliata" prima che l'utente se ne accorga!
			_tracked_node.scale = s
	# ------------------------------

	_last_pos = p
	_last_rot = r
	_last_scale = s

	# Emettiamo il segnale (non c'è bisogno di cambiare la firma, 
	# il Dock legge già la scala direttamente dal nodo aggiornato!)
	selected_node_transformed.emit(_tracked_node, p, r)