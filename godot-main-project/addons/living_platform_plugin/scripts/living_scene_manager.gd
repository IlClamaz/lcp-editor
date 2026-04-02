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
	if current != null:
		var current_path := current.scene_file_path
		if current_path != "" and not _scene_cache.has(current_path):
			_scene_cache[current_path] = current
		root.remove_child(current)

	# Retrieve cached instance or instantiate for the first time.
	var next: Node
	if _scene_cache.has(path):
		next = _scene_cache[path]
		_scene_cache.erase(path)
		print("LivingSceneManager: restoring cached scene '%s'" % path)
	else:
		var packed: PackedScene = load(path)
		if packed == null:
			push_error("LivingSceneManager: failed to load scene '%s'" % path)
			return
		next = packed.instantiate()
		print("LivingSceneManager: loading scene for the first time '%s'" % path)

	root.add_child(next)
	get_tree().current_scene = next
