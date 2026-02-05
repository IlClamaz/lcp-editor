extends Node
class_name AssetsManager
# Downloader/mounter di più .pck in sequenza

# === CONFIG ===
@export var save_dir: String = "user://packs/"
@export var auto_start_on_ready: bool = true
@export var replace_files: bool = true           # di default, i file nei pack più recenti overrideano i precedenti
@export var stop_on_error: bool = true           # se true interrompe la sequenza al primo errore

# Elenco pack da scaricare (in ordine). Ogni voce è un Dictionary con:
# { "url": String, "filename": String (opz., default ricavato da header/url), "sha256": String opz., "replace": bool opz. }
@export var packs: Array = [
	# {"url": "https://cdn.example.com/assets_base_v1.pck", "sha256": "", "replace": true},
	# {"url": "https://cdn.example.com/assets_patch_v2.pck", "sha256": "abcd1234...", "replace": true},
]

static var Instance: AssetsManager

# === SEGNALI ===
signal queue_started(total: int)
signal pack_download_started(index: int, total: int, url: String, filename: String)
signal pack_download_progress(index: int, received: int, total: int)   # total può essere 0 se sconosciuto
signal pack_completed(index: int, path: String, mounted: bool)
signal pack_failed(index: int, url: String, error: String)
signal queue_completed(success_count: int, fail_count: int)

# === RUNTIME ===
var _http: HTTPRequest
var _idx: int = -1
var _total: int = 0
var _current_spec: Dictionary = {}
var _current_temp_path: String = ""   # salvataggio streaming su file
var _success: int = 0
var _fail: int = 0

func _ready() -> void:
	if Instance and Instance != self:
		queue_free()
		return
	Instance = self
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	
	DirAccess.make_dir_recursive_absolute(save_dir)
	if auto_start_on_ready and packs.size() > 0:
		start_queue()

# Avvia la sequenza sui pack definiti in `packs`
func start_queue() -> void:
	_idx = -1
	_total = packs.size()
	_success = 0
	_fail = 0
	if _total == 0:
		emit_signal("queue_completed", 0, 0)
		return
	emit_signal("queue_started", _total)
	_process_next()

# Aggiungi un pack a runtime
func add_pack(url: String, filename := "", sha256 := "", replace = null) -> void:
	var d := {"url": url}
	if filename != "": d["filename"] = filename
	if sha256 != "": d["sha256"] = sha256
	if replace != null: d["replace"] = replace
	packs.append(d)

# === Interno ===
func _process_next() -> void:
	_idx += 1
	if _idx >= _total:
		print("queue completed " + str(_total) + " " + str(_success) + " " + str(_fail)) 
		emit_signal("queue_completed", _success, _fail)
		return

	_current_spec = packs[_idx]
	if not _current_spec.has("url"):
		_fail += 1
		emit_signal("pack_failed", _idx, "", "Spec priva di 'url'")
		if stop_on_error: 
			emit_signal("queue_completed", _success, _fail)
			return
		_process_next()
		return

	var url: String = str(_current_spec["url"])
	var filename = _current_spec.get("filename", _infer_filename_from_url(url))
	if not filename.ends_with(".pck"):
		filename += ".pck"

	# preparazione file temporaneo per stream (evita di tenere tutto in RAM)
	DirAccess.make_dir_recursive_absolute(save_dir)
	_current_temp_path = save_dir.path_join(filename + ".part")
	var final_path := save_dir.path_join(filename)

	# cancella eventuale .part precedente
	if FileAccess.file_exists(_current_temp_path):
		DirAccess.remove_absolute(_current_temp_path)

	_http.set_download_file(_current_temp_path)  # stream diretto a file
	var err := _http.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		_fail += 1
		var msg := "Impossibile avviare la richiesta: %s" % err
		push_error(msg)
		emit_signal("pack_failed", _idx, url, msg)
		if stop_on_error:
			emit_signal("queue_completed", _success, _fail)
			return
		_process_next()
		return

	emit_signal("pack_download_started", _idx, _total, url, filename)

