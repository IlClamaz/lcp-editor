@tool
extends RefCounted
class_name CuratorLayoutController

# ============================================================
# CuratorLayoutController
# ============================================================
# Responsabilità:
# - Funzioni di "layout" e utilità geometriche per il dock.
# - Non gestisce UI, non gestisce DB: solo posizionamento e pulizia.
#
# Perché RefCounted:
# - È un "helper" riutilizzabile e leggero, senza dipendenze da Control.
# ============================================================


func cell_to_local_position(cell: String, spacing: float) -> Vector3:
	# Converte una cella tipo "A1", "B4", "Z10" in una posizione locale 3D.
	#
	# Convenzione usata dal plugin:
	# - Griglia sul piano XZ (Y resta 0)
	# - Colonna = lettera (A=0, B=1, ..., Z=25)
	# - Riga = numero (1=0, 2=1, ...)
	# - Spacing = distanza tra celle in unità Godot (metri se la scena è in scala reale)
	#
	# Esempi:
	# - "A1" con spacing 2.0 -> (0, 0, 0)
	# - "B1" -> (2, 0, 0)
	# - "A2" -> (0, 0, 2)
	#
	# Nota: al momento supporta solo colonne A..Z (26 colonne).

	var c := cell.strip_edges().to_upper()
	if c.length() < 2:
		# input troppo corto per essere valido (es. "A" o "")
		return Vector3.ZERO

	# --- Colonna (lettera) ---
	var col_char := c[0]
	var col := int(col_char.unicode_at(0) - "A".unicode_at(0))

	# clamp: se l'utente scrive qualcosa fuori range, evitiamo numeri assurdi
	col = clamp(col, 0, 25)

	# --- Riga (numero) ---
	# substring dal secondo carattere in poi (es. "10" se la cella è "A10")
	var row_str := c.substr(1)

	# convertiamo in int e trasformiamo in indice 0-based: "1" -> 0
	var row := int(row_str) - 1
	row = max(row, 0)

	# Posizione finale su XZ
	return Vector3(col * spacing, 0.0, row * spacing)


func reset_root_children(root_el: LivingElement, undo_redo: EditorUndoRedoManager) -> void:
	# Rimuove (queue_free) tutti i figli diretti di tipo LivingElement
	# sotto il root LivingElement.
	#
	# ATTENZIONE:
	# Questo è un reset "forte": elimina tutta la struttura figlia (LivingElement).
	# Non distingue tra "oggetti canonici da DB" e "duplicati piazzati manualmente".
	#
	# undo_redo:
	# Se disponibile, registra l'operazione in Undo/Redo di Godot.
	# Se null, esegue direttamente.

	if root_el == null:
		return

	# Raccolta dei nodi da eliminare (prima li mettiamo in lista, poi li processiamo)
	var to_delete: Array = []
	for c in root_el.get_children():
		if c is LivingElement:
			to_delete.append(c)

	if to_delete.is_empty():
		# niente da fare
		return

	if undo_redo != null:
		# Undo/Redo: ogni nodo viene queue_free nel "do"
		# Nota: qui non aggiungiamo "undo" perché ripristinare nodi freed è non banale.
		# (Per undo completo servirebbe serializzare e re-instanziare, o rimuovere senza free.)
		undo_redo.create_action("Reset Root Children (LivingElement)")
		for n in to_delete:
			undo_redo.add_do_method(n, "queue_free")
		undo_redo.commit_action()
	else:
		# Esecuzione diretta senza Undo/Redo
		for n in to_delete:
			n.queue_free()


func auto_layout(root_el: LivingElement, spacing: float, cols: int, undo_redo: EditorUndoRedoManager) -> void:
	# Dispone automaticamente i figli LivingElement del root in una griglia.
	#
	# Logica:
	# - prende tutti i figli diretti di tipo LivingElement (ordine corrente)
	# - li posiziona su XZ con:
	#     col = i % cols
	#     row = i / cols
	#     position = (col*spacing, 0, row*spacing)
	#
	# spacing:
	# - distanza tra elementi (celle)
	#
	# cols:
	# - numero di colonne prima di andare a capo (>= 1)
	#
	# undo_redo:
	# - se presente registra posizionamenti con undo/redo completo (do + undo)

	if root_el == null:
		return

	# garantiamo almeno 1 colonna
	var ccols := max(cols, 1)

	# Collezioniamo i figli LivingElement
	var kids: Array = []
	for c in root_el.get_children():
		if c is LivingElement:
			kids.append(c)

	if kids.is_empty():
		return

	if undo_redo != null:
		# Undo/Redo completo: per ogni nodo memorizziamo pos precedente e target
		undo_redo.create_action("Auto layout LivingElements")
		for i in range(kids.size()):
			var le := kids[i] as Node3D
			var col = i % ccols
			var row = i / ccols
			var target := Vector3(col * spacing, 0.0, row * spacing)

			# Do: posiziona
			undo_redo.add_do_method(le, "set_position", target)
			# Undo: ripristina la posizione precedente
			undo_redo.add_undo_method(le, "set_position", le.position)
		undo_redo.commit_action()
	else:
		# Esecuzione diretta senza Undo/Redo
		for i in range(kids.size()):
			var le := kids[i] as Node3D
			var col = i % ccols
			var row = i / ccols
			le.position = Vector3(col * spacing, 0.0, row * spacing)
