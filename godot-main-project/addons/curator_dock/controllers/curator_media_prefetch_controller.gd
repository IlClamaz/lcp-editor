@tool
extends RefCounted
class_name CuratorMediaPrefetchController

signal _dummy_success(filename: String, path: String, type: String)
signal _dummy_error(reason: String)


func prefetch_scene_media(
	host: Node,
	local_scene_path: String,
	expected_env_id: int,
	omeka_base_url: String,
	media_cache_dir: String,
	remote_pwd: String,
	progress_cb: Callable = Callable()
) -> Dictionary:
	var item_ids := _extract_item_ids_from_scene(local_scene_path) 
	if expected_env_id > 0:
		item_ids = item_ids.filter(func(i): return int(i) != expected_env_id)

	var done := 0
	var total := item_ids.size()
	for iid in item_ids:  
		if host == null or not host.is_inside_tree():
			return {"ok": false, "item_ids": item_ids, "aborted": true}
		if progress_cb.is_valid():
			progress_cb.call("prefetch_item", done + 1, total, "Prefetch item %d/%d..." % [done + 1, total])

		var ok := await _prefetch_media_for_item(
			host,
			int(iid),
			omeka_base_url,
			media_cache_dir,
			remote_pwd
		)
		if not ok:
			push_warning("Prefetch media fallito per item %d" % int(iid))
		done += 1

	if progress_cb.is_valid():
		progress_cb.call("import_wait", 0, 0, "Import media in corso...")
	var imports_ready := await _wait_prefetched_glb_import_ready(host, item_ids, media_cache_dir, progress_cb)

	return {
		"ok": imports_ready,
		"item_ids": item_ids,
		"aborted": false
	}


func _extract_item_ids_from_scene(scene_path: String) -> Array[int]:
	var out: Array[int] = []
	if not FileAccess.file_exists(scene_path): return out

	var txt := FileAccess.get_file_as_string(scene_path)
	if txt == "": return out

	var rgx := RegEx.new()
	if rgx.compile("(?m)^\\s*item_id\\s*=\\s*(\\d+)\\s*$") != OK: return out

	var seen := {}
	for m in rgx.search_all(txt):
		var iid := int(m.get_string(1))
		if iid > 0 and not seen.has(iid):
			seen[iid] = true
			out.append(iid)
	return out

# ==============================================================================
# LA NUOVA LOGICA DI PREFETCH (CON CACHE E PROBE NEXTCLOUD)
# ==============================================================================
func _prefetch_media_for_item(
	host: Node,
	item_id: int,
	omeka_base_url: String,
	media_cache_dir: String,
	remote_pwd: String
) -> bool:
	if item_id <= 0: return true

	var item_data := await _fetch_item_media_data(host, item_id, omeka_base_url)
	if not item_data.get("ok", false): return false

	var medium_uri := str(item_data.get("medium_uri", ""))
	var thumb_uri := str(item_data.get("thumb_uri", ""))

	var item_dir := media_cache_dir.path_join(str(item_id))
	if not DirAccess.dir_exists_absolute(item_dir):
		DirAccess.make_dir_recursive_absolute(item_dir)

	var cache_path := item_dir.path_join("cache_info.json")
	var cache_data := _read_cache(cache_path)
	var local_fp := _build_media_fingerprint_from_cache(cache_data)

	var all_ok := true
	
	# --- SYNC MEDIUM PRINCIPALE ---
	if medium_uri != "" and not _looks_like_directory_medium_uri(medium_uri):
		var remote_fp = await _get_remote_fingerprint_async(host, medium_uri, remote_pwd)
		var file_exists = cache_data.get("media_path", "") != "" and FileAccess.file_exists(cache_data["media_path"])
		
		if not file_exists or (_has_valid_media_fingerprint(remote_fp) and not _media_fingerprint_equal(remote_fp, local_fp)):
			print("Prefetch %d: Media obsoleto o mancante. Avvio download..." % item_id)
			var dl_res = await _download_file_async(host, medium_uri, item_dir, str(item_id) + "-", remote_pwd)
			if dl_res.get("ok", false):
				remote_fp["media_path"] = dl_res["local_path"]
				remote_fp["media_type"] = dl_res["type"]
				_update_cache(cache_path, remote_fp)
				
				if dl_res["local_path"].get_extension().to_lower() == "zip":
					all_ok = all_ok and _prefetch_extract_zip_if_needed(dl_res["local_path"], item_dir)
			else:
				all_ok = false
		else:
			print("Prefetch %d: Cache file principale valida." % item_id)
			var main_path = cache_data.get("media_path", "")
			if main_path.get_extension().to_lower() == "zip":
				all_ok = all_ok and _prefetch_extract_zip_if_needed(main_path, item_dir)

	# --- SYNC THUMBNAIL ---
	if thumb_uri != "":
		var thumb_exists = cache_data.get("thumb_path", "") != "" and FileAccess.file_exists(cache_data["thumb_path"])
		if not thumb_exists or cache_data.get("thumb_source_uri", "") != thumb_uri:
			var dl_res = await _download_file_async(host, thumb_uri, item_dir, str(item_id) + "-thumbnail-", remote_pwd)
			if dl_res.get("ok", false):
				_update_cache(cache_path, {"thumb_path": dl_res["local_path"], "thumb_source_uri": thumb_uri})
			else:
				all_ok = false

	return all_ok


