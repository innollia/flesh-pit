class_name FDKSoundBank
extends RefCounted

## Loads a sound manifest and hands out streams.
##
## Manifest (JSON, written by game/tools/audio/build_audio.py or by hand):
##   {"version": 1,
##    "sounds": {"<id>": {"kind": "sfx"|"loop", "files": ["res://..."], "spatial": bool}},
##    "beds":   {"<bed name>": ["<loop id>", ...]}}
##
## pick(id) returns a random variation of a sound and never the same
## variation twice in a row. Loop sounds come back with loop_mode set.

const MANIFEST_VERSION := 1

var sounds: Dictionary = {}
var beds: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _last: Dictionary = {}
var _cache: Dictionary = {}

static func from_file(path: String) -> FDKSoundBank:
	var bank := FDKSoundBank.new()
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_warning("FDKSoundBank: manifest not found or empty: %s" % path)
		return bank
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("FDKSoundBank: manifest is not a JSON object: %s" % path)
		return bank
	bank.load_dict(data)
	return bank

func load_dict(data: Dictionary) -> void:
	sounds = data.get("sounds", {})
	beds = data.get("beds", {})
	_last.clear()
	_cache.clear()

func has(id: String) -> bool:
	return sounds.has(id)

func is_loop(id: String) -> bool:
	return sounds.has(id) and String(sounds[id].get("kind", "sfx")) == "loop"

func is_spatial(id: String) -> bool:
	return sounds.has(id) and bool(sounds[id].get("spatial", false))

func variation_count(id: String) -> int:
	if not sounds.has(id):
		return 0
	return (sounds[id].get("files", []) as Array).size()

## Random index that differs from the previous pick of the same id.
func pick_index(id: String) -> int:
	var n := variation_count(id)
	if n <= 1:
		_last[id] = 0
		return 0
	var last: int = _last.get(id, -1)
	var i: int
	if last < 0:
		i = rng.randi_range(0, n - 1)
	else:
		i = rng.randi_range(0, n - 2)
		if i >= last:
			i += 1
	_last[id] = i
	return i

func pick(id: String) -> AudioStream:
	if variation_count(id) == 0:
		return null
	return stream(id, pick_index(id))

func stream(id: String, index: int) -> AudioStream:
	var key := "%s#%d" % [id, index]
	if _cache.has(key):
		return _cache[key]
	var files: Array = sounds[id].get("files", [])
	if index < 0 or index >= files.size():
		return null
	var s: AudioStream = load(String(files[index])) as AudioStream
	if s is AudioStreamWAV and is_loop(id):
		var wav := s as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
	_cache[key] = s
	return s
