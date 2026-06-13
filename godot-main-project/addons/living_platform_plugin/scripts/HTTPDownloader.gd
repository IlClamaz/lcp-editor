## Support class to download files from URLs.
## Converts NextCloud share links into WebDAV links and handles authentication.
extends HTTPRequest
class_name HTTPDownloader

const DOWNLOAD_TIMEOUT_SEC := 180.0

# ==============================================================================
# VARIABILI GLOBALI E SEGNALI
# ==============================================================================
var public_url: String
var download_path: String
var save_prefix: String
var remote_pwd: String = ""
var target_remote_file: String = "" 

var success_signal: Signal
var error_signal: Signal

# ==============================================================================
# INIZIALIZZAZIONE
# ==============================================================================
func _init(uri: String, save_path: String, prefix: String, success_sig: Signal, error_sig: Signal):
	public_url = uri
	download_path = save_path
	save_prefix = prefix
	success_signal = success_sig
	error_signal = error_sig

# ==============================================================================
# FLUSSO PRINCIPALE DI DOWNLOAD
# ==============================================================================
func do_download() -> void:
	if not public_url.begins_with("http://") and not public_url.begins_with("https://"):
		public_url = "https://" + public_url
	var headers: PackedStringArray = []
	var nc_token := ""
	
	# 1. Conversione link NextCloud in WebDAV
	if public_url.contains("/s/"):
		print("Converting NextCloud URL '%s'" % public_url)
		var url_info := LivingUtils.parse_nextcloud_share_link(public_url)
		public_url = url_info['base_url'] + "/public.php/dav/files/" + url_info['token']
		nc_token = str(url_info['token'])
		
		if target_remote_file != "":
			public_url += "/" + target_remote_file.uri_encode()

	# 2. Recupero token se l'URL era già WebDAV nativo
	if nc_token == "" and public_url.contains("/public.php/dav/files/"):
		nc_token = _extract_nextcloud_token_from_dav_url(public_url)
		if target_remote_file != "" and _is_nextcloud_dav_root_url(public_url):
			public_url = public_url.rstrip("/") + "/" + target_remote_file.uri_encode()

	# 3. Autenticazione (FIX 401: invia sempre se c'è un token, anche con pwd vuota)
	if nc_token != "":
		var auth_string = "%s:%s" % [nc_token, remote_pwd.strip_edges()]
		var auth_b64 = Marshalls.raw_to_base64(auth_string.to_utf8_buffer())
		headers.append("Authorization: Basic " + auth_b64)

	# 4. Anti-Cache per Nextcloud
	if _is_nextcloud_url(public_url):
		headers.append("Cache-Control: no-cache")
		headers.append("Pragma: no-cache")

	print("Downloading media from URL '%s'..." % [public_url])
		
	self.request_completed.connect(_on_request_completed.bind(self), CONNECT_ONE_SHOT)
	self.timeout = DOWNLOAD_TIMEOUT_SEC
	
	var err := self.request(public_url, headers)
	if err != OK:
		self.queue_free()
		error_signal.emit("HTTPRequest failed to start: %d" % err)


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, _http_request: HTTPRequest) -> void:
	self.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS:
		error_signal.emit("Download failed: result=%d, code=%d" % [result, response_code])
		return
	
	if response_code != 200:
		error_signal.emit("Server error: %d" % response_code)
		return

	# Quando abbiamo scaricato con successo...
	var media_type = _extract_content_type_from_headers(headers)
	var requested_filename = _extract_filename_from_headers(headers)
	if requested_filename == "": # In caso non ci sia il content-disposition...
		requested_filename = _extract_filename_from_url(public_url)

	var new_media_filename = save_prefix + requested_filename # es. 1768_Maciste.glb
	var new_media_path = download_path.path_join(new_media_filename) # Il path è il download_path + il filename

	if not DirAccess.dir_exists_absolute(download_path):
		var err: Error = DirAccess.make_dir_recursive_absolute(download_path)
		if err != OK:
			error_signal.emit("Failed to create %s: %s" % [download_path, error_string(err)])
			return

	var write_ok := _write_file_atomically_with_retry(new_media_path, body) # Scrive effettivamente sul filesystem
	if not write_ok:
		error_signal.emit("Failed to write local file (locked or in use): %s" % new_media_path)
		return
	
	success_signal.emit(new_media_filename, new_media_path, media_type) 
	# Restituisce al living_item, il nome con prefisso, il path e il type


