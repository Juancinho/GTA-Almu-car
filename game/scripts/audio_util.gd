extends RefCounted

## Loads a sound even when the editor has not imported it yet (a fresh pull run
## straight from a script or shortcut): if the imported copy under .godot is
## missing, the original .wav/.ogg is read directly instead of failing with
## "Cannot open file res://.godot/imported/…".

static var _cache: Dictionary = {}


static func stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var result: AudioStream = null
	if _imported(path):
		result = load(path) as AudioStream
	if result == null and FileAccess.file_exists(path):
		var absolute := ProjectSettings.globalize_path(path)
		if path.get_extension().to_lower() == "wav":
			result = AudioStreamWAV.load_from_file(absolute)
		elif path.get_extension().to_lower() == "ogg":
			result = AudioStreamOggVorbis.load_from_file(absolute)
	if result == null:
		push_warning("Sound unavailable: " + path)
	_cache[path] = result
	return result


## True when the import metadata exists and points at a file that is present
## (always true in an exported build, where only imported copies ship).
static func _imported(path: String) -> bool:
	var meta := path + ".import"
	if not FileAccess.file_exists(meta):
		return ResourceLoader.exists(path)
	var config := ConfigFile.new()
	if config.load(meta) != OK:
		return true
	var target := str(config.get_value("remap", "path", ""))
	if target == "":
		for key in ["path.s3tc", "path.etc2"]:
			target = str(config.get_value("remap", key, ""))
			if target != "":
				break
	return target == "" or FileAccess.file_exists(target)
