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
# RESET: rimuove i figli LivingItem dell'environment (UNDOABLE)
# ------------------------------------------------------------
func reset_environment_children(env: LivingEnvironment, undo_redo: EditorUndoRedoManager) -> void:
	if env == null:
		return

	# Prendiamo SOLO i LivingItem diretti (Area/Element) e li stacchiamo.
	# Il subtree (media, ecc.) rimane attaccato al root, quindi undo/redo lo riporta insieme.
	var roots: Array[Node] = []
	var indices: Array[int] = []
	for c in env.get_children():
		if c is LivingItem:
			roots.append(c)
			indices.append(c.get_index())

	if roots.is_empty():
		return

	var scene_owner := env.get_tree().edited_scene_root if Engine.is_editor_hint() else env.get_tree().current_scene
	# In editor, scene_owner dovrebbe essere il LivingEnvironment root della scena.

	# if undo_redo != null:
	# 	undo_redo.create_action("Svuota scena (Undoable)")

	# 	# DO: rimuovi i root dal parent (NON free)
	# 	for r in roots:
	# 		undo_redo.add_do_method(env, "remove_child", r)

	# 	# UNDO: riaggiungi i root allo stesso indice e ripristina owner su subtree
	# 	for i in range(roots.size()):
	# 		var r := roots[i]
	# 		var idx := indices[i]

	# 		undo_redo.add_undo_method(env, "add_child", r)
	# 		undo_redo.add_undo_method(env, "move_child", r, idx)

	# 		# Importantissimo: owner solo DOPO che il nodo è tornato nell'albero
	# 		undo_redo.add_undo_method(self, "_set_owner_recursive_safe", r, scene_owner)

	# 	undo_redo.commit_action()
	# else:
	for r in roots:
		env.remove_child(r)


# Imposta owner ricorsivamente, ma SOLO se owner è un antenato nel tree
# func _set_owner_recursive_safe(n: Node, owner: Node) -> void:
	# LivingUtils._set_owner_recursive(n, owner)


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
