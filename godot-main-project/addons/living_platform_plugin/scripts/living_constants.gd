extends Resource

class_name LivingConstants

## The visibility of a LivingItem during the interaction
enum ItemVisibility {
	PRE_EXPERIENCE = 1,
	POST_EXPERIENCE = 2
}

## String versions of the ItemVisibility enumeration. Keep them aligned!
const ITEM_VISIBILITY_PRE_STR: String = "Pre-experience"
const ITEM_VISIBILITY_POST_STR: String = "Post-experience"

## This is used to retrieve the list of all elements in the scene via `get_tree().get_nodes_in_group(LIVING_ELEMENTS_GROUP_NAME)`
## LivingElements add and remove themselves to the group.
const LIVING_ELEMENTS_GROUP_NAME: String = "LivingElements"

## When loading a 3D model (glb) this is the name of the node that will be searched to support collisions of the camera ray and activate the visibility of the HUD
const LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE = "Face"
## The collisiuon layer for front faces
const LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER = 1 << 1


## When loading a 3D model (glb) this is the name of the node that will be searched to support collisions with the camera body and activate the visibility of the Caption for long text descriptions
const LIVING_3DMODEL_TRIGGER_COLLISION_NODE = "Trigger"
## The collision layer for triggers
const LIVING_3DMODEL_TRIGGER_COLLISION_LAYER = 1 << 2
