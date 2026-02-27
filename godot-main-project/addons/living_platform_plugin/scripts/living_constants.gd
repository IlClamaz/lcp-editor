extends Resource

class_name LivingConstants

enum ItemVisibility {
	PRE_EXPERIENCE = 1,
	POST_EXPERIENCE = 2
}

# Keep this aligned!
const ITEM_VISIBILITY_PRE_STR: String = "Pre-experience"
const ITEM_VISIBILITY_POST_STR: String = "Post-experience"

# This is used to retrieve the list of all elements in the scene via `get_tree().get_nodes_in_group(LIVING_ELEMENTS_GROUP_NAME)`
# LivingElements add and remove themselves to the group.
const LIVING_ELEMENTS_GROUP_NAME: String = "LivingElements"
