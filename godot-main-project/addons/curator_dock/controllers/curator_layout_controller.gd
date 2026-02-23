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


# ------------------------------------------------------------
# RESET: elimina i figli LivingItem dell'environment
# ------------------------------------------------------------
func reset_environment_children(env: LivingEnvironment, undo_redo: EditorUndoRedoManager) -> void:
	if env == null:
		return

	var to_delete: Array[Node] = []
	for c in env.get_children():
		if c is LivingItem:
			# preserviamo Lights, Player e Floor (che non sono LivingItem) ma eliminiamo tutto il resto
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


func auto_layout_direct_elements(
	parent: Node,
	spacing: float,
	cols: int,
	undo_redo: EditorUndoRedoManager
) -> void:
	# Auto layout SOLO dei LivingElement figli DIRETTI del nodo parent.
	# parent può essere LivingEnvironment o LivingArea (o qualunque Node).
	if parent == null:
		return

	var ccols := max(cols, 1)

	# raccogli solo LivingElement diretti
	var elems: Array[LivingElement] = []
	for c in parent.get_children():
		if c is LivingElement:
			elems.append(c as LivingElement)

	if elems.is_empty():
		return

	# layout in griglia XZ, ancorata all'origine locale del parent
	# (0,0,0 è la "cella A1")
	if undo_redo != null:
		undo_redo.create_action("Auto layout LivingElements (Direct Children)")
		for i in range(elems.size()):
			var le := elems[i] as Node3D
			var col = i % ccols
			var row = i / ccols
			var target := Vector3(col * spacing, le.position.y, row * spacing) # preservo Y locale
			print("Auto-layout target for '%s': %s" % [le.name, target])
			undo_redo.add_do_method(le, "set_position", target)
			undo_redo.add_undo_method(le, "set_position", le.position)
		undo_redo.commit_action()
		print("Auto-layout eseguito su %d elementi (cols=%d, spacing=%.2f)" % [elems.size(), ccols, spacing])
	else:
		for i in range(elems.size()):
			var le := elems[i] as Node3D
			var col = i % ccols
			var row = i / ccols
			le.position = Vector3(col * spacing, le.position.y, row * spacing)
