@tool
extends RefCounted
class_name CuratorPipeline

# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------

# Fetch su un qualunque LivingItem + (se serve) download medium.
# Nota: LivingArea di solito non ha medium_uri, quindi è ok.
func scan_environment(env_root: LivingEnvironment) -> Array:
	
	var out: Array
	var level = 0
	
	scan_environment_R(env_root, out, level)
	
	return out

	
	
func scan_environment_R(n: LivingItem, accumulator: Array, level: int) -> void:

	accumulator.append({
		"name": n.name,
		"visible": n.is_visible_in_tree(),
		"nesting_level": level
		})
	
	var children = n.get_children()
	for c in children:
		if c is LivingItem:
			scan_environment_R(c, accumulator, level + 1)