func _on_download_progress(downloaded: int, total: int) -> void:
	emit_signal("pack_download_progress", _idx, downloaded, total)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	# NOTA: con set_download_file, 'body' è vuoto; il contenuto è in _current_temp_path
	var url: String = str(_current_spec.get("url", ""))
	var filename = _current_spec.get("filename", _infer_filename_from_headers_or_url(headers, url))
	if not filename.ends_with(".pck"):
		filename += ".pck"
	var final_path := save_dir.path_join(filename)

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		# pulizia .part
		if FileAccess.file_exists(_current_temp_path):
			DirAccess.remove_absolute(_current_temp_path)
		_fail += 1
		var msg := "Download fallito. result=%s, http=%s" % [result, response_code]
		push_error(msg)
		emit_signal("pack_failed", _idx, url, msg)
		if stop_on_error:
			emit_signal("queue_completed", _success, _fail)
			return
		_process_next()
		return

	# rinomina .part -> finale
	var ok_rename := DirAccess.rename_absolute(_current_temp_path, final_path) == OK
	if not ok_rename:
		# se rename non va, prova copia
		var moved := _move_part_to_final(_current_temp_path, final_path)
		if not moved:
			_fail += 1
			var msg2 := "Salvataggio fallito: %s" % final_path
			push_error(msg2)
			emit_signal("pack_failed", _idx, url, msg2)
			if stop_on_error:
				emit_signal("queue_completed", _success, _fail)
				return
			_process_next()
			return

	# verifica hash se presente
	var want_hash: String = str(_current_spec.get("sha256", ""))
	if want_hash.length() > 0:
		var got_hash := _file_sha256(final_path)
		if got_hash != want_hash:
			_fail += 1
			var msg3 := "Hash mismatch per %s: atteso %s, ottenuto %s" % [final_path, want_hash, got_hash]
			push_error(msg3)
			emit_signal("pack_failed", _idx, url, msg3)
			# file corrotto → rimuovi
			if FileAccess.file_exists(final_path):
				DirAccess.remove_absolute(final_path)
			if stop_on_error:
				emit_signal("queue_completed", _success, _fail)
				return
			_process_next()
			return

	# mount
	var replace := bool(_current_spec.get("replace", replace_files))
	var mounted := ProjectSettings.load_resource_pack(final_path, replace)
	if not mounted:
		_fail += 1
		var msg4 := "Mount PCK fallito: %s" % final_path
		push_error(msg4)
		emit_signal("pack_failed", _idx, url, msg4)
		if stop_on_error:
			emit_signal("queue_completed", _success, _fail)
			return
		_process_next()
		return

	_success += 1
	print("PCK montato: ", final_path, "  replace=", replace)
	emit_signal("pack_completed", _idx, final_path, mounted)
	_process_next()

# === Helpers ===

func _infer_filename_from_headers_or_url(headers: PackedStringArray, url: String) -> String:
	# Prova dal Content-Disposition
	for h in headers:
		var lower := h.to_lower()
		if lower.begins_with("content-disposition:"):
			var parts := lower.split("filename=")
			if parts.size() >= 2:
				var raw := parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
				if raw != "": return raw
	# fallback: ultimo segmento url
	return _infer_filename_from_url(url)

func _infer_filename_from_url(url: String) -> String:
	var no_query := url.split("?")[0].rstrip("/")
	var segs: PackedStringArray = no_query.split("/")
	if segs.size() > 0:
		var last := segs[segs.size() - 1]
		if last != "":
			return last
	return "remote_assets.pck"

func _file_sha256(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var bytes := f.get_buffer(f.get_length())
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(bytes)
	var digest: PackedByteArray = hc.finish()
	return digest.hex_encode()

func _move_part_to_final(part_path: String, final_path: String) -> bool:
	if not FileAccess.file_exists(part_path):
		return false
	var src := FileAccess.open(part_path, FileAccess.READ)
	if src == null:
		return false
	DirAccess.make_dir_recursive_absolute(final_path.get_base_dir())
	var dst := FileAccess.open(final_path, FileAccess.WRITE)
	if dst == null:
		return false
	dst.store_buffer(src.get_buffer(src.get_length()))
	dst.flush()
	dst.close()
	src.close()
	DirAccess.remove_absolute(part_path)
	return true
