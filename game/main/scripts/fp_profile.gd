extends RefCounted

## Section timer for performance work (tests/bench_play.gd turns it on).
## Off by default: begin()/end() return at once. Totals are microseconds
## summed since the last take(), with call counts.

static var enabled := false
static var _started := {}
static var totals := {}
static var counts := {}

static func begin(section: String) -> void:
	if enabled:
		_started[section] = Time.get_ticks_usec()

static func end(section: String) -> void:
	if not enabled or not _started.has(section):
		return
	var us: int = Time.get_ticks_usec() - int(_started[section])
	totals[section] = int(totals.get(section, 0)) + us
	counts[section] = int(counts.get(section, 0)) + 1

## Adds an externally measured cost (e.g. a kit node's last_*_us).
static func add(section: String, us: int) -> void:
	if enabled:
		totals[section] = int(totals.get(section, 0)) + us
		counts[section] = int(counts.get(section, 0)) + 1

## The totals so far, then starts over.
static func take() -> Dictionary:
	var out := {"totals": totals.duplicate(), "counts": counts.duplicate()}
	totals.clear()
	counts.clear()
	return out
