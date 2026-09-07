extends Resource
class_name SketcherGameRevealAction

enum Mode { SHOW, HIDE, HIDE_IF_VISIBLE }

@export_node_path("LivingObject") var element: NodePath
@export var mode: Mode = Mode.SHOW
