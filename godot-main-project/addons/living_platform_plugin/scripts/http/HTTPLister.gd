## Lists files in a NextCloud shared folder using the WebDAV PROPFIND method.
## The NextCloud share URL is converted into its WebDAV equivalent.
## Uses StreamPeerTLS directly to issue a raw PROPFIND request, since Godot's
## HTTPRequest/HTTPClient do not expose PROPFIND in their Method enum.
extends Node

class_name HTTPLister

## The NextCloud share folder URL
var public_url: String
## The password for password-protected shares (leave empty if none)
var pwd: String
## Emitted on success with an Array[Dictionary] of file entries.
## Each dict contains: name, href, type ("file"|"folder"), size, modified, content_type
var success_signal: Signal
## Emitted on any error with a String message
var error_signal: Signal


func _init(uri: String, p_pwd: String, p_success: Signal, p_error: Signal):
	self.public_url = uri
	self.pwd = p_pwd
	self.success_signal = p_success
	self.error_signal = p_error


## Invoke this to start the listing process (must be called after add_child)
func do_list() -> void:
	if not public_url.begins_with("http://") and not public_url.begins_with("https://"):
		public_url = "https://" + public_url

	# Convert NextCloud share URL into a WebDAV folder URL
	var dav_url: String
	if public_url.contains("/public.php/dav/files/"):
		dav_url = public_url.trim_suffix("/") + "/"
	elif public_url.contains("/s/"):
		print("Converting NextCloud URL '%s'" % public_url)
		var url_info := LivingUtils.parse_nextcloud_share_link(public_url)
		if url_info.is_empty():
			queue_free()
			error_signal.emit("Failed to parse NextCloud share URL: '%s'" % public_url)
			return
		dav_url = url_info["base_url"] + "/public.php/dav/files/" + url_info["token"] + "/"
	else:
		queue_free()
		error_signal.emit("Not a valid NextCloud share URL: '%s'" % public_url)
		return

	print("Listing '%s'..." % dav_url)
	_do_propfind.call_deferred(dav_url)


func _do_propfind(dav_url: String) -> void:
	var url_parts := _parse_url(dav_url)
	if url_parts.is_empty():
		queue_free()
		error_signal.emit("Failed to parse DAV URL: '%s'" % dav_url)
		return

	var host: String = url_parts["host"]
	var port: int    = url_parts["port"]
	var path: String = url_parts["path"]
	var use_tls: bool = url_parts["scheme"] == "https"

	# Build the raw PROPFIND request
	var auth := Marshalls.utf8_to_base64("public:" + pwd)
	var body := (
		"""<?xml version="1.0" encoding="utf-8"?>"""
		+ """<d:propfind xmlns:d="DAV:">"""
		+ """<d:prop>"""
		+ """<d:displayname/>"""
		+ """<d:resourcetype/>"""
		+ """<d:getcontentlength/>"""
		+ """<d:getlastmodified/>"""
		+ """<d:getcontenttype/>"""
		+ """</d:prop>"""
		+ """</d:propfind>"""
	)
	var request_str := (
		"PROPFIND " + path + " HTTP/1.1\r\n"
		+ "Host: " + host + "\r\n"
		+ "Authorization: Basic " + auth + "\r\n"
		+ "Depth: 1\r\n"
		+ "Content-Type: application/xml; charset=utf-8\r\n"
		+ "Content-Length: " + str(body.to_utf8_buffer().size()) + "\r\n"
		+ "Connection: close\r\n"
		+ "\r\n"
		+ body
	)

	# --- TCP connection ---
	var tcp := StreamPeerTCP.new()
	var err := tcp.connect_to_host(host, port)
	if err != OK:
		queue_free()
		error_signal.emit("TCP connect failed: %d" % err)
		return

	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		await get_tree().process_frame
		tcp.poll()

	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		queue_free()
		error_signal.emit("TCP connection refused to '%s:%d'" % [host, port])
		return

	# --- Optional TLS handshake ---
	var peer: StreamPeer
	var tls: StreamPeerTLS
	if use_tls:
		tls = StreamPeerTLS.new()
		err = tls.connect_to_stream(tcp, host)
		if err != OK:
			queue_free()
			error_signal.emit("TLS connect failed: %d" % err)
			return
		while tls.get_status() == StreamPeerTLS.STATUS_HANDSHAKING:
			await get_tree().process_frame
			tls.poll()
		if tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			queue_free()
			error_signal.emit("TLS handshake failed (status=%d)" % tls.get_status())
			return
		peer = tls
	else:
		peer = tcp

	# --- Send request ---
	err = peer.put_data(request_str.to_utf8_buffer())
	if err != OK:
		queue_free()
		error_signal.emit("Failed to send request: %d" % err)
		return

	# --- Read response until connection closes ---
	var response_bytes := PackedByteArray()
	var timeout_frames := 600  # ~10 s at 60 fps
	
	while timeout_frames > 0:
		# 1. PRIMA facciamo il poll di rete
		if use_tls:
			tls.poll()
		tcp.poll()
		
		# 2. POI verifichiamo se il server ha chiuso la connessione nel frattempo
		var is_active = true
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			is_active = false
		if use_tls and tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			is_active = false
			
		if not is_active:
			break # Il server ha finito, usciamo in modo pulito
			
		# 3. SOLO ORA è sicuro leggere i byte senza ricevere errori rossi da mbedtls
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk := peer.get_data(available)
			if chunk[0] == OK:
				response_bytes.append_array(chunk[1])
			timeout_frames = 600  # reset on activity
		else:
			timeout_frames -= 1
			await get_tree().process_frame

	if response_bytes.is_empty():
		queue_free()
		error_signal.emit("Empty response from server")
		return

	# --- Parse HTTP response ---
	var header_end := _find_header_end(response_bytes)
	if header_end == -1:
		queue_free()
		error_signal.emit("Invalid HTTP response (no header boundary)")
		return

	var header_bytes := response_bytes.slice(0, header_end)
	var body_bytes   := response_bytes.slice(header_end + 4)
	var header_text  := header_bytes.get_string_from_utf8()
	var header_lines := header_text.split("\r\n")

	# Status line: "HTTP/1.1 207 Multi-Status"
	var status_code := header_lines[0].split(" ")[1].to_int() if header_lines.size() > 0 else 0

	# Detect chunked transfer encoding
	var is_chunked := false
	for line in header_lines:
		if line.to_lower().begins_with("transfer-encoding:") and "chunked" in line.to_lower():
			is_chunked = true
			break

	var xml_bytes := _decode_chunked(body_bytes) if is_chunked else body_bytes

	print("List request completed. code=%d, body=%d bytes" % [status_code, xml_bytes.size()])
	queue_free()

	if status_code != 207:
		error_signal.emit("Unexpected server response: %d" % status_code)
		return

	var files := _parse_propfind_response(xml_bytes.get_string_from_utf8(), dav_url)
	success_signal.emit(files)


