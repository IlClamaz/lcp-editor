extends RefCounted
class_name SketcherGameRevealEngine


func apply_initial_visibility(owner: Node, elements: Array[SketcherGameRevealElement]) -> void:
	for item in elements:
		if item == null:
			continue
		var element := _resolve_element(owner, item.element)
		if element != null:
			element.visible = item.start_visible


func apply_success_event(
	owner: Node,
	events: Array[SketcherGameSuccessEvent],
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
			print("SketcherGameRevealEngine: applied success event for '%s'." % source_key)
		return

	if debug:
		push_warning("SketcherGameRevealEngine: no success event for source_key '%s'." % source_key)


func _apply_branch(owner: Node, branch: SketcherGameRevealBranch, debug: bool) -> void:
	if branch == null:
		return

	var watch_element := _resolve_element(owner, branch.when_element_visible)
	var use_true_path := watch_element != null and watch_element.is_visible_in_tree()
	var actions := branch.actions_if_true if use_true_path else branch.actions_if_false
	for action in actions:
		_apply_action(owner, action, debug)


func _apply_action(owner: Node, action: SketcherGameRevealAction, debug: bool) -> void:
	if action == null:
		return
	var element := _resolve_element(owner, action.element)
	if element == null:
		return

	match action.mode:
		SketcherGameRevealAction.Mode.SHOW:
			element.visible = true
		SketcherGameRevealAction.Mode.HIDE:
			element.visible = false
		SketcherGameRevealAction.Mode.HIDE_IF_VISIBLE:
			if element.is_visible_in_tree():
				element.visible = false

	if debug:
		print(
			"SketcherGameRevealEngine: %s -> %s"
			% [SketcherGameRevealAction.Mode.keys()[action.mode], element.name]
		)


func _resolve_element(owner: Node, path: NodePath) -> LivingObject:
	if owner == null or path.is_empty():
		return null

	var resolve_root: Node = owner
	var node_path := path
	if owner is SketcherGameController:
		var area := (owner as SketcherGameController).get_area_root()
		if area != null:
			resolve_root = area
			node_path = _path_relative_to_area(path)

	var node := resolve_root.get_node_or_null(node_path)
	if node is LivingObject and is_instance_valid(node):
		return node as LivingObject
	return null


func _path_relative_to_area(path: NodePath) -> NodePath:
	var path_text := str(path)
	if path_text.begins_with("../"):
		return NodePath(path_text.substr(3))
	if path_text.begins_with("./"):
		return NodePath(path_text.substr(2))
	return path
