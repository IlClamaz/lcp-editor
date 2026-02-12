@tool
extends Node3D
class_name InteractableInfo

enum State { FAR, NEAR, CLOSE, INTERACT }

@export var info: InfoEntry

@export var near_distance := 4.0
@export var close_distance := 2.0

@export var interaction_action: StringName = &"interact"

@onready var area: Area3D = $ProximityArea
@onready var anchor: Marker3D = $CanvasAnchor
@onready var billboard: Sprite3D = $Billboard
@onready var panel: Control = $InfoViewport/InfoPanel

var _player: Node3D
var _state: State = State.FAR

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	_set_state(State.FAR)

func _process(_dt: float) -> void:
	if not _player:
		return

	# Posizionamento del billboard vicino all’oggetto
	billboard.global_transform.origin = anchor.global_transform.origin

	# Se vuoi che guardi sempre la camera (billboard)
	var cam := get_viewport().get_camera_3d()
	if cam:
		billboard.look_at(cam.global_transform.origin, Vector3.UP)

	# Calcolo stato in base alla distanza
	var d := global_transform.origin.distance_to(_player.global_transform.origin)

	var target: State
	if d > near_distance:
		target = State.FAR
	elif d > close_distance:
		target = State.NEAR
	else:
		# close
		target = (_state == State.INTERACT) if State.INTERACT else State.CLOSE

	if target != _state:
		_set_state(target)

func _unhandled_input(event: InputEvent) -> void:
	if not _player:
		return

	if event.is_action_pressed(interaction_action):
		if _state == State.CLOSE:
			_set_state(State.INTERACT)
		elif _state == State.INTERACT:
			# toggle / next page / close interact
			_set_state(State.CLOSE)

func _on_body_entered(body: Node) -> void:
	# Assumi che il player sia in un gruppo "player"
	if body is LivingCamera:
		_player = body as Node3D

func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
		_set_state(State.FAR)

func _set_state(s: State) -> void:
	_state = s

	match _state:
		State.FAR:
			billboard.visible = false
			_apply_text("")  # o nascondi panel
		State.NEAR:
			billboard.visible = true
			_apply_text(info.preview_text)
		State.CLOSE:
			billboard.visible = true
			_apply_text(info.extended_text)
		State.INTERACT:
			billboard.visible = true
			_apply_text(info.interact_text)

func _apply_text(t: String) -> void:
	# Qui dipende da com’è fatto InfoPanel
	# Esempio: InfoPanel contiene un RichTextLabel chiamato "Body"
	var body := panel.get_node_or_null("Body")
	if body and body is RichTextLabel:
		(body as RichTextLabel).text = t
