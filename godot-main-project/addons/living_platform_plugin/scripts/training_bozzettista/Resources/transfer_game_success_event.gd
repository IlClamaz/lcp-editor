extends Resource
class_name TransferGameSuccessEvent

## Matches the token source key (e.g. img_1), same as living_image_keys / valid_pairs.
@export var source_key: String = ""
@export var always_actions: Array[TransferGameRevealAction] = []
@export var branches: Array[TransferGameRevealBranch] = []
