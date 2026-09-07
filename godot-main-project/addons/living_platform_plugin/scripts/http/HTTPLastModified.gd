## Fetches only the Last-Modified date of a file on a server, using a HEAD request (no body download).
## If a NextCloud share URL is detected, it is converted to its WebDAV equivalent.
extends HTTPRequest

class_name HTTPLastModified

## The URL to query
var public_url: String
## The signal triggered on success, emits (last_modified: String)
var success_signal: Signal
## The signal triggered on any error, emits (message: String)
var error_signal: Signal

var remote_pwd: String = ""
var target_remote_file: String = ""


#
# Usage example:
#
# var checker = HTTPLastModified.new(url, success_signal, error_signal)
# checker.remote_pwd = "optional_password"        # optional
# checker.target_remote_file = "scene.tscn"       # optional
# add_child(checker)
# checker.do_request()
#

func _init(uri: String, success_signal: Signal, error_signal: Signal):
	self.public_url = uri
	self.success_signal = success_signal
	self.error_signal = error_signal


## Invoke this to start the HEAD request
func do_request():
	var headers: PackedStringArray = []

	if public_url.contains("/s/"):
		print("HTTPLastModified: converting NextCloud URL '%s'" % public_url)
		var url_info := LivingUtils.parse_nextcloud_share_link(public_url)
		public_url = url_info['base_url'] + "/public.php/dav/files/" + url_info['token']

		if target_remote_file != "":
			public_url += "/" + target_remote_file.uri_encode()

		if remote_pwd != "":
			var auth_string = "%s:%s" % [url_info['token'], remote_pwd]
			var auth_b64 = Marshalls.raw_to_base64(auth_string.to_utf8_buffer())
			headers.append("Authorization: Basic " + auth_b64)

	print("HTTPLastModified: HEAD request to '%s'" % public_url)

	self.request_completed.connect(_on_request_completed, CONNECT_ONE_SHOT)

	var err := self.request(public_url, headers, HTTPClient.METHOD_HEAD)
	if err != OK:
		self.queue_free()
		error_signal.emit("HTTPLastModified: HEAD request failed to start: %d" % err)


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, _body: PackedByteArray) -> void:
	self.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		error_signal.emit("HTTPLastModified: request failed: result=%d, code=%d" % [result, response_code])
		return

	if response_code != 200:
		error_signal.emit("HTTPLastModified: server error: %d" % response_code)
		return

	var last_modified := ""
	for header_line: String in headers:
		if header_line.to_lower().begins_with("last-modified:"):
			last_modified = header_line.substr("last-modified:".length()).strip_edges()
			break

	if last_modified == "":
		error_signal.emit("HTTPLastModified: Last-Modified header not found in response")
		return

	print("HTTPLastModified: Last-Modified = %s" % last_modified)
	success_signal.emit(last_modified)
