class_name FPSubtitles
extends CanvasLayer

## Subtitles for the vent being's Korean voice (spec 03 §7: voice + subtitles,
## the one exception to "no text on screen"). A single line at the bottom of
## the screen, pale on a soft dark band, fading in and out. Feed it with
## show_line(line_id) (text from LINES) or show_text(text) directly.

## Text for the line ids the vent currently emits. Lines come from
## docs/content/vent-lines.md; the trigger logic owns which id fires when.
const LINES := {
	"vent_heard_flush": "들었다. 들었어. 방금 그거 물 내린 거 맞지?",
	"vent_first_heard": "......어? 어어? 나 똑똑히 들었다? 거기 누구 있어? 있지? 있잖아!",
	"vent_bong_frantic": "좋아! 좋아... 좋아... 저, 저기, 물통. 물통 뚜껑 열어봐. 거기 봉 있지. 봉. 응?",
	"vent_bong_calm": "......봉",
	"vent_bong_idle": "봉 쌓였지. 소리 났어. 달그락.",
	"vent_not_enough": "......흥.",
	"vent_this_is_fair": "......하아. 그래. 그래, 이거지. 이거 참 몰랑한 봉이로군. 값은 이 정도면 적당하겠어. 가져가.",
	"vent_laugh": "큭 켘.",
}
const FADE := 0.25
const MIN_TIME := 1.8
const PER_CHAR := 0.075
## A line with a recorded voice stays for the clip plus this; a very short clip
## still leaves VOICE_MIN_TIME to read it.
const VOICE_TAIL := 0.2
const VOICE_MIN_TIME := 1.0

var label: Label
var band: PanelContainer
var current_text := ""
var _left := 0.0

func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	band = PanelContainer.new()
	band.name = "Band"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_left = 0.12
	band.anchor_right = 0.88
	band.anchor_top = 0.84
	band.anchor_bottom = 0.84
	band.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	# a dim, warm smear rather than a modern rounded box
	sb.bg_color = Color(0.05, 0.01, 0.02, 0.6)
	sb.shadow_color = Color(0.05, 0.01, 0.02, 0.35)
	sb.shadow_size = 10
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	band.add_theme_stylebox_override("panel", sb)
	root.add_child(band)
	label = Label.new()
	label.name = "Line"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", FPMenuKit.FONT)
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", Color(0.96, 0.95, 0.88))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	band.add_child(label)
	band.modulate.a = 0.0
	band.visible = false

## Shows the subtitle for a vent line id. Text comes from the vent line data
## file (res://main/data/vent_lines.json, "lines":[{id, ko}]) when it has the
## id, otherwise from LINES. Unknown ids show nothing.
func show_line(line_id: String) -> bool:
	var t := line_text(line_id)
	if t == "":
		return false
	show_text(t)
	return true

const DATA_PATH := "res://main/data/vent_lines.json"
## The being's remarks on the biomes and structures the player has been to
## (same format, kept apart from the main line file).
const BIOME_DATA_PATH := "res://main/data/vent_biome_lines.json"
## The being telling the player what to do next (guide.*, e.g. flush the
## vomit waiting in the bowl), kept apart the same way.
const GUIDE_DATA_PATH := "res://main/data/vent_guide_lines.json"
static var _data: Dictionary = {}
static var _data_loaded := false

static func line_text(line_id: String) -> String:
	if not _data_loaded:
		_data_loaded = true
		for path in [GUIDE_DATA_PATH, BIOME_DATA_PATH, DATA_PATH]:
			if not FileAccess.file_exists(path):
				continue
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				for l in parsed.get("lines", []):
					if l is Dictionary and l.has("id"):
						_data[String(l["id"])] = String(l.get("ko", ""))
	if _data.has(line_id):
		return String(_data[line_id])
	return String(LINES.get(line_id, ""))

## Lines that arrive while one is still up wait their turn instead of
## replacing it (one main signal at a time); at most QUEUE_MAX wait.
const QUEUE_MAX := 3
var _queue: Array = []

func show_text(text: String, seconds: float = -1.0) -> void:
	if text != "" and is_showing() and text != current_text:
		if not _queue.has(text):
			_queue.append([text, seconds])
			if _queue.size() > QUEUE_MAX:
				_queue.pop_front()
		return
	_show(text, seconds)

func _show(text: String, seconds: float) -> void:
	current_text = text
	label.text = text
	band.visible = text != ""
	_left = seconds if seconds > 0.0 else maxf(MIN_TIME, text.length() * PER_CHAR)

## The voice started saying this line now: the subtitle shows it now, for as
## long as the clip, even if it was waiting behind another line.
func follow_voice(line_id: String, seconds: float) -> void:
	var t := line_text(line_id)
	if t == "":
		return
	_queue = _queue.filter(func(q): return String(q[0]) != t)
	_show(t, maxf(seconds + VOICE_TAIL, VOICE_MIN_TIME))

## The voice was cut off: its subtitle goes too, the next waiting line follows.
func voice_cut(line_id: String) -> void:
	if current_text != "" and current_text == line_text(line_id):
		_left = 0.0

func queued() -> int:
	return _queue.size()

func is_showing() -> bool:
	return band.visible and _left > 0.0

func _process(delta: float) -> void:
	if not band.visible:
		return
	_left -= delta
	if _left <= 0.0 and not _queue.is_empty():
		var next: Array = _queue.pop_front()
		_show(String(next[0]), float(next[1]))
	var target := 1.0 if _left > 0.0 else 0.0
	band.modulate.a = move_toward(band.modulate.a, target, delta / FADE)
	if _left <= 0.0 and band.modulate.a <= 0.0:
		band.visible = false
		current_text = ""

## Capture helper: show at full opacity right away.
func show_now(text: String) -> void:
	_queue.clear()
	_show(text, 30.0)
	band.modulate.a = 1.0
