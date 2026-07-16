@tool
extends RefCounted
class_name CuratorBusyState

## Shared busy / error flags for the dock (download, create, restore, …).

signal changed

var is_busy: bool = false
var has_error: bool = false


func begin_work() -> void:
	is_busy = true
	has_error = false
	changed.emit()


func end_work(success: bool) -> void:
	is_busy = false
	has_error = not success
	changed.emit()


func set_error(error: bool) -> void:
	if has_error == error:
		return
	has_error = error
	changed.emit()
