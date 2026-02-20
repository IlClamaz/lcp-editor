@tool
extends RefCounted
class_name CuratorLayoutController

# ============================================================
# CuratorLayoutController
# ============================================================
# Layout + utilità geometriche (no UI, no DB).
# Aggiornato per:
# - LivingEnvironment come root
# - figli diretti: LivingArea + LivingElement (e potenzialmente altri)
# ============================================================


func cell_to_local_position(cell: String, spacing: float) -> Vector3:
	var c := cell.strip_edges().to_upper()
	if c.length() < 2:
		return Vector3.ZERO

	var col_char := c[0]
	var col := int(col_char.unicode_at(0) - "A".unicode_at(0))
	col = clamp(col, 0, 25)

	var row_str := c.substr(1)
	var row := int(row_str) - 1
	row = max(row, 0)

	return Vector3(col * spacing, 0.0, row * spacing)


# ------------------------------------------------------------
# RESET: elimina i figli LivingItem dell'environment
# ------------------------------------------------------------
func reset_environment_children(env: LivingEnvironment, undo_redo: EditorUndoRedoManager) -> void:
	if env == null:
		return

	var to_delete: Array[Node] = []
	for c in env.get_children():
		if c is LivingItem:
			# (opzionale) se vuoi preservare setup/player/floor/lights: filtra qui
			to_delete.append(c)

	if to_delete.is_empty():
		return

	if undo_redo != null:
		undo_redo.create_action("Reset Environment Children (LivingItem)")
		for n in to_delete:
			undo_redo.add_do_method(n, "queue_free")
		undo_redo.commit_action()
	else:
		for n in to_delete:
			n.queue_free()


# ------------------------------------------------------------
# AUTO LAYOUT: posiziona SOLO i LivingElement diretti sotto env
# ------------------------------------------------------------
func auto_layout_environment_elements(
	env: LivingEnvironment,
	spacing: float,
	cols: int,
	undo_redo: EditorUndoRedoManager
) -> void:
	if env == null:
		return

	var ccols := max(cols, 1)

	var elems: Array[LivingElement] = []
	for c in env.get_children():
		if c is LivingElement:
			elems.append(c as LivingElement)

	if elems.is_empty():
		return

	if undo_redo != null:
		undo_redo.create_action("Auto layout LivingElements (Environment)")
		for i in range(elems.size()):
			var le := elems[i] as Node3D
			var col = i % ccols
			var row = i / ccols
			var target := Vector3(col * spacing, 0.0, row * spacing)

			undo_redo.add_do_method(le, "set_position", target)
			undo_redo.add_undo_method(le, "set_position", le.position)
		undo_redo.commit_action()
	else:
		for i in range(elems.size()):
			var le := elems[i] as Node3D
			var col = i % ccols
			var row = i / ccols
			le.position = Vector3(col * spacing, 0.0, row * spacing)


# ------------------------------------------------------------
# (Opzionale) RESET SOLO ELEMENTS: utile se vuoi mantenere le aree
# ------------------------------------------------------------
func reset_environment_elements_only(env: LivingEnvironment, undo_redo: EditorUndoRedoManager) -> void:
	if env == null:
		return

	var to_delete: Array[Node] = []
	for c in env.get_children():
		if c is LivingElement:
			to_delete.append(c)

	if to_delete.is_empty():
		return

	if undo_redo != null:
		undo_redo.create_action("Reset Environment Elements (LivingElement)")
		for n in to_delete:
			undo_redo.add_do_method(n, "queue_free")
		undo_redo.commit_action()
	else:
		for n in to_delete:
			n.queue_free()
