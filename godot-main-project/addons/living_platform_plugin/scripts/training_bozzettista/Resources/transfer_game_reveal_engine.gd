extends RefCounted
class_name TransferGameRevealEngine


func apply_initial_visibility(owner: Node, elements: Array[TransferGameRevealElement]) -> void:
	for item in elements:
		if item == null:
			continue
		var element := _resolve_element(owner, item.element)
		if element != null:
			element.visible = item.start_visible


func apply_success_event(
	owner: Node,
	events: Array[TransferGameSuccessEvent],
	source_key: String,
	debug: bool = false
) -> void:
	if source_key.strip_edges() == "":
		return

	for event in events:
		if event == null or event.source_key != source_key:
			continue
		for action in event.always_actions:
			_apply_action(owner, action, debug)
		for branch in event.branches:
			_apply_branch(owner, branch, debug)
		if debug:
			print("TransferGameRevealEngine: applied success event for '%s'." % source_key)
		return

	if debug:
		push_warning("TransferGameRevealEngine: no success event for source_key '%s'." % source_key)


func _apply_branch(owner: Node, branch: TransferGameRevealBranch, debug: bool) -> void:
	if branch == null:
		return

	var watch_element := _resolve_element(owner, branch.when_element_visible)
	var use_true_path := watch_element != null and watch_element.is_visible_in_tree()
	var actions := branch.actions_if_true if use_true_path else branch.actions_if_false
	for action in actions:
		_apply_action(owner, action, debug)


func _apply_action(owner: Node, action: TransferGameRevealAction, debug: bool) -> void:
	if action == null:
		return
	var element := _resolve_element(owner, action.element)
	if element == null:
		return

	match action.mode:
		TransferGameRevealAction.Mode.SHOW:
			element.visible = true
		TransferGameRevealAction.Mode.HIDE:
			element.visible = false
		TransferGameRevealAction.Mode.HIDE_IF_VISIBLE:
			if element.is_visible_in_tree():
				element.visible = false

	if debug:
		print(
			"TransferGameRevealEngine: %s -> %s"
			% [TransferGameRevealAction.Mode.keys()[action.mode], element.name]
		)


func _resolve_element(owner: Node, path: NodePath) -> LivingElement:
	if owner == null or path.is_empty():
		return null

	var resolve_root: Node = owner
	var node_path := path
	if owner is TransferGameController:
		var area := (owner as TransferGameController).get_area_root()
		if area != null:
			resolve_root = area
			node_path = _path_relative_to_area(path)

	var node := resolve_root.get_node_or_null(node_path)
	if node is LivingElement and is_instance_valid(node):
		return node as LivingElement
	return null


func _path_relative_to_area(path: NodePath) -> NodePath:
	var path_text := str(path)
	if path_text.begins_with("../"):
		return NodePath(path_text.substr(3))
	if path_text.begins_with("./"):
		return NodePath(path_text.substr(2))
	return path
