@tool
extends Resource
class_name LivingEvent


enum TriggerType { CONDITION_CHECK, STARGATE_COLLIDED, BUTTON_HELD, ENVIRONMENT_CHANGED, END_VIDEO360 }

enum ActionType { ACTIVATE_TRIGGER, JUMP_TO_ENVIRONMENT, PLAY_VIDEO_360 }


## The containing environment
@export var environment_id: int
## The unique id of this event
@export var id: int

## The trigger_type, as constant from enumeration
@export var trigger_type: TriggerType
## The id of the item activating the trigger
@export var triggering_item_id: int
## The list of preconditions before ecxecuting the action
@export var preconditions: Array[String] = []

## The type of action when triggered
@export var action: ActionType
## The list of parameters for the action. Each parameter is a DB item
@export var action_params: Array[int] = []
## The list of effects to apply after the action is executed
@export var effects: Array[String] = []
