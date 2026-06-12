@tool
extends RefCounted
class_name LivingEvent


enum TriggerType { CONDITION_CHECK, STARGATE_COLLIDED, BUTTON_HELD, ENVIRONMENT_CHANGED, END_VIDEO360 }

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
## The list of parameters for the action
var action_params: Array[String]
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



func check_preconditions() -> bool:
    return true



func exec_action() -> void:

    match self.action:

        ActionType.ACTIVATE_TRIGGER:
            # TODO
            print("Activating trigger...")

        ActionType.JUMP_TO_ENVIRONMENT:
            var target_env = self.action_params[0]
            print("Jumping to env ")
            LivingSceneManager.go_to_scene(target_env)

        ActionType.PLAY_VIDEO_360:
            var living_video360_item_id = self.action_params[0]
            var video_player: LivingVideo360 = null  # TODO: resolve reference
            video_player.seek(0)
            video_player.play()
