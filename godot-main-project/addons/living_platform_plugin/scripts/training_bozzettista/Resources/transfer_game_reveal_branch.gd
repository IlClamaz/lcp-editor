extends Resource
class_name TransferGameRevealBranch

@export_node_path("LivingElement") var when_element_visible: NodePath
@export var actions_if_true: Array[TransferGameRevealAction] = []
@export var actions_if_false: Array[TransferGameRevealAction] = []
