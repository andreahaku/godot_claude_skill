@tool
class_name ScanHelper
extends RefCounted

## Debounced filesystem scan utility.
## Wraps EditorInterface.get_resource_filesystem().scan() with deduplication
## to avoid multiple scans per command batch.

const MIN_SCAN_INTERVAL_MS := 2000

var _editor_interface: EditorInterface
var _last_scan_time: int = 0


func _init(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface


func scan_if_needed() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_scan_time < MIN_SCAN_INTERVAL_MS:
		return false
	force_scan()
	return true


func force_scan() -> void:
	_last_scan_time = Time.get_ticks_msec()
	_editor_interface.get_resource_filesystem().scan()


func is_scanning() -> bool:
	return _editor_interface.get_resource_filesystem().is_scanning()