# ==============================================================================
# SCRITTURA ATOMICA SICURA
# ==============================================================================
func _write_file_atomically_with_retry(target_path: String, body: PackedByteArray) -> bool:
	var tmp_path := "%s.part_%d" % [target_path, Time.get_ticks_usec()]

	# 1. Scrittura su file temporaneo a chunk per file di grandi dimensioni
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return false

	var chunk_size := 8192
	for i in range(0, body.size(), chunk_size):
		var end := mini(i + chunk_size, body.size())
		file.store_buffer(body.slice(i, end))
	file.close()

	# 2. Rename con retry per arginare lock transitori di sistema (es. Windows)
	var attempts := 20
	for _i in range(attempts):
		if FileAccess.file_exists(target_path):
			var rm_err := DirAccess.remove_absolute(target_path)
			if rm_err != OK and rm_err != ERR_DOES_NOT_EXIST:
				OS.delay_msec(60)
				continue

		var mv_err := DirAccess.rename_absolute(tmp_path, target_path)
		if mv_err == OK:
			return true

		OS.delay_msec(60)

	# 3. Fallback se un altro processo ha nel frattempo completato il salvataggio
	if FileAccess.file_exists(target_path):
		DirAccess.remove_absolute(tmp_path)
		return true

	DirAccess.remove_absolute(tmp_path)
	return false


# ==============================================================================
# METODI STATICI ASINCRONI (JSON E PROBE UNIFICATI)
# ==============================================================================
static func request_json(host: Node, url: String, timeout_sec: float = 25.0) -> Dictionary:
	if not url.begins_with("http://") and not url.begins_with("https://"):
		url = "https://" + url
	var out := {"ok": false, "result": -1, "response_code": 0, "headers": PackedStringArray(), "body": PackedByteArray(), "json": null, "error": ""}
	if host == null:
		out["error"] = "host null"
		return out

	var req := HTTPRequest.new()
	host.add_child(req)
	req.timeout = timeout_sec
	
	if req.request(url) != OK:
		req.queue_free()
		out["error"] = "request start failed"
		return out

	var response = await req.request_completed
	req.queue_free()
	if response.size() < 4:
		out["error"] = "incomplete response"
		return out

	out["result"] = int(response[0])
	out["response_code"] = int(response[1])
	out["headers"] = response[2]
	out["body"] = response[3]

	if out["result"] != HTTPRequest.RESULT_SUCCESS or out["response_code"] < 200 or out["response_code"] >= 300:
		out["error"] = "http error"
		return out

	var json := JSON.new()
	if json.parse(out["body"].get_string_from_utf8()) != OK:
		out["error"] = "invalid json"
		return out

	out["ok"] = true
	out["json"] = json.get_data()
	return out


# Le due vecchie funzioni enormi ora re-indirizzano a un singolo core ottimizzato!
static func request_head(host: Node, url: String, timeout_sec: float = 10.0, remote_pwd: String = "") -> Dictionary:
	return await _internal_probe_request(host, url, timeout_sec, remote_pwd, HTTPClient.METHOD_HEAD)

static func request_probe_get(host: Node, url: String, timeout_sec: float = 12.0, remote_pwd: String = "") -> Dictionary:
	return await _internal_probe_request(host, url, timeout_sec, remote_pwd, HTTPClient.METHOD_GET)

