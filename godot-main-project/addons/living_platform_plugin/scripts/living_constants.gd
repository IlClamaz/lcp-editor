extends Resource

class_name LivingConstants

const SAVED_SCENES_FOLDER = "curated_scenes"

## Baked Omeka dynamic state vocabulary (ENTITY:STATE rows).
const STATE_JSON_PATH := "res://addons/living_platform_plugin/omeka_dynamic_properties_table.json"

## The visibility of a LivingItem during the interaction
enum ItemVisibility {
	PRE_EXPERIENCE = 1,
	POST_EXPERIENCE = 2
}

## String versions of the ItemVisibility enumeration. Keep them aligned!
const ITEM_VISIBILITY_PRE_STR: String = "Pre-experience"
const ITEM_VISIBILITY_POST_STR: String = "Post-experience"

## This is used to identify what items should be returned during a Cmaera Raycast.
## LivingElements and LivingAreas add and remove themselves to the group.
const RAY_PICKABLE_GROUP_NAME: String = "RayPickableLivingItems"

## This is used to identify what nodes should block the ray casting.
## Any kind of object type can add itself (and remove), so that it will block the view of objects behind.
const RAY_PICK_BLOCK_VIEW_GROUP_NAME: String = "RayPickBlockingNode"


## When loading a 3D model (glb) this is the name of the node that will be searched to support collisions of the camera ray and activate the visibility of the HUD
const LIVING_3DMODEL_FRONT_FACE_COLLISION_NODE = "Face"
## The collisiuon layer for front faces
const LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER = 1 << 1

## When loading a 3D model (glb) this is the name of the node that will be searched to support collisions with the camera body and activate the visibility of the Caption for long text descriptions
const LIVING_3DMODEL_TRIGGER_COLLISION_NODE = "Trigger"
## The collision layer for triggers
const LIVING_3DMODEL_TRIGGER_COLLISION_LAYER = 1 << 2

## When loading a 3D model (glb) this is the name of the node that will be searched to support collisions of the camera ray and activate the visibility of the HUD
const LIVING_3DMODEL_VOLUME_COLLISION_NODE = "Volume"
## The collision layer for volumes
const LIVING_3DMODEL_VOLUME_COLLISION_LAYER = 1 << 3

## The collision layer index (1-32) used for the Player Character
const LIVING_PLAYER_COLLISION_LAYER_INDEX = 5

## The collision layer index (1-32) used for the Crowd Agents
const LIVING_CROWD_COLLISION_LAYER_INDEX = 6


#
# AUDIO SAMPLES
#
const AUDIO_PORTAL_ACTIVATED = preload("res://addons/living_platform_plugin/audio/stargate.wav") as AudioStreamWAV
const AUDIO_SHORT_TEXT_IN = preload("res://addons/living_platform_plugin/audio/short_in.wav") as AudioStreamWAV
const AUDIO_SHORT_TEXT_OUT = preload("res://addons/living_platform_plugin/audio/short_out.wav") as AudioStreamWAV
const AUDIO_LONG_TEXT_IN = preload("res://addons/living_platform_plugin/audio/long_text_in.wav") as AudioStreamWAV
const AUDIO_LONG_TEXT_OUT = preload("res://addons/living_platform_plugin/audio/long_text_out.wav") as AudioStreamWAV
