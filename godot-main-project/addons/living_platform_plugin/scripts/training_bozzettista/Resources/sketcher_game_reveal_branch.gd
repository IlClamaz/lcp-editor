extends Resource
class_name SketcherGameRevealBranch

@export_node_path("LivingElement") var when_element_visible: NodePath
@export var actions_if_true: Array[SketcherGameRevealAction] = []
@export var actions_if_false: Array[SketcherGameRevealAction] = []
