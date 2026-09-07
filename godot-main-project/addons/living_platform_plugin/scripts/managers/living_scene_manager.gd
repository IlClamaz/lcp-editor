extends Node

## Singleton that manages scene transitions while preserving scene state across
## the session. Unlike change_scene_to_packed(), this manager removes the outgoing
## scene from the tree without freeing it, so its full state is restored when
## switching back to it.

## Set to false to always load a fresh scene instance (useful while debugging).
var scene_caching_enabled: bool = false

# Maps scene_file_path -> Node instance kept alive off-tree.
var _scene_cache: Dictionary = {}


func _ready() -> void:
	call_deferred("_refresh_events_on_startup")


func _refresh_events_on_startup() -> void:
	var current := get_tree().current_scene
	if current != null:
		_refresh_events_for_current_scene(current)


## Switch to a scene by [param target]:
## - [code]String[/code]: scene path (e.g. [code]res://.../scene.tscn[/code])
## - [code]int[/code]: Omeka environment id — resolves to the most recent saved scene.
func go_to_scene(target: Variant) -> void:
	var path := _resolve_scene_path(target)
	if path == "":
		return
	_do_switch.call_deferred(path)


func _resolve_scene_path(target: Variant) -> String:
	if typeof(target) == TYPE_INT or typeof(target) == TYPE_FLOAT:
		var environment_id := int(target)
		if environment_id <= 0:
			push_error("LivingSceneManager: invalid environment id %s." % str(target))
			return ""
		var path := LivingUtils.get_most_recent_scene(environment_id)
		if path == "":
			push_error("LivingSceneManager: no saved scene for environment id %d." % environment_id)
		else:
			print("LivingSceneManager: environment %d -> '%s'" % [environment_id, path])
		return path

	if typeof(target) == TYPE_STRING:
		var path := str(target).strip_edges()
		if path == "":
			push_error("LivingSceneManager: empty scene path.")
			return ""
		if path.begins_with("res://") and not ResourceLoader.exists(path):
			push_error("LivingSceneManager: scene not found at '%s'." % path)
			return ""
		return path

	push_error("LivingSceneManager: go_to_scene expects a scene path (String) or environment id (int).")
	return ""


func _do_switch(path: String) -> void:
	var root := get_tree().root
	var current := get_tree().current_scene

	if current != null:
		if scene_caching_enabled:
			var current_path := current.scene_file_path
			if current_path != "" and not _scene_cache.has(current_path):
				_scene_cache[current_path] = current
			root.remove_child(current)
		else:
			root.remove_child(current)
			current.queue_free()

	var next: Node
	if scene_caching_enabled and _scene_cache.has(path):
		next = _scene_cache[path]
		_scene_cache.erase(path)
		print("LivingSceneManager: restoring cached scene '%s'" % path)
	else:
		var packed: PackedScene = load(path)
		if packed == null:
			push_error("LivingSceneManager: failed to load scene '%s'" % path)
			return
		next = packed.instantiate()
		print("LivingSceneManager: loading scene '%s'" % path)

	root.add_child(next)
	get_tree().current_scene = next
	_refresh_events_for_current_scene.call_deferred(next)


# Load events baked into the scene's LivingEnvironment.omeka_events and print them.
func _refresh_events_for_current_scene(scene_root: Node) -> void:
	LivingEventManager.clear_events()

	if scene_root == null or not (scene_root is LivingEnvironment):
		return

	var env := scene_root as LivingEnvironment
	var result := LivingEventManager.load_for_environment(env)
	if not result.get("ok", false):
		push_warning("LivingSceneManager: event load failed: %s" % str(result.get("error", "unknown error")))

	LivingEventManager.notify_environment_changed(env.item_id)


## Get the root of the currently shown scene.
## The root should be of type LivingEnvironment
func get_current_scene() -> LivingEnvironment:
	var current := get_tree().current_scene
	if current is LivingEnvironment:
		return current

	# During scene switch, _ready() on the new scene may run before current_scene is assigned.
	var root := get_tree().root
	if root.get_child_count() > 0:
		var newest := root.get_child(root.get_child_count() - 1)
		if newest is LivingEnvironment:
			return newest

	return null