func _fetch_item_media_data(host: Node, item_id: int, omeka_base_url: String) -> Dictionary:
	var out := {"ok": false, "medium_uri": "", "thumb_uri": ""}
	var url := omeka_base_url.strip_edges().trim_suffix("/") + "/api/items?pretty_print=1&id=" + str(item_id)
	var response = await HTTPDownloader.request_json(host, url, 25.0)
	if not response.get("ok", false): return out

	var data = response.get("json", null)
	if typeof(data) != TYPE_ARRAY or data.is_empty(): return out

	var item = data[0]
	if typeof(item) != TYPE_DICTIONARY: return out

	var medium_uri := ""
	if item.has("lcp_form:has_URI"):
		var uri_array: Array = item["lcp_form:has_URI"]
		if not uri_array.is_empty() and typeof(uri_array[0]) == TYPE_DICTIONARY:
			var mu = uri_array[0].get("@id")
			if mu != null: medium_uri = str(mu)

	var thumb_uri := ""
	if item.has("thumbnail_display_urls"):
		var td = item["thumbnail_display_urls"]
		if typeof(td) == TYPE_DICTIONARY and td.has("square") and td["square"] != null:
			thumb_uri = str(td["square"])

	out = {"ok": true, "medium_uri": medium_uri, "thumb_uri": thumb_uri}
	return out

# ==============================================================================
# UTILITIES DI CACHE E DOWNLOAD (ALLINEATE A LIVING_ITEM.GD)
# ==============================================================================
func _get_fallback_media_type(path: String, header_type: String = "") -> String:
	if header_type != "" and header_type != "application/octet-stream": return header_type
	var ext = path.get_extension().to_lower()
	if ext in ["png"]: return "image/png"
	elif ext in ["jpg", "jpeg"]: return "image/jpeg"
	elif ext in ["txt"]: return "text/plain"
	elif ext in ["ogg", "ogv"]: return "video/ogg"
	elif ext in ["glb", "gltf"]: return "model/gltf-binary"
	elif ext in ["zip", "pck"]: return "application/zip"
	return "application/octet-stream"

func _get_remote_fingerprint_async(host: Node, uri: String, pwd: String) -> Dictionary:
	var probe_url = _get_probe_url_for_medium(uri)
	var head_res = await HTTPDownloader.request_head(host, probe_url, 10.0, pwd)
	var fp = _build_media_fingerprint_from_headers(head_res.get("headers", []))
	if not head_res.get("ok", false) or not _has_valid_media_fingerprint(fp):
		var get_res = await HTTPDownloader.request_probe_get(host, probe_url, 10.0, pwd)
		if get_res.get("ok", false):
			return _build_media_fingerprint_from_headers(get_res.get("headers", []))
	return fp

