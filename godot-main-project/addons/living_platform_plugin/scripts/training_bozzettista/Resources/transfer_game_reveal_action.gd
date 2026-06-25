extends Resource
class_name TransferGameRevealAction

enum Mode { SHOW, HIDE, HIDE_IF_VISIBLE }

@export_node_path("LivingElement") var element: NodePath
@export var mode: Mode = Mode.SHOW
