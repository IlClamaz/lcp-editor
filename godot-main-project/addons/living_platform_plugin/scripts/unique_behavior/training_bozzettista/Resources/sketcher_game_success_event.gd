extends Resource
class_name SketcherGameSuccessEvent

## Matches the token source_key (e.g. img_1), same as living_image_keys / valid_pairs keys.
@export var source_key: String = ""
@export var always_actions: Array[SketcherGameRevealAction] = []
@export var branches: Array[SketcherGameRevealBranch] = []
