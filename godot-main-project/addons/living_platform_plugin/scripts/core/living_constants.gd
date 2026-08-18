extends Resource

class_name LivingConstants

const SAVED_SCENES_FOLDER = "curated_scenes"

## Baked Omeka dynamic state vocabulary (ENTITY:VARIABLE:VALUE rows).
const STATE_JSON_PATH := "res://addons/living_platform_plugin/omeka_dynamic_properties_table.json"

## Max length for LivingItem.name derived from Omeka title.
const OMEKA_TITLE_MAX_LEN: int = 200
const OMEKA_DEFAULT_ITEM_TITLE: String = "Senza Titolo"

## Entry scene name inside extracted ModelloContenitore packages.
const LIVING_ENVIRONMENT_TEMPLATE_FILENAME: String = "LivingEnvironmentTemplate.tscn"

# ==============================================================================
# OMEKA JSON FIELD KEYS (API payload)
# ==============================================================================
const OMEKA_KEY_ID := "o:id"
const OMEKA_KEY_TITLE := "o:title"
const OMEKA_KEY_MODIFIED := "o:modified"
const OMEKA_KEY_RESOURCE_CLASS := "o:resource_class"
const OMEKA_KEY_THUMBNAIL_DISPLAY_URLS := "thumbnail_display_urls"
const OMEKA_KEY_THUMBNAIL_SQUARE := "square"
const OMEKA_KEY_AT_VALUE := "@value"
const OMEKA_KEY_AT_ID := "@id"
const OMEKA_KEY_VALUE_RESOURCE_ID := "value_resource_id"

const OMEKA_KEY_PARTICIPATORY_ITEM_TYPE := "lcp_form:has_participatory_item_type_f"
const OMEKA_KEY_COMPONENTS := "lcp_form:is_composed_of_f"
const OMEKA_KEY_AREAS := "lcp_form:has_participatory_area_f"
const OMEKA_KEY_URI := "lcp_form:has_URI"
const OMEKA_KEY_SHORT_TEXT := "lcp_form:has_short_text_f"
const OMEKA_KEY_LONG_TEXT := "lcp_form:has_long_text_f"
const OMEKA_KEY_CATALOGUE_TEXT := "lcp_form:has_catalogue_text_f"
const OMEKA_KEY_PARTICIPATORY_FORM_TYPE := "lcp_form:Participatory_item_form"

# ==============================================================================
# OMEKA EVENT FIELD KEYS (lcp_form-event)
# ==============================================================================
const OMEKA_KEY_EVENT_CLASS_TYPE := "lcp_form-event:Event"
const OMEKA_KEY_EVENT_ENVIRONMENT := "lcp_form-event:has_environment"
const OMEKA_KEY_EVENT_TRIGGER_TYPE := "lcp_form-event:has_trigger_type_f"
const OMEKA_KEY_EVENT_TRIGGER_ARG := "lcp_form-event:has_trigger_arg_f"
const OMEKA_KEY_EVENT_PRECONDITIONS := "lcp_form-event:has_trigger_preconditions_f"
const OMEKA_KEY_EVENT_ACTION_TYPE := "lcp_form-event:has_action_type_f"
const OMEKA_KEY_EVENT_ACTION_PARAMS := "lcp_form-event:has_action_params_f"
const OMEKA_KEY_EVENT_ACTION_EFFECTS := "lcp_form-event:has_action_effects_f"

# ==============================================================================
# OMEKA DYNAMIC PROPERTIES TABLE FIELD KEYS (lcp_form-event)
# ==============================================================================
const OMEKA_KEY_DYNAMIC_PROPERTIES_TABLE_TYPE := "lcp_form-event:Table_of_dynamic_properties"
const OMEKA_KEY_ITEM_OF_STATE_VARIABLE := "lcp_form-event:has_item_of_state_variable_f"
const OMEKA_KEY_VARIABLE_NAME := "lcp_form-event:has_variable_name_f"

# Friendly keys written into omeka_dynamic_properties_table.json
const OMEKA_META_DYNAMIC_TABLE_ID := "id"
const OMEKA_META_DYNAMIC_TABLE_TITLE := "title"
const OMEKA_META_ITEM_OF_STATE_VARIABLE_ID := "item_of_state_variable_id"
const OMEKA_META_VARIABLE_NAMES := "variable_names"

# ==============================================================================
# FRIENDLY META KEYS (OmekaTreePrefetcher → LivingItem)
# ==============================================================================
const OMEKA_META_ITEM_ID := "item_id"
const OMEKA_META_TITLE := "title"
const OMEKA_META_MODIFIED := "modified"
const OMEKA_META_SHORT_DESCRIPTION := "short_description"
const OMEKA_META_LONG_DESCRIPTION := "long_description"
const OMEKA_META_CATALOG_DESCRIPTION := "catalog_description"
const OMEKA_META_RESOURCE_CLASS := "resource_class"
const OMEKA_META_PARTICIPATORY_ITEM_TYPE := "participatory_item_type"
const OMEKA_META_COMPONENTS := "components"
const OMEKA_META_AREAS := "areas"
const OMEKA_META_MEDIUM_URI := "medium_uri"
const OMEKA_META_THUMBNAIL_URI := "thumbnail_uri"

# ==============================================================================
# PARTICIPATORY ITEM TYPE VALUES (Omeka)
# ==============================================================================
const PARTICIPATORY_TYPE_AMBIENTE := "Ambiente"
const PARTICIPATORY_TYPE_AREA := "Area"
const PARTICIPATORY_TYPE_IMMAGINE := "Immagine"
const PARTICIPATORY_TYPE_VIDEO := "Video"
const PARTICIPATORY_TYPE_VIDEO360 := "Video360"
const PARTICIPATORY_TYPE_OGGETTO := "Oggetto"
const PARTICIPATORY_TYPE_TARGET := "Target"
const PARTICIPATORY_TYPE_OGGETTO_ANIMATO := "OggettoAnimato"
const PARTICIPATORY_TYPE_CROWD := "Crowd"
const PARTICIPATORY_TYPE_MODELLO_CONTENITORE := "ModelloContenitore"
const PARTICIPATORY_TYPE_SLIDESHOW := "Slideshow"
const PARTICIPATORY_TYPE_STARGATE := "Stargate"
const PARTICIPATORY_TYPE_SUONO := "Suono"

# ==============================================================================
# EDITOR NODE META KEYS
# ==============================================================================
const META_IS_BORN := "is_born"
const META_EDIT_GROUP := "_edit_group_"
const META_EDIT_LOCK := "_edit_lock_"

## This is used to identify what items should be returned during a Cmaera Raycast.
## LivingObjects and LivingAreas add and remove themselves to the group.
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
const AUDIO_STARGATE_ACTIVATED = preload("res://addons/living_platform_plugin/audio/stargate.ogg") as AudioStreamOggVorbis
const AUDIO_SHORT_TEXT_IN = preload("res://addons/living_platform_plugin/audio/short_in.ogg") as AudioStreamOggVorbis
const AUDIO_SHORT_TEXT_OUT = preload("res://addons/living_platform_plugin/audio/short_out.ogg") as AudioStreamOggVorbis
const AUDIO_LONG_TEXT_IN = preload("res://addons/living_platform_plugin/audio/long_text_in.ogg") as AudioStreamOggVorbis
const AUDIO_LONG_TEXT_OUT = preload("res://addons/living_platform_plugin/audio/long_text_out.ogg") as AudioStreamOggVorbis
const AUDIO_SUCCESS = preload("res://addons/living_platform_plugin/audio/success.ogg") as AudioStreamOggVorbis
const AUDIO_FAILURE = preload("res://addons/living_platform_plugin/audio/failure.ogg") as AudioStreamOggVorbis
