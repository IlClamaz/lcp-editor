@tool
extends RefCounted
class_name CuratorPipeline

# ============================================================
# CuratorPipeline
# ============================================================
# Responsabilità:
# - Orchestrare una "pipeline" standard per i LivingElement:
#     1) fetch_omeka_info() sul nodo (popola title, components, media_uri, ecc.)
#     2) instantiate_components() (crea figli LivingElement in base a components[])
#     3) sui figli: fetch_omeka_info() e download_media() quando necessario
#
# Questa classe NON conosce UI e NON gestisce Undo/Redo:
# è un helper puro che esegue chiamate su LivingElement e reagisce ai segnali.
#
# Nota importante:
# - fetch_omeka_info() è asincrona (usa HTTPRequest e segnali).
# - Quindi la pipeline deve "aspettare" la fine del fetch usando i segnali:
#     fetch_json_success / fetch_json_error
#
# Perché CONNECT_ONE_SHOT:
# - Evita accumulo di connessioni multiple nel tempo (memory leak / doppi trigger).
# - Garantisce che la callback venga eseguita una sola volta per chiamata.
# ============================================================


func hydrate_living_element_tree(root_el: LivingElement) -> void:
	# "Idrata" un LivingElement e la sua sotto-struttura:
	# - Scarica info del root dal DB (fetch)
	# - Instanzia i suoi componenti (LivingElement figli)
	# - Per ogni figlio: fetch + download media
	#
	# Tipico utilizzo:
	# - Quando importi una scena dal DB ("Istanzia scena da DB")
	# - Quando piazzi un nuovo elemento in scena e vuoi che si riempia automaticamente

	# 1) Fetch del root: popola campi come title, components, media_uri, ecc.
	#    Questo è necessario PRIMA di instantiate_components(), perché components[]
	#    arriva dal fetch.
	root_el.fetch_omeka_info()

	# 2) Quando il fetch del root termina con successo:
	#    - crea figli LivingElement dai componenti
	#    - avvia pipeline fetch+download su ciascun figlio
	root_el.fetch_json_success.connect(func():
		# 2a) crea i figli (LivingElement) in base a root_el.components
		root_el.instantiate_components()

		# 3) per ogni figlio LivingElement: fetch e download media se serve
		for c in root_el.get_children():
			if c is LivingElement:
				fetch_then_download_media(c as LivingElement)
	, CONNECT_ONE_SHOT)

	# Gestione errore fetch root:
	# - logghiamo un warning e non proseguiamo (senza components non possiamo creare figli)
	root_el.fetch_json_error.connect(func(reason: String):
		push_warning("Fetch root fallito (%s): %s" % [root_el.name, reason])
	, CONNECT_ONE_SHOT)


func fetch_then_download_media(le: LivingElement) -> void:
	# Pipeline semplificata per un singolo LivingElement "foglia" o figlio:
	# 1) fetch_omeka_info() per ottenere media_uri e metadata
	# 2) se media_uri è presente e non abbiamo già scaricato (media_path vuoto):
	#    chiamiamo download_media()
	#
	# Questo è utile perché:
	# - media_uri viene popolato dal fetch, quindi non possiamo scaricare prima
	# - download_media() è costosa: vogliamo farla solo se davvero necessaria

	# 1) fetch del living element (asincrono)
	le.fetch_omeka_info()

	# 2) quando fetch termina con successo:
	#    decidiamo se scaricare il media
	le.fetch_json_success.connect(func():
		# DownloadMedia SOLO se serve (idempotente):
		# - se media_uri è vuoto, non c'è nulla da scaricare
		# - se media_path è già pieno, significa che il file è già stato scaricato
		#   (o almeno che il nodo "pensa" di averlo già).
		#
		# Nota: questa condizione evita download duplicati e rallentamenti.
		if str(le.media_uri).strip_edges() != "" and str(le.media_path).strip_edges() == "":
			le.download_media()
	, CONNECT_ONE_SHOT)

	# Gestione errore fetch figlio:
	# - logghiamo un warning e non tentiamo download.
	le.fetch_json_error.connect(func(reason: String):
		push_warning("Fetch child fallito (#%d): %s" % [le.item_id, reason])
	, CONNECT_ONE_SHOT)
