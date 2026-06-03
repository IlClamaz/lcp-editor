extends Node

## Singleton that manages scene transitions while preserving scene state across
## the session. Unlike change_scene_to_packed(), this manager removes the outgoing
## scene from the tree without freeing it, so its full state is restored when
## switching back to it.

# Maps scene_file_path -> Node instance kept alive off-tree.
var _scene_cache: Dictionary = {}


## Switch to the scene at [param path].
## First call: loads and instantiates the packed scene.
## Subsequent calls: restores the cached instance with its full state intact.
func go_to_scene(path: String) -> void:
	_do_switch.call_deferred(path)


func _do_switch(path: String) -> void:
	var root := get_tree().root
	var current := get_tree().current_scene

	# Park the outgoing scene in the cache (keyed by its file path).
	# CACHING DISABLED: keep this block commented to force full scene reload on every transition.
	# if current != null:
	# 	var current_path := current.scene_file_path
	# 	if current_path != "" and not _scene_cache.has(current_path):
	# 		_scene_cache[current_path] = current
	# 	root.remove_child(current)

	# No-cache behavior: remove and free the outgoing scene.
	if current != null:
		root.remove_child(current)
		current.queue_free()

	# Retrieve cached instance or instantiate for the first time.
	var next: Node
	# CACHING DISABLED: keep this block commented to force full scene reload on every transition.
	# if _scene_cache.has(path):
	# 	next = _scene_cache[path]
	# 	_scene_cache.erase(path)
	# 	print("LivingSceneManager: restoring cached scene '%s'" % path)
	# else:
	# 	var packed: PackedScene = load(path)
	# 	if packed == null:
	# 		push_error("LivingSceneManager: failed to load scene '%s'" % path)
	# 		return
	# 	next = packed.instantiate()
	# 	print("LivingSceneManager: loading scene for the first time '%s'" % path)

	var packed: PackedScene = load(path)
	if packed == null:
		push_error("LivingSceneManager: failed to load scene '%s'" % path)
		return
	next = packed.instantiate()
	print("LivingSceneManager: loading fresh scene '%s'" % path)

	root.add_child(next)
	get_tree().current_scene = next
	_refresh_events_for_current_scene.call_deferred(next)


# Load events baked into the scene's LivingEnvironment.omeka_events and print them.
func _refresh_events_for_current_scene(scene_root: Node) -> void:
	LivingEventManager.clear_events()

	if scene_root == null or not (scene_root is LivingEnvironment):
		return

	var result := LivingEventManager.load_for_environment(scene_root as LivingEnvironment)
	if not result.get("ok", false):
		push_warning("LivingSceneManager: event load failed: %s" % str(result.get("error", "unknown error")))


## Get the root of the currently shown scene.
## The root should be of type LivingEnvironment
func get_current_scene() -> LivingEnvironment:
	var current := get_tree().current_scene
	if current is LivingEnvironment:
		return current
	return null
