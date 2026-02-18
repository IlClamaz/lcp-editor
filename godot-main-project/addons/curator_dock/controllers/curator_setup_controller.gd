@tool
extends RefCounted
class_name CuratorSetupController

# Percorsi delle scene fornite
const FLOOR_SCENE := "res://addons/living_platform_plugin/scenes/living_floor.tscn"
const LIGHTS_SCENE := "res://addons/living_platform_plugin/scenes/living_lights.tscn"
const PLAYER_SCENE := "res://addons/living_platform_plugin/scenes/living_camera.tscn"

# Gruppi "marker" per evitare duplicati
const GROUP_FLOOR := "curator_floor"
const GROUP_LIGHTS := "curator_lights"
const GROUP_PLAYER := "curator_player"

# Nomi di fallback (se vuoi trovarli anche per nome)
const NAME_FLOOR := "Living_Floor"
const NAME_LIGHTS := "Living_Lights"
const NAME_PLAYER := "Living_Camera"


func has_floor(ls: Node) -> bool:
	return _find_first_in_group_or_name(ls, GROUP_FLOOR, NAME_FLOOR) != null

func has_lights(ls: Node) -> bool:
	return _find_first_in_group_or_name(ls, GROUP_LIGHTS, NAME_LIGHTS) != null

func has_player(ls: Node) -> bool:
	return _find_first_in_group_or_name(ls, GROUP_PLAYER, NAME_PLAYER) != null


func ensure_floor(ls: Node, undo_redo: EditorUndoRedoManager, owner: Node) -> Node:
	var existing := _find_first_in_group_or_name(ls, GROUP_FLOOR, NAME_FLOOR)
	if existing != null:
		return existing

	var packed := load(FLOOR_SCENE) as PackedScene
	if packed == null:
		push_error("Cannot load floor scene: %s" % FLOOR_SCENE)
		return null

	var inst := packed.instantiate()
	inst.name = NAME_FLOOR
	inst.add_to_group(GROUP_FLOOR)

	_add_child_persistent(ls, inst, undo_redo, owner, "Add Floor")
	return inst


func ensure_lights(ls: Node, undo_redo: EditorUndoRedoManager, owner: Node) -> Node:
	var existing := _find_first_in_group_or_name(ls, GROUP_LIGHTS, NAME_LIGHTS)
	if existing != null:
		return existing

	var packed := load(LIGHTS_SCENE) as PackedScene
	if packed == null:
		push_error("Cannot load lights scene: %s" % LIGHTS_SCENE)
		return null

	var inst := packed.instantiate()
	inst.name = NAME_LIGHTS
	inst.add_to_group(GROUP_LIGHTS)

	_add_child_persistent(ls, inst, undo_redo, owner, "Add Lights")
	return inst


func ensure_player(ls: Node, undo_redo: EditorUndoRedoManager, owner: Node) -> Node:
	var existing := _find_first_in_group_or_name(ls, GROUP_PLAYER, NAME_PLAYER)
	if existing != null:
		return existing

	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		push_error("Cannot load player scene: %s" % PLAYER_SCENE)
		return null

	var inst := packed.instantiate()
	inst.name = NAME_PLAYER
	inst.add_to_group(GROUP_PLAYER)

	_add_child_persistent(ls, inst, undo_redo, owner, "Add Player/Camera")
	return inst


func ensure_all(ls: Node, undo_redo: EditorUndoRedoManager, owner: Node) -> void:
	ensure_player(ls, undo_redo, owner)
	ensure_floor(ls, undo_redo, owner)
	ensure_lights(ls, undo_redo, owner)


# -------------------------
# Helpers
# -------------------------

func _add_child_persistent(parent: Node, child: Node, undo_redo: EditorUndoRedoManager, owner: Node, action_name: String) -> void:
	if undo_redo != null:
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(parent, "add_child", child)
		undo_redo.add_undo_method(parent, "remove_child", child)
		undo_redo.add_do_method(child, "set_owner", owner)
		undo_redo.commit_action()
	else:
		parent.add_child(child)
		child.owner = owner


func _find_first_in_group_or_name(root: Node, group_name: String, expected_name: String) -> Node:
	if root == null:
		return null

	# Ricerca ricorsiva nel subtree della LivingScene
	return _find_first_rec(root, group_name, expected_name)


func _find_first_rec(n: Node, group_name: String, expected_name: String) -> Node:
	if n.is_in_group(group_name):
		return n
	if n.name == expected_name:
		return n

	for c in n.get_children():
		var found := _find_first_rec(c, group_name, expected_name)
		if found != null:
			return found
	return null
