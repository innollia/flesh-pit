extends Node

## The vent being's recorded voice. Listens to FPVent.line_spoken and plays
## <voice_dir>/<line id>.ogg or .wav when there is one; without one the line
## is subtitle only. The next line, with or without a file, cuts the one
## playing. Reads files and hears the vent, changes nothing in the game; main
## connects the two signals below to the subtitles. The clip is flat, not at
## the vent: subtitles reach the player anywhere, the words have to as well.

signal voice_started(line_id: String, seconds: float)
signal voice_cut(line_id: String)

const BUS := &"Voice"
const VOICE_DIR := "res://audio/voice"
const EXTENSIONS := ["ogg", "wav"]
const WAV_EXTENSIBLE := 0xFFFE

var voice_dir := VOICE_DIR
## The line playing now, "" when quiet.
var current_id := ""
var player: AudioStreamPlayer

func _ready() -> void:
	FPSettings.ensure_buses()
	player = AudioStreamPlayer.new()
	player.name = "Line"
	player.bus = BUS
	add_child(player)
	player.finished.connect(func(): current_id = "")

func listen(vent: Node) -> void:
	if vent != null and vent.has_signal("line_spoken"):
		vent.connect("line_spoken", _on_line)

func _on_line(line_id: String) -> void:
	stop()
	var s := stream_for(line_id)
	if s == null:
		return
	current_id = line_id
	player.stream = s
	player.play()
	voice_started.emit(line_id, s.get_length())

func stop() -> void:
	var was := current_id
	current_id = ""
	player.stop()
	if was != "":
		voice_cut.emit(was)

## The clip for a line, null when there is none or it cannot be read. A file
## dropped in the folder is read as it is, so nothing has to import it first;
## an exported game has only the imported copy, which load() finds.
func stream_for(line_id: String) -> AudioStream:
	for ext in EXTENSIONS:
		var path := "%s/%s.%s" % [voice_dir, line_id, ext]
		var s: AudioStream = null
		if FileAccess.file_exists(path):
			s = _read(path, ext)
		elif ResourceLoader.exists(path):
			s = load(path) as AudioStream
		if s != null and s.get_length() > 0.0:
			return s
	return null

func _read(path: String, ext: String) -> AudioStream:
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	return AudioStreamWAV.load_from_buffer(plain_wav(FileAccess.get_file_as_bytes(path)))

## Editors and ffmpeg mark 24-bit WAV "extensible", which Godot refuses though
## the samples are plain PCM or float. Puts the real format in the header.
static func plain_wav(bytes: PackedByteArray) -> PackedByteArray:
	var pos := 12
	while pos + 8 <= bytes.size():
		var size := bytes.decode_u32(pos + 4)
		if bytes.slice(pos, pos + 4).get_string_from_ascii() == "fmt ":
			if size >= 26 and pos + 34 <= bytes.size() and bytes.decode_u16(pos + 8) == WAV_EXTENSIBLE:
				bytes.encode_u16(pos + 8, bytes.decode_u16(pos + 32))
			break
		pos += 8 + size + (size & 1)
	return bytes