# ---------------------------------------------------------------------------
# XML parsing
# ---------------------------------------------------------------------------

static func _parse_propfind_response(xml_text: String, base_dav_url: String) -> Array[Dictionary]:
	var files: Array[Dictionary] = []
	var parser := XMLParser.new()
	if parser.open_buffer(xml_text.to_utf8_buffer()) != OK:
		push_error("HTTPLister: failed to parse XML response")
		return files

	var base_path := _url_path(base_dav_url).trim_suffix("/")

	var current: Dictionary = {}
	var in_response := false
	var is_collection := false
	var current_tag := ""

	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := _strip_ns(parser.get_node_name())
				current_tag = tag
				match tag:
					"response":
						in_response = true
						current = {}
						is_collection = false
					"collection":
						if in_response:
							is_collection = true

			XMLParser.NODE_ELEMENT_END:
				var tag := _strip_ns(parser.get_node_name())
				if tag == "response" and in_response:
					in_response = false
					current_tag = ""
					if current.is_empty():
						continue
					var entry_path := _url_path(current.get("href", "")).trim_suffix("/")
					if entry_path == base_path:
						continue  # skip the folder itself
					current["type"] = "folder" if is_collection else "file"
					if not current.has("size"):
						current["size"] = 0
					files.append(current)
				else:
					current_tag = ""

			XMLParser.NODE_TEXT:
				if not in_response:
					continue
				var text := parser.get_node_data().strip_edges()
				if text.is_empty():
					continue
				match current_tag:
					"href":
						current["href"] = text
						current["name"] = text.uri_decode().trim_suffix("/").get_file()
					"displayname":
						current["displayname"] = text
					"getcontentlength":
						current["size"] = text.to_int()
					"getlastmodified":
						current["modified"] = text
					"getcontenttype":
						current["content_type"] = text

	return files


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _strip_ns(tag: String) -> String:
	return tag.get_slice(":", 1) if ":" in tag else tag


## Returns the byte offset of the first \r\n\r\n sequence, or -1.
static func _find_header_end(data: PackedByteArray) -> int:
	for i in range(data.size() - 3):
		if data[i] == 0x0D and data[i+1] == 0x0A and data[i+2] == 0x0D and data[i+3] == 0x0A:
			return i
	return -1


## Decodes an HTTP/1.1 chunked-encoded body.
static func _decode_chunked(data: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	var pos := 0
	while pos < data.size():
		# Find \r\n ending the chunk-size line
		var line_end := -1
		for i in range(pos, mini(pos + 20, data.size() - 1)):
			if data[i] == 0x0D and data[i+1] == 0x0A:
				line_end = i
				break
		if line_end == -1:
			break
		var size_str := data.slice(pos, line_end).get_string_from_utf8().split(";")[0].strip_edges()
		var chunk_size := size_str.hex_to_int()
		if chunk_size == 0:
			break
		pos = line_end + 2
		result.append_array(data.slice(pos, pos + chunk_size))
		pos += chunk_size + 2  # skip data + trailing \r\n
	return result


## Extracts the path (and query) component from a URL.
static func _url_path(url: String) -> String:
	var stripped := url
	var scheme_end := url.find("://")
	if scheme_end != -1:
		stripped = url.substr(scheme_end + 3)
	var slash := stripped.find("/")
	return stripped.substr(slash) if slash != -1 else "/"


## Parses a URL into { scheme, host, port, path }.
static func _parse_url(url: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile(r"^(https?)://([^/:]+)(?::(\d+))?(/.*)$")
	var m := regex.search(url)
	if m == null:
		push_error("HTTPLister: cannot parse URL: %s" % url)
		return {}
	var scheme := m.get_string(1)
	var host   := m.get_string(2)
	var port_s := m.get_string(3)
	var path   := m.get_string(4)
	var port: int = port_s.to_int() if port_s != "" else (443 if scheme == "https" else 80)
	return { "scheme": scheme, "host": host, "port": port, "path": path }