func _download_file_async(host: Node, uri: String, local_dir: String, prefix: String, pwd: String) -> Dictionary:
	var downloader := HTTPDownloader.new(uri, local_dir, prefix, _dummy_success, _dummy_error)
	downloader.remote_pwd = pwd.strip_edges()
	host.add_child(downloader)

	var result = {"ok": false, "local_path": "", "error": "", "type": ""}
	downloader.success_signal.connect(func(_fname, path, type):
		result["ok"] = true
		result["local_path"] = path
		result["type"] = _get_fallback_media_type(path, type)
	, CONNECT_ONE_SHOT)
	
	downloader.error_signal.connect(func(err): result["error"] = err, CONNECT_ONE_SHOT)
	downloader.do_download()

	while not result["ok"] and result["error"] == "":
		if not is_instance_valid(downloader) or downloader.is_queued_for_deletion():
			if result["error"] == "" and not result["ok"]: result["error"] = "Download interrotto."
			break
		await host.get_tree().process_frame

	return result

func _read_cache(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY: return parsed
	return {}

func _update_cache(path: String, new_data: Dictionary) -> void:
	var data = _read_cache(path)
	data.merge(new_data, true)
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f: 
		f.store_string(JSON.stringify(data))
		f.close()

func _looks_like_directory_medium_uri(uri: String) -> bool:
	if uri == "": return false
	if uri.contains("/public.php/dav/files/"):
		var marker := "/public.php/dav/files/"
		var idx := uri.find(marker)
		if idx == -1: return false
		var rest := uri.substr(idx + marker.length()).strip_edges().trim_suffix("/")
		return rest != "" and rest.split("/").size() == 1
	if uri.contains("/s/"):
		return not uri.ends_with("/download")
	return false

func _get_probe_url_for_medium(uri: String) -> String:
	if uri.contains("/s/"):
		var url_info := LivingUtils.parse_nextcloud_share_link(uri)
		if typeof(url_info) == TYPE_DICTIONARY and url_info.has("base_url") and url_info.has("token"):
			return str(url_info["base_url"]) + "/public.php/dav/files/" + str(url_info["token"])
	return uri

func _build_media_fingerprint_from_headers(headers: PackedStringArray) -> Dictionary:
	return {
		"media_remote_etag": _get_header_value(headers, "etag"),
		"media_remote_last_modified": _get_header_value(headers, "last-modified"),
		"media_remote_content_length": _get_header_value(headers, "content-length")
	}

func _build_media_fingerprint_from_cache(cache_data: Dictionary) -> Dictionary:
	return {
		"media_remote_etag": str(cache_data.get("media_remote_etag", "")).strip_edges(),
		"media_remote_last_modified": str(cache_data.get("media_remote_last_modified", "")).strip_edges(),
		"media_remote_content_length": str(cache_data.get("media_remote_content_length", "")).strip_edges()
	}

func _has_valid_media_fingerprint(fingerprint: Dictionary) -> bool:
	return (
		str(fingerprint.get("media_remote_etag", "")).strip_edges() != ""
		or str(fingerprint.get("media_remote_last_modified", "")).strip_edges() != ""
		or str(fingerprint.get("media_remote_content_length", "")).strip_edges() != ""
	)

func _media_fingerprint_equal(a: Dictionary, b: Dictionary) -> bool:
	var a_etag := str(a.get("media_remote_etag", "")).strip_edges()
	var b_etag := str(b.get("media_remote_etag", "")).strip_edges()
	var a_lm := str(a.get("media_remote_last_modified", "")).strip_edges()
	var b_lm := str(b.get("media_remote_last_modified", "")).strip_edges()
	var a_len := str(a.get("media_remote_content_length", "")).strip_edges()
	var b_len := str(b.get("media_remote_content_length", "")).strip_edges()

	# 1. Controlliamo PRIMA l'ETag, che è il dato più sicuro e assoluto
	if a_etag != "" and b_etag != "": 
		return a_etag == b_etag
		
	# 2. Se per qualche motivo manca l'ETag, usiamo la combinazione data + peso
	if a_lm != "" and b_lm != "" and a_len != "" and b_len != "": 
		return a_lm == b_lm and a_len == b_len
		
	# 3. Fallback disperati
	if a_lm != "" and b_lm != "": return a_lm == b_lm
	if a_len != "" and b_len != "": return a_len == b_len
	return false

func _get_header_value(headers: PackedStringArray, header_name: String) -> String:
	var prefix := header_name.to_lower() + ":"
	for h in headers:
		var line := str(h)
		var low := line.to_lower()
		if low.begins_with(prefix):
			return line.substr(line.find(":") + 1).strip_edges()
	return ""

# ==============================================================================
# VECCHIE FUNZIONI DI IMPORT E ZIP
# ==============================================================================
func _wait_prefetched_glb_import_ready(
	host: Node,
	item_ids: Array[int],
	media_cache_dir: String,
	progress_cb: Callable = Callable()
) -> bool:
	var glb_paths: Array[String] = []
	for iid in item_ids:
		var item_dir := media_cache_dir.path_join(str(int(iid)))
		_collect_files_with_extension_recursive(item_dir, "glb", glb_paths)
		_collect_files_with_extension_recursive(item_dir, "gltf", glb_paths)

	if glb_paths.is_empty():
		return true

	var fs := EditorInterface.get_resource_filesystem()
	for p in glb_paths:
		fs.update_file(p)

	if not fs.is_scanning():
		fs.scan()
	while fs.is_scanning():
		if host == null or not host.is_inside_tree():
			return false
		await host.get_tree().process_frame

	var loops := 0
	var max_loops := 1200
	var stable_ready_frames := 0
	while loops < max_loops:
		if host == null or not host.is_inside_tree():
			return false

		var pending := 0
		var total := glb_paths.size()
		for p in glb_paths:
			if not FileAccess.file_exists(p):
				pending += 1
				continue
			if not FileAccess.file_exists(p + ".import"):
				pending += 1

		if pending == 0 and not fs.is_scanning():
			stable_ready_frames += 1
			if stable_ready_frames >= 20:
				return true
		else:
			stable_ready_frames = 0

		if progress_cb.is_valid():
			progress_cb.call("import_wait_progress", total - pending, total, "Import media %d/%d..." % [total - pending, total])

		if loops % 60 == 0 and not fs.is_scanning():
			fs.scan()

		await host.get_tree().process_frame
		loops += 1

	return false

func _collect_files_with_extension_recursive(root_dir: String, ext: String, out_paths: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(root_dir): return
	var d := DirAccess.open(root_dir)
	if d == null: return

	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full_path := root_dir.path_join(name)
		if d.current_is_dir():
			if name != "." and name != "..":
				_collect_files_with_extension_recursive(full_path, ext, out_paths)
		else:
			if name.get_extension().to_lower() == ext.to_lower():
				out_paths.append(full_path)
		name = d.get_next()

func _prefetch_extract_zip_if_needed(zip_path: String, extraction_dir: String) -> bool:
	if zip_path == "": return true
	if not FileAccess.file_exists(zip_path): return false

	var entry_scene := extraction_dir.path_join("LivingEnvironmentTemplate.tscn")
	if FileAccess.file_exists(entry_scene): return true

	var zip := ZIPReader.new()
	var err := zip.open(zip_path)
	if err != OK:
		push_warning("Prefetch ZIP non valido: %s" % zip_path)
		return false

	if not DirAccess.dir_exists_absolute(extraction_dir):
		DirAccess.make_dir_recursive_absolute(extraction_dir)

	var zip_files := zip.get_files()
	var uid_regex := RegEx.new()
	uid_regex.compile(" uid=\"uid://[^\"]*\"")

	for file_name in zip_files:
		var content: PackedByteArray = zip.read_file(file_name)
		var out_path := extraction_dir.path_join(file_name)

		if file_name.ends_with(".tscn") or file_name.ends_with(".tres") or file_name.ends_with(".material"):
			var text := content.get_string_from_utf8()
			var modified := false
			if text.find("uid=\"uid://") != -1:
				text = uid_regex.sub(text, "", true)
				modified = true

			for dependency in zip_files:
				var original_path := "res://" + dependency
				var new_path := extraction_dir.path_join(dependency)
				if text.find(original_path) != -1:
					text = text.replace(original_path, new_path)
					modified = true

			if modified: content = text.to_utf8_buffer()

		var base_dir := out_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(base_dir):
			DirAccess.make_dir_recursive_absolute(base_dir)

		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			zip.close()
			push_warning("Prefetch ZIP: impossibile scrivere %s" % out_path)
			return false
		f.store_buffer(content)
		f.close()

	zip.close()
	return FileAccess.file_exists(entry_scene)