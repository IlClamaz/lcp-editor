@tool
extends RefCounted
class_name CuratorEventsPanel

## Read-only Events tab: builds accordions from LivingEnvironment.omeka_events.
## Reuses CuratorDockUIBuilder.clear_events_list / add_event_accordion for chrome.

var events_list: VBoxContainer
var ui_builder: CuratorDockUIBuilder
var env_list: OptionButton


func bind_ui(_events_list: VBoxContainer, _ui_builder: CuratorDockUIBuilder) -> void:
	events_list = _events_list
	ui_builder = _ui_builder


func bind_env_list(_env_list: OptionButton) -> void:
	env_list = _env_list


func refresh(env: LivingEnvironment) -> void:
	if events_list == null or ui_builder == null:
		return

	ui_builder.clear_events_list(events_list)

	if env == null:
		_add_hint("Open an environment scene to see events.")
		return

	if env.omeka_events.is_empty():
		_add_hint("No events. Run RESTORE SAVED COMPONENTS and save the scene.")
		return

	var item_labels: Dictionary = _build_item_label_map(env)
	for event in env.omeka_events:
		if event == null:
			continue
		ui_builder.add_event_accordion(
			events_list,
			_event_accordion_title(event),
			_event_body_lines(event, env, item_labels)
		)


func _add_hint(text: String) -> void:
	var hint := Label.new()
	hint.text = text
	hint.modulate = Color(1, 1, 1, 0.55)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	events_list.add_child(hint)


func _event_accordion_title(event: LivingEvent) -> String:
	var title: String = event.title.strip_edges()
	if title != "":
		return title
	var trigger: String = str(LivingEvent.TriggerType.keys()[event.trigger_type])
	var action: String = str(LivingEvent.ActionType.keys()[event.action])
	return "#%d · %s → %s" % [event.id, trigger, action]


func _event_body_lines(event: LivingEvent, env: LivingEnvironment, item_labels: Dictionary = {}) -> PackedStringArray:
	var trigger: String = str(LivingEvent.TriggerType.keys()[event.trigger_type])
	var action: String = str(LivingEvent.ActionType.keys()[event.action])
	var trigger_item: String = _resolve_item_label(event.triggering_item_id, item_labels)

	var param_labels: PackedStringArray = []
	for param_id in event.action_params:
		param_labels.append(_resolve_item_label(int(param_id), item_labels))
	var params_text: String = "—"
	if not param_labels.is_empty():
		params_text = ", ".join(param_labels)

	var lines: PackedStringArray = PackedStringArray([
		"Trigger: %s · %s" % [trigger, trigger_item],
		"Action: %s · %s" % [action, params_text],
	])

	if event.preconditions.is_empty():
		lines.append("Preconditions: —")
	else:
		lines.append("Preconditions:")
		for p in event.preconditions:
			lines.append("  • %s" % p)

	if event.effects.is_empty():
		lines.append("Effects: —")
	else:
		lines.append("Effects:")
		for e in event.effects:
			lines.append("  • %s" % e)

	return lines


func _build_item_label_map(env: LivingEnvironment) -> Dictionary:
	var labels: Dictionary = {}
	if env == null:
		return labels

	var env_title: String = str(env.title).strip_edges()
	labels[int(env.item_id)] = env_title if env_title != "" else str(env.name)

	for node in env.find_children("*", "LivingItem", true, true):
		if not (node is LivingItem):
			continue
		var living := node as LivingItem
		var iid: int = int(living.item_id)
		if iid <= 0 or labels.has(iid):
			continue
		var item_title: String = str(living.title).strip_edges()
		labels[iid] = item_title if item_title != "" else str(living.name)
	return labels


func _resolve_item_label(item_id: int, item_labels: Dictionary = {}) -> String:
	if item_id <= 0:
		return "—"
	# 1) LivingItem / ambiente aperto in scena
	if item_labels.has(item_id):
		return str(item_labels[item_id])
	# 2) Lista environment del Curator Dock (utile per JUMP_TO_ENVIRONMENT)
	var dock_env_title: String = _resolve_env_title_from_dock(item_id)
	if dock_env_title != "":
		return dock_env_title
	# 3) fallback
	return "id %d" % item_id


func _resolve_env_title_from_dock(env_id: int) -> String:
	if env_list == null or env_id <= 0:
		return ""
	var idx: int = env_list.get_item_index(env_id)
	if idx < 0:
		return ""
	if env_list.is_item_disabled(idx):
		return ""
	return env_list.get_item_text(idx).strip_edges()
