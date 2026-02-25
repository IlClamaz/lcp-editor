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

	# Timer lives under the host (dock) so it actually runs in-editor
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = max(0.05, poll_interval_sec)
	_host.add_child(_timer)
	_timer.timeout.connect(_poll, CONNECT_DEFERRED)

	# Connect to everything currently in the tree (and we will also reconnect on poll)
	_connect_download_signals_recursive(_env)

	_timer.start()
	_poll() # immediate UI update

func stop() -> void:
	_running = false
	_env = null
	_env_instance_id = 0
	_host = null

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

	if total <= 0:
		# Nothing scheduled yet → keep at 0%
		progress_changed.emit(0, 0, 0)
		return

	var pct := int(round(float(_done) * 100.0 / float(total)))
	progress_changed.emit(pct, _done, total)

	# Stop as soon as we have no pending
	if pending == 0:
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
	# avoid reconnecting every poll
	if li.has_meta("_curator_dl_connected") and bool(li.get_meta("_curator_dl_connected")):
		return
	li.set_meta("_curator_dl_connected", true)

	# NOTE: signals exist in your LivingItem. If some child isn't a LivingItem, we never get here.
	if not li.download_media_success.is_connected(_on_any_download_done):
		li.download_media_success.connect(_on_any_download_done, CONNECT_DEFERRED)
	if not li.download_media_error.is_connected(_on_any_download_err):
		li.download_media_error.connect(_on_any_download_err, CONNECT_DEFERRED)

	if not li.download_thumbnail_success.is_connected(_on_any_download_done):
		li.download_thumbnail_success.connect(_on_any_download_done, CONNECT_DEFERRED)
	if not li.download_thumbnail_error.is_connected(_on_any_download_err):
		li.download_thumbnail_error.connect(_on_any_download_err, CONNECT_DEFERRED)

func _on_any_download_done(_filename: String, _path: String, _type: String) -> void:
	_done += 1
	# do not call _poll() directly too often; but it's fine
	_poll()

func _on_any_download_err(_reason: String) -> void:
	_done += 1
	_poll()

func _sum_pending_downloads(root: Node) -> int:
	var sum := 0

	if root is LivingItem:
		var li := root as LivingItem
		# We don't touch LivingItem. If getter exists, use it. Otherwise fallback 0.
		if li.has_method("get_pending_downloads"):
			sum += int(li.call("get_pending_downloads"))

	for c in root.get_children():
		sum += _sum_pending_downloads(c)

	return sum