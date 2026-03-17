@tool
extends RefCounted
class_name CuratorDownloadProgress

signal progress_changed(pct: int, done: int, total: int)
signal finished(done: int, total: int)
signal aborted(reason: String)

var _timer: Timer = null
var _host: Node = null
var _env: LivingEnvironment = null
var _env_instance_id: int = 0

var _done: int = 0
var _running: bool = false

# Build guard: non fermarti finché il rebuild non è finito
var _build_finished: bool = false
var _build_success: bool = true

# Evita reconnect continui, senza sporcare i nodi con meta
var _connected_iids: Dictionary = {} # iid -> true

# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------
func reset() -> void:
	_done = 0

func start(env: LivingEnvironment, host: Node, poll_interval_sec: float = 0.15) -> void:
	stop()

	if env == null or host == null:
		aborted.emit("start called with null env/host")
		return

	_env = env
	_env_instance_id = env.get_instance_id()
	_host = host
	_running = true

	_done = 0
	_build_finished = false
	_build_success = true
	_connected_iids.clear()

	# Timer lives under the host (dock) so it actually runs in-editor
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = max(0.05, poll_interval_sec)
	_host.add_child(_timer)
	_timer.timeout.connect(_poll, CONNECT_DEFERRED)

	# Connect to everything currently in the tree (and we will also reconnect on poll)
	_connect_download_signals_recursive(_env)

	_timer.start()

# Chiamala dal dock quando env.rebuild_completed emette
func mark_build_finished(success: bool) -> void:
	_build_finished = true
	_build_success = success
	if not success:
		_emit_abort_and_stop("build_failed")

func stop() -> void:
	_running = false
	_env = null
	_env_instance_id = 0
	_host = null
	_build_finished = false
	_build_success = true
	_connected_iids.clear()

	if _timer != null:
		if _timer.timeout.is_connected(_poll):
			_timer.timeout.disconnect(_poll)
		_timer.stop()
		if is_instance_valid(_timer):
			_timer.queue_free()
	_timer = null

# ------------------------------------------------------------
# Internals
# ------------------------------------------------------------
func _poll() -> void:
	if not _running:
		return

	if _env == null or not is_instance_valid(_env):
		_emit_abort_and_stop("env no longer valid")
		return

	# If user switched to another scene/environment, abort silently
	if _env_instance_id != 0 and _env.get_instance_id() != _env_instance_id:
		_emit_abort_and_stop("env changed")
		return

	# New nodes appear during rebuild: connect them on the fly
	_connect_download_signals_recursive(_env)

	var pending := _sum_pending_downloads(_env)
	var total := _done + pending

	# Not scheduled yet → keep at 0%, BUT do not stop
	if total <= 0:
		progress_changed.emit(0, 0, 0)
		return

	var pct := int(round(float(_done) * 100.0 / float(total)))
	progress_changed.emit(pct, _done, total)

	# ✅ Stop SOLO quando il build è finito E non ci sono pending
	if _build_finished and pending == 0:
		finished.emit(_done, total)
		stop()

func _emit_abort_and_stop(reason: String) -> void:
	aborted.emit(reason)
	stop()

func _connect_download_signals_recursive(root: Node) -> void:
	if root == null:
		return

	if root is LivingItem:
		_connect_download_signals(root as LivingItem)

	for c in root.get_children():
		_connect_download_signals_recursive(c)

func _connect_download_signals(li: LivingItem) -> void:
	var iid := li.get_instance_id()
	if _connected_iids.has(iid):
		return
	_connected_iids[iid] = true

	# media success/error
	if not li.download_media_success.is_connected(_on_any_download_done):
		li.download_media_success.connect(_on_any_download_done, CONNECT_DEFERRED)
	if not li.download_media_error.is_connected(_on_any_download_err):
		li.download_media_error.connect(_on_any_download_err, CONNECT_DEFERRED)

	# thumbnail success/error
	if not li.download_thumbnail_success.is_connected(_on_any_download_done):
		li.download_thumbnail_success.connect(_on_any_download_done, CONNECT_DEFERRED)
	if not li.download_thumbnail_error.is_connected(_on_any_download_err):
		li.download_thumbnail_error.connect(_on_any_download_err, CONNECT_DEFERRED)

func _on_any_download_done(_filename: String, _path: String, _type: String) -> void:
	_done += 1
	_poll()

func _on_any_download_err(_reason: String) -> void:
	_done += 1
	_poll()

func _sum_pending_downloads(root: Node) -> int:
	var sum := 0

	if root is LivingItem:
		var li := root as LivingItem
		if li.has_method("get_pending_downloads"):
			sum += int(li.call("get_pending_downloads"))

	for c in root.get_children():
		sum += _sum_pending_downloads(c)

	return sum