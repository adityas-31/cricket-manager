class_name GameLog
extends RefCounted
## A local play log for reviewing play-tests later. Nothing is sent anywhere.
##
## Each session writes one JSON-lines file, user://logs/session-<date>-<time>.jsonl (on Windows
## %APPDATA%\Godot\app_userdata\Cricket Manager\logs\). Every line is one event:
## {"t": wall-clock time, "s": seconds into the session, "type": ..., ...details}.
## Engine and script errors and warnings are captured too, through a Godot Logger.
## Godot's own console log is also kept there (godot.log) by the project settings.
##
## Code anywhere calls GameLog.event("type", {...}); until start() is called (the app does it,
## tests don't) events are ignored.

## Tests point this elsewhere so they never mix with real play-test logs.
static var dir := "user://logs"
const KEEP_SESSIONS := 30

static var _file: FileAccess
static var _mutex := Mutex.new()
static var _started_msec := 0
static var path := ""


## Opens this session's log, removes old ones, and starts capturing errors.
static func start(details: Dictionary = {}) -> void:
	if _file:
		return
	DirAccess.make_dir_recursive_absolute(dir)
	_prune()
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	path = "%s/session-%s.jsonl" % [dir, stamp]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("GameLog: could not open %s" % path)
		return
	_started_msec = Time.get_ticks_msec()
	OS.add_logger(ErrorCapture.new())
	var info := {
		"game_version": ProjectSettings.get_setting("application/config/version", ""),
		"godot": Engine.get_version_info().string,
		"build": "debug" if OS.is_debug_build() else "release",
		"exported": not OS.has_feature("editor") and OS.has_feature("template"),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"locale": OS.get_locale(),
		"screen": str(DisplayServer.screen_get_size()),
		"user_dir": OS.get_user_data_dir(),
	}
	info.merge(details)
	event("session_start", info)


static func stop(details: Dictionary = {}) -> void:
	if _file == null:
		return
	event("session_end", details)
	_mutex.lock()
	_file.close()
	_file = null
	_mutex.unlock()


static func is_running() -> bool:
	return _file != null


## Records one event. Values should be JSON-friendly (numbers, strings, arrays, dictionaries).
static func event(type: String, details: Dictionary = {}) -> void:
	if _file == null:
		return
	var line := {"t": Time.get_datetime_string_from_system(), "s": snappedf((Time.get_ticks_msec() - _started_msec) / 1000.0, 0.1),
		"type": type}
	line.merge(details)
	_mutex.lock()
	_file.store_line(JSON.stringify(line))
	_file.flush()  # survive crashes
	_mutex.unlock()


static func _prune() -> void:
	var sessions := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.begins_with("session-"))
	sessions.sort()
	for i in maxi(sessions.size() - KEEP_SESSIONS + 1, 0):
		DirAccess.remove_absolute("%s/%s" % [dir, sessions[i]])


## Writes engine and script errors and warnings into the session log.
class ErrorCapture extends Logger:
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var kinds := {ERROR_TYPE_ERROR: "error", ERROR_TYPE_WARNING: "warning", ERROR_TYPE_SCRIPT: "script_error",
			ERROR_TYPE_SHADER: "shader_error"}
		var trace := []
		for bt in script_backtraces:
			for i in bt.get_frame_count():
				trace.append("%s:%d %s" % [bt.get_frame_file(i), bt.get_frame_line(i), bt.get_frame_function(i)])
		GameLog.event(kinds.get(error_type, "error"), {"message": rationale if rationale != "" else code,
			"code": code, "where": "%s:%d %s" % [file, line, function], "backtrace": trace})

	func _log_message(message: String, error: bool) -> void:
		if error:
			GameLog.event("stderr", {"message": message.strip_edges()})