static func _internal_probe_request(host: Node, url: String, timeout_sec: float, remote_pwd: String, method: int) -> Dictionary:
	if not url.begins_with("http://") and not url.begins_with("https://"):
		url = "https://" + url
	var out := {"ok": false, "result": -1, "response_code": 0, "headers": PackedStringArray(), "url": url, "error": ""}
	if host == null:
		out["error"] = "host null"
		return out

	var final_url := url
	var request_headers: PackedStringArray = []
	var nc_token := ""
	
	if final_url.contains("/s/"):
		var url_info := LivingUtils.parse_nextcloud_share_link(final_url)
		if typeof(url_info) == TYPE_DICTIONARY and url_info.has("base_url") and url_info.has("token"):
			nc_token = str(url_info["token"])
			final_url = str(url_info["base_url"]) + "/public.php/dav/files/" + nc_token
			
	if nc_token == "" and final_url.contains("/public.php/dav/files/"):
		nc_token = _extract_nextcloud_token_from_dav_url(final_url)
		
	# FIX 401 integrato
	if nc_token != "":
		var auth_string = "%s:%s" % [nc_token, remote_pwd.strip_edges()]
		var auth_b64 = Marshalls.raw_to_base64(auth_string.to_utf8_buffer())
		request_headers.append("Authorization: Basic " + auth_b64)

	if method == HTTPClient.METHOD_GET:
		request_headers.append("Range: bytes=0-0")
		
	if _is_nextcloud_url(final_url):
		request_headers.append("Cache-Control: no-cache")
		request_headers.append("Pragma: no-cache")

	var req := HTTPRequest.new()
	host.add_child(req) # QUESTA E STATICA, LO FA LEI SULL'HOST, QUELLA DEL DOWNLOAD NO!!
	req.timeout = timeout_sec
	
	if req.request(final_url, request_headers, method) != OK:
		req.queue_free()
		out["error"] = "request start failed"
		return out

	var response = await req.request_completed
	req.queue_free()
	
	if response.size() < 3:
		out["error"] = "incomplete response"
		return out

	out["result"] = int(response[0])
	out["response_code"] = int(response[1])
	out["headers"] = response[2]
	out["url"] = final_url
	
	var is_success = out["result"] == HTTPRequest.RESULT_SUCCESS
	if method == HTTPClient.METHOD_GET:
		out["ok"] = is_success and (out["response_code"] == 200 or out["response_code"] == 206)
	else:
		out["ok"] = is_success and out["response_code"] >= 200 and out["response_code"] < 300
		
	if not out["ok"]:
		out["error"] = "http error: code %d" % out["response_code"]
	return out


# ==============================================================================
# PARSING E UTILITIES DI TESTO
# ==============================================================================
static func _extract_nextcloud_token_from_dav_url(url: String) -> String:
	var marker := "/public.php/dav/files/"
	var idx := url.find(marker)
	if idx == -1: return ""
	var rest := url.substr(idx + marker.length()).strip_edges().trim_suffix("/")
	if rest == "": return ""
	return str(rest.split("/")[0])

static func _is_nextcloud_dav_root_url(url: String) -> bool:
	var marker := "/public.php/dav/files/"
	var idx := url.find(marker)
	if idx == -1: return false
	var rest := url.substr(idx + marker.length()).strip_edges().trim_suffix("/")
	return rest != "" and rest.split("/").size() == 1

# il Content-Type indica il formato del file (es. image/png oppure model/gltf-binary). 
# Se trova questa riga, usa .substr(14) per "tagliare via" 
# i primi 14 caratteri (che sono esattamente le lettere della parola "content-type: ") e restituisce solo il resto.
static func _extract_content_type_from_headers(headers: PackedStringArray) -> String:
	for header_line in headers:
		if header_line.to_lower().begins_with("content-type: "):
			return header_line.substr(14).strip_edges()
	return ""

# "Trova la parola 'filename=', 
# ignora le virgolette, e cattura tutto il testo finché non trovi un'altra virgoletta o un punto e virgola".
static func _extract_filename_from_headers(headers: PackedStringArray) -> String:
	for header_line in headers:
		if "content-disposition" in header_line.to_lower():
			var regex := RegEx.new()
			regex.compile('filename[\\s]*=[\\s"]*([^";]+)')
			var match := regex.search(header_line)
			if match:
				return match.get_string(1).strip_edges().uri_decode()
	return ""

# Se non c'è il content-disposition, cerchiamo di capire il nome dall'url...
static func _extract_filename_from_url(url: String) -> String:
	var clean := url.split("?")[0].split("#")[0]
	return clean.get_file()

static func _is_nextcloud_url(url: String) -> bool:
	var u := url.to_lower()
	return u.contains("nextcloud.") or u.contains("/public.php/dav/files/") or u.contains("/s/")
