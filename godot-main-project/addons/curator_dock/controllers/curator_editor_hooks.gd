@tool
extends RefCounted
class_name CuratorEditorHooks

signal refresh_requested()

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager
var scene_ctrl: CuratorSceneController


func bind(_editor_interface: EditorInterface, _undo_redo: EditorUndoRedoManager, _scene_ctrl: CuratorSceneController) -> void:
	editor_interface = _editor_interface
	undo_redo = _undo_redo
	scene_ctrl = _scene_ctrl

	_bind_tree_signals()
	_bind_undo_redo_signals()

func request_refresh() -> void:
	call_deferred("_emit_refresh")

func _emit_refresh() -> void:
	emit_signal("refresh_requested")

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

	request_refresh()

# Chiamiamo dopo che abbiamo uno snapshot (scan_environment)
# per aggiornare subito quando arrivano i title (rename async)
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