@tool
extends RefCounted
class_name LivingEvent


enum TriggerType { ENVIRONMENT_STATE_CHANGED, STARGATE_COLLIDED, BUTTON_HELD, ENVIRONMENT_CHANGED, END_VIDEO360 }

enum ActionType { ACTIVATE_TRIGGER, JUMP_TO_ENVIRONMENT, PLAY_VIDEO_360 }


## The containing environment
var environment_id: int
## The unique id of this event
var id: int

## The trigger_type, as constant from enumeration
var trigger_type: TriggerType
## The id of the item activating the trigger
var triggering_item_id: int
## The list of preconditions before ecxecuting the action
var preconditions: Array[String]

## The type of action when triggered
var action: ActionType
## The list of parameters for the action. Each parameter is a DB item
var action_params: Array[int]
## The list of effects to apply after the action is executed
var effects: Array[String]




func _resolve_source_id(source: Variant) -> int:
    if source is int:
        return int(source)
    if source is LivingPortal:
        return int((source as LivingPortal).target_environment_id)
    if source is LivingItem:
        return int((source as LivingItem).item_id)
    return 0
