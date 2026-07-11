## Support class to upload files to a NextCloud shared folder using the WebDAV protocol.
## The NextCloud share URL is converted into its WebDAV equivalent to perform a PUT request.
extends HTTPRequest

class_name HTTPUploader

## The NextCloud share folder URL
var public_url: String
## The password to write the file
var pwd: String
## Local path of the file to upload
var file_path: String
## Name to use on the remote folder
var save_name: String
## The signal triggered when upload is successful
var success_signal: Signal
## The signal triggered when any error occurs
var error_signal: Signal


func _init(uri: String, pwd: String, file_path: String, save_name: String, success_signal: Signal, error_signal: Signal):
	self.public_url = uri
	self.pwd = pwd
	self.file_path = file_path
	self.save_name = save_name
	self.success_signal = success_signal
	self.error_signal = error_signal


## Invoke this to really start the upload process
func do_upload():
	if not public_url.begins_with("http://") and not public_url.begins_with("https://"):
		public_url = "https://" + public_url
	# Convert NextCloud share URL into a WebDAV PUT URL
	if not public_url.contains("/public.php/dav/files/"):
		if not public_url.contains("/s/"):
			self.queue_free()
			error_signal.emit("Not a valid NextCloud share URL: '%s'" % public_url)
			return
		print("Converting NextCloud URL '%s'" % public_url)
		var url_info := LivingUtils.parse_nextcloud_share_link(public_url)
		if url_info.is_empty():
			self.queue_free()
			error_signal.emit("Failed to parse NextCloud share URL: '%s'" % public_url)
			return
		public_url = url_info['base_url'] + "/public.php/dav/files/" + url_info['token']

	# Append the remote filename to the DAV folder URL
	var remote_url := public_url.trim_suffix("/") + "/" + save_name.uri_encode()

	print("Uploading '%s' to '%s'..." % [file_path, remote_url])

	# Read local file
	if not FileAccess.file_exists(file_path):
		self.queue_free()
		error_signal.emit("Local file not found: '%s'" % file_path)
		return

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		self.queue_free()
		error_signal.emit("Failed to open local file: '%s'" % file_path)
		return

	var body := file.get_buffer(file.get_length())
	file.close()

	# Build headers
	var content_type := _mime_type_from_filename(save_name)
	var auth := Marshalls.utf8_to_base64("public:" + pwd)
	var headers := PackedStringArray([
		"Content-Type: " + content_type,
		"Content-Length: " + str(body.size()),
		"Authorization: Basic " + auth,
	])

	# Connect one-shot callback
	self.request_completed.connect(
		_on_request_completed.bind(self, remote_url),
		CONNECT_ONE_SHOT
	)

	# Issue PUT request
	var err := self.request_raw(remote_url, headers, HTTPClient.METHOD_PUT, body)
	print("Upload request returns: ", err)
	if err != OK:
		self.queue_free()
		error_signal.emit("HTTPRequest failed to start: %d" % err)


## Invoked asynchronously after the HTTP request completes.
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, _http_request: HTTPRequest, remote_url: String) -> void:
	print("Upload request completed. result=%d, code=%d" % [result, response_code])
	self.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		error_signal.emit("Upload failed: result=%d, code=%d" % [result, response_code])
		return

	# WebDAV PUT returns 201 Created or 204 No Content on success
	if response_code != 201 and response_code != 204:
		error_signal.emit("Server error on upload: %d" % response_code)
		return

	print("Uploaded '%s' to '%s'" % [save_name, remote_url])
	success_signal.emit(save_name, remote_url)



static func _mime_type_from_filename(filename: String) -> String:
	var ext := filename.get_extension().to_lower()
	match ext:
		"jpg", "jpeg": return "image/jpeg"
		"png":         return "image/png"
		"gif":         return "image/gif"
		"webp":        return "image/webp"
		"mp4":         return "video/mp4"
		"webm":        return "video/webm"
		"mp3":         return "audio/mpeg"
		"ogg":         return "audio/ogg"
		"wav":         return "audio/wav"
		"pdf":         return "application/pdf"
		"json":        return "application/json"
		"txt":         return "text/plain"
		_:             return "application/octet-stream"
