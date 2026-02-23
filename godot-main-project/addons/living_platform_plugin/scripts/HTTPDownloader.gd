## Support class to download files from URLs.
## If a NextCloud URL is detected, it is converted in its webdav equivalent to avoid redirects, which Godot doesn't support.
extends HTTPRequest

class_name HTTPDownloader

## The URL to download from
var public_url: String
## Directory where to store the data
var download_path: String
## Prefix added to the filename
var save_prefix: String
## The signal triggered when download is all successfull (both network download and file storage)
var success_signal: Signal
## The signal triggered when any error occurs
var error_signal: Signal


func _init(uri: String, save_path: String, save_prefix: String, success_signal: Signal, error_signal: Signal):
	self.public_url = uri
	self.download_path = save_path
	self.save_prefix = save_prefix
	self.success_signal = success_signal
	self.error_signal = error_signal


## Invoke this to really start the download process
func do_download():
	
	# If the link is a NextCloud share, convert it into a webdav link
	#if not public_url.contains("/public.php/dav/files/"):
	if public_url.contains("/s/"):
		print("Converting NextCloud URL '%s'" % public_url)
		var url_info := _parse_nextcloud_share_link(public_url)
		public_url = url_info['base_url'] + "/public.php/dav/files/" + url_info['token']

	print("Downloading media from URL '%s'..." % [public_url])
		
	# Connect one-shot callback (auto-disconnects after firing)
	self.request_completed.connect(
		_on_request_completed.bind(self),
		CONNECT_ONE_SHOT
	)
	
	print("Connected")
	
	# Issue GET request
	var err := self.request(public_url)
	print("Requested returns: ", err)
	if err != OK:
		self.queue_free()
		var msg = "HTTPRequest failed to start: %d" % err
		error_signal.emit(msg)

## Invoked asynchronously after the HTTP request has done. Mainly retrieves info and store the data into the specified directory path.
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	print("Request completed. Processing...")
	self.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS:
		var msg = "Download failed: result=%d, code=%d" % [result, response_code]
		error_signal.emit(msg)
		return
	
	if response_code != 200:
		var msg = "Server error: %d" % response_code
		error_signal.emit(msg)
		return
		
	#print("=== HEADERS ===")
	#for hline in headers:
		#print(hline)

	var media_type = _extract_content_type_from_headers(headers)
	var requested_filename = _extract_filename_from_headers(headers)
	if requested_filename == "":
		requested_filename = public_url.get_file()

	var new_media_filename = str(self.save_prefix) + requested_filename
	var new_media_path = self.download_path + "/" + new_media_filename

	# Prepare the sotring directory, if not already
	if not DirAccess.dir_exists_absolute(self.download_path):
		var err: Error = DirAccess.make_dir_recursive_absolute(self.download_path)
		if err != OK:
			var msg = "Failed to create %s: %s" % [self.download_path, error_string(err)]
			error_signal.emit(msg)
			return

	# Stream body to file in chunks (8192 bytes)
	var file := FileAccess.open(new_media_path, FileAccess.WRITE)
	if file == null:
		var msg = "Failed to open local file: %s" % new_media_path
		error_signal.emit(msg)
		return
	
	var chunk_size := 8192
	for i in range(0, body.size(), chunk_size):
		var end := mini(i + chunk_size, body.size())
		file.store_buffer(body.slice(i, end))
	
	file.close()
	
	print("Downloaded to %s" % new_media_path)

	# Needed to refresh the GUI when values or scene structure has changed
	# notify_property_list_changed()
	# emit_signal("download_media_success")
	success_signal.emit(new_media_filename, new_media_path, media_type)


static func _parse_nextcloud_share_link(shared_url: String) -> Dictionary:
	# Analyses a typical NextCloud share link.
	# Returns { "base_url": String, "token": String }
	# Example:
	# https://nextcloud.example.com/s/5ZK4QSbQGr9bktT
	# -> { "base_url": "https://nextcloud.example.com", "token": "5ZK4QSbQGr9bktT" }

	var url_regex := RegEx.new()
	url_regex.compile(r"^(https?)://([^/]+)(/.+)?$")  # Godot RegEx with raw string literal [web:2][web:4]
	var match := url_regex.search(shared_url)
	if match == null:
		push_error("Invalid URL: %s" % shared_url)
		return {}

	var scheme := match.get_string(1)
	var netloc := match.get_string(2)
	var path := match.get_string(3)
	if path == null:
		path = ""

	var parts := path.trim_prefix("/").trim_suffix("/").split("/")

	if parts.size() < 2 or parts[0] != "s":
		push_error("Unexpected share URL format: %s" % shared_url)
		return {}

	var token := parts[1]
	var base_url := "%s://%s" % [scheme, netloc]

	return {
		"base_url": base_url,
		"token": token,
	}


const CONTENT_TYPE_KEY = "Content-Type: "

static func _extract_content_type_from_headers(headers: PackedStringArray) -> String:
	
	var out: String = ""
	
	for header_line: String in headers:
		if header_line.begins_with(CONTENT_TYPE_KEY):
			out = header_line.substr(CONTENT_TYPE_KEY.length())
			break

	return out


static func _extract_filename_from_headers(headers: PackedStringArray) -> String:
	for header_line in headers:
		if "content-disposition" in header_line.to_lower():
			# Parse: "Content-Disposition: attachment; filename=\"example.png\""
			var regex := RegEx.new()
			regex.compile('filename[\\s]*=[\\s"]*([^";]+)')
			var match := regex.search(header_line)
			if match:
				return match.get_string(1).strip_edges().uri_decode()  # Decode URL-encoded chars
	return ""
