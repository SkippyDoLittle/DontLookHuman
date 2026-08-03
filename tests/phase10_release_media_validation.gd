extends SceneTree

const CAPTURE_SCRIPT_PATH: String = "res://tools/capture_gameplay_video.gd"
const TRAILER_PATH: String = "res://docs/gameplay_preview.avi"
const PACKAGE_SCRIPT_PATH: String = "res://tools/package_windows_release.ps1"
const FINALIZER_SCRIPT_PATH: String = "res://tools/finalize_trailer.ps1"
const SOUNDTRACK_SCRIPT_PATH: String = "res://tools/trailer_soundtrack.gd"

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	_validate_capture_contract()
	_validate_trailer_container()
	_validate_release_workflow()
	if _failures == 0:
		print("PHASE10_RELEASE_MEDIA_VALIDATION_OK")
	quit(_failures)

func _validate_capture_contract() -> void:
	var capture_script := load(CAPTURE_SCRIPT_PATH) as Script
	_check(capture_script != null, "Trailer capture script loads")
	if capture_script == null:
		return
	var constants := capture_script.get_script_constant_map()
	var duration := float(constants.get("TRAILER_SECONDS", 0.0))
	_check(is_equal_approx(duration, 33.0), "Trailer target is the 33-second hook-first cut")
	_check(int(constants.get("FPS", 0)) == 30, "Trailer capture targets 30 FPS")
	_check(
		String(constants.get("BRAND_IMAGE", "")) == "res://assets/branding/store_capsule.png",
		"Trailer uses the release store artwork"
	)
	_check(FileAccess.file_exists(String(constants.get("BRAND_IMAGE", ""))), "Trailer artwork exists")
	var shots: Array = constants.get("SHOT_SPECS", [])
	_check(shots.size() == 4, "Trailer includes four escalating gameplay sequences")
	for shot in shots:
		_check(
			shot is Dictionary and ResourceLoader.exists(String(shot.get("path", ""))),
			"Every trailer shot references a playable level"
		)
	_check(ResourceLoader.exists("res://tools/trailer_card.tscn"), "Trailer card scene exists")
	_check(ResourceLoader.exists(SOUNDTRACK_SCRIPT_PATH), "Original trailer soundtrack generator exists")

func _validate_trailer_container() -> void:
	_check(FileAccess.file_exists(TRAILER_PATH), "Release trailer file exists")
	if not FileAccess.file_exists(TRAILER_PATH):
		return
	var file := FileAccess.open(TRAILER_PATH, FileAccess.READ)
	_check(file != null, "Release trailer can be opened")
	if file == null:
		return
	var file_size := file.get_length()
	var header := file.get_buffer(mini(file_size, 4096))
	_check(file_size > 40 * 1024 * 1024, "Release trailer contains full-resolution media")
	_check(_fourcc(header, 0) == "RIFF" and _fourcc(header, 8) == "AVI ", "Trailer is a RIFF AVI")
	_check(int(header.decode_u32(4)) + 8 == file_size, "Trailer RIFF length is valid")

	var header_offset := _find_ascii(header, "avih", 0, header.size())
	_check(header_offset >= 0, "Trailer contains an AVI main header")
	if header_offset >= 0:
		var microseconds_per_frame := int(header.decode_u32(header_offset + 8))
		var total_frames := int(header.decode_u32(header_offset + 24))
		var width := int(header.decode_u32(header_offset + 40))
		var height := int(header.decode_u32(header_offset + 44))
		var duration_seconds := float(total_frames * microseconds_per_frame) / 1_000_000.0
		_check(microseconds_per_frame >= 33332 and microseconds_per_frame <= 33334, "Trailer is 30 FPS")
		_check(total_frames == 990, "Trailer contains the finalized 990-frame cut")
		_check(width == 1280 and height == 720, "Trailer is 1280 by 720")
		_check(duration_seconds >= 32.9 and duration_seconds <= 33.1, "Trailer runtime is 33 seconds")

	var tail_start := maxi(0, file_size - 100_000)
	file.seek(tail_start)
	var tail := file.get_buffer(file_size - tail_start)
	file.close()
	var index_offset := _find_ascii_reverse(tail, "idx1", 0)
	_check(index_offset >= 0, "Trailer contains an AVI index")
	if index_offset >= 0:
		var index_size := int(tail.decode_u32(index_offset + 4))
		_check(tail_start + index_offset + 8 + index_size == file_size, "Trailer index reaches the end of the file")
		_check(index_size % 16 == 0, "Trailer index has complete entries")
		var video_chunks := 0
		var audio_chunks := 0
		for entry_offset in range(index_offset + 8, tail.size(), 16):
			match _fourcc(tail, entry_offset):
				"00db":
					video_chunks += 1
				"01wb":
					audio_chunks += 1
		_check(video_chunks == 990, "Trailer index contains every video frame")
		_check(audio_chunks == 990, "Trailer index contains synchronized audio chunks")

func _validate_release_workflow() -> void:
	_check(FileAccess.file_exists(PACKAGE_SCRIPT_PATH), "Windows packaging script exists")
	_check(FileAccess.file_exists(FINALIZER_SCRIPT_PATH), "Trailer finalizer exists")
	var package_script := FileAccess.get_file_as_string(PACKAGE_SCRIPT_PATH)
	_check(package_script.contains("--export-release"), "Packaging performs a release export")
	_check(package_script.contains("Compress-Archive"), "Packaging creates a ZIP")
	_check(package_script.contains("SHA256"), "Packaging creates a SHA-256 checksum")
	_check(package_script.contains("does not match project version"), "Packaging prevents mismatched version labels")
	var finalizer_script := FileAccess.get_file_as_string(FINALIZER_SCRIPT_PATH)
	_check(
		finalizer_script.contains("$expectedFrames = 990")
		and finalizer_script.contains("cards=animated")
		and finalizer_script.contains("TRAILER_FINALIZE_OK"),
		"Trailer finalizer verifies the animated cut and synchronized audio"
	)

	var export_config := ConfigFile.new()
	_check(export_config.load("res://export_presets.cfg") == OK, "Windows export preset loads")
	var excluded := String(export_config.get_value("preset.0", "exclude_filter", ""))
	_check(
		excluded.contains("tools/*")
		and excluded.contains("tests/*")
		and excluded.contains("export/*"),
		"Release excludes development tools, tests, and generated exports"
	)
	_check(excluded.contains("assets/branding/store_capsule.png"), "Release excludes store-only artwork")

func _find_ascii(data: PackedByteArray, text: String, start: int, end: int) -> int:
	var needle := text.to_ascii_buffer()
	for offset in range(start, end - needle.size() + 1):
		if _matches(data, needle, offset):
			return offset
	return -1

func _find_ascii_reverse(data: PackedByteArray, text: String, start: int) -> int:
	var needle := text.to_ascii_buffer()
	for offset in range(data.size() - needle.size(), start - 1, -1):
		if _matches(data, needle, offset):
			return offset
	return -1

func _matches(data: PackedByteArray, needle: PackedByteArray, offset: int) -> bool:
	for index in needle.size():
		if data[offset + index] != needle[index]:
			return false
	return true

func _fourcc(data: PackedByteArray, offset: int) -> String:
	if offset < 0 or offset + 4 > data.size():
		return ""
	return data.slice(offset, offset + 4).get_string_from_ascii()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Phase 10 release-media validation failed: %s" % message)
