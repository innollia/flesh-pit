class_name FDKTissueRules
extends RefCounted

## Tissue table and per-tissue rules (docs/spec/02-world-tissue.md 3,
## 01-body-eating.md 3, 06-tools.md 1/3). Pure data + static helpers: the
## chunk reads REGEN for its per-corner regrowth, the game asks can_grab /
## chew_time / tear_cells before and during a chew, and the terrain field
## drives the contractile tissue's periodic squeeze with contract_offset.

## Tissue ids (stored per cell). 2 was the old fat band, now the fat-cave biome;
## MELTED is never stored -- tissue_at reports it for sprayed cells.
const COMPRESSIVE := 0 ## core shell: puffy flesh, regrows fastest
const NERVE := 1 ## surface shell: yellow nerves packed in
const LEGACY_FAT := 2
const MEMBRANE := 3 ## around the restroom and on every shell boundary
const CONTRACTILE := 4 ## mantle shell: muscle-like, squeezes periodically
const MELTED := 5 ## sprayed: density 0 forever, inedible
## Biome tissues (02-world-tissue.md 1-1): one shell holds several biomes,
## each made of its own tissue. FAT reuses the old fat band slot.
const FAT := 2 ## soft rendered fat, caves form in it
const CARTILAGE := 6 ## gristle ribs, needs a blade like muscle
const CLOTH := 7 ## swallowed clothing pressed into wads, barely regrows
const HAIR := 8 ## matted hair over scalp, regrows fast

## Shell index (0 core, 1 mantle, 2 surface) -> main tissue.
const SHELL_TISSUE := [COMPRESSIVE, CONTRACTILE, NERVE]

const HARDNESS := {COMPRESSIVE: 1.0, NERVE: 1.2, FAT: 0.8, MEMBRANE: 2.0, CONTRACTILE: 1.4,
	CARTILAGE: 1.8, CLOTH: 1.1, HAIR: 1.3}
const REGEN := {COMPRESSIVE: 1.5, NERVE: 0.8, FAT: 1.2, MEMBRANE: 0.0, CONTRACTILE: 1.0, MELTED: 0.0,
	CARTILAGE: 0.5, CLOTH: 0.3, HAIR: 1.2}

const BASE_CHEW_TIME := 0.6
## Big saw: one stroke = base x 1.5 x hardness, tears 6 cells.
const SAW_TIME_FACTOR := 1.5
const SAW_TEAR_CELLS := 6

## Contractile squeeze (02-world-tissue.md 3, "수축 조직의 주기 수축").
const CONTRACT_PERIOD := 8.0
const CONTRACT_RISE := 1.5
const CONTRACT_HOLD := 1.0
const CONTRACT_RELEASE := 2.0
const CONTRACT_GAIN := 0.3
const CONTRACT_WAVE := 3.0 ## m: one squeeze wave runs along the wall this long
const CONTRACT_WARN := 1.0 ## the squeeze sound plays this long before it starts
## The wall shows the coming squeeze this long before it starts (the terrain
## shader's preview, contract_preview below). The sound's lead is CONTRACT_WARN.
const CONTRACT_SHOW_LEAD := 1.6
## The squeeze wave: direction it runs along, and its sideways wobble
## (x and z frequency, amplitude in wave lengths). contract_phase and the
## terrain shader read the same numbers.
const CONTRACT_DIR := Vector3(0.62, 0.31, 0.72)
const CONTRACT_WOBBLE := Vector3(0.9, 0.4, 0.35)
## Cells below this density count as empty for "touches an empty cell".
const EMPTY_DENSITY := 0.5

## Knife digs every tissue this much faster.
const KNIFE_SPEED := 1.6

static func hardness(tissue: int) -> float:
	return float(HARDNESS.get(tissue, 1.0))

static func regen_multiplier(tissue: int) -> float:
	return float(REGEN.get(tissue, 1.0))

## opts (all optional, from mutations -- 05-mutations.md):
##   "compress_hardness_scale": float   M08 webbing, compressive x0.7
##   "thick_nails": bool                M09, bare hands grab membrane, x3 time
##   "split_jaw": bool                  T6, membrane torn by mouth, hardness 1.0
static func can_grab(tissue: int, tool: String, opts: Dictionary = {}) -> bool:
	if tissue == MELTED:
		return false
	if tissue == MEMBRANE:
		return tool == "knife" or tool == "big_saw" or bool(opts.get("thick_nails", false)) or bool(opts.get("split_jaw", false))
	if tissue == CONTRACTILE or tissue == CARTILAGE:
		return tool == "knife" or tool == "big_saw" # muscle and gristle need a blade
	return true

## Effective hardness for this tool (membrane rules depend on how it is cut).
static func effective_hardness(tissue: int, tool: String, opts: Dictionary = {}) -> float:
	var h := hardness(tissue)
	if tissue == COMPRESSIVE:
		h *= float(opts.get("compress_hardness_scale", 1.0))
	if tissue == MEMBRANE:
		if bool(opts.get("split_jaw", false)):
			h = 1.0
		elif tool != "knife" and tool != "big_saw" and bool(opts.get("thick_nails", false)):
			h *= 3.0
	return h

## Seconds one tear takes: base x hardness (x1.5 for a saw stroke) x overfill.
static func chew_time(tissue: int, tool: String, overfill_multiplier: float = 1.0, opts: Dictionary = {}) -> float:
	var t := BASE_CHEW_TIME * effective_hardness(tissue, tool, opts) * overfill_multiplier
	if tool == "big_saw":
		t *= SAW_TIME_FACTOR
	elif tool == "knife":
		t /= KNIFE_SPEED # the knife digs 1.6x faster
	return t

## Delta scale to feed FDKChewer.process_chew (which already applies the
## overfill multiplier to base_chew_time), so its tear lands at chew_time().
static func chew_speed(tissue: int, tool: String, opts: Dictionary = {}) -> float:
	return BASE_CHEW_TIME / chew_time(tissue, tool, 1.0, opts)

static func tear_cells(tool: String) -> int:
	return SAW_TEAR_CELLS if tool == "big_saw" else 1

## Seconds into its own cycle a point starts, so the squeeze runs along the
## wall as a ~3 m wave instead of the whole tunnel pulsing at once.
static func contract_phase(p: Vector3) -> float:
	var along := p.dot(CONTRACT_DIR)
	var wobble := sin(p.x * CONTRACT_WOBBLE.x + p.z * CONTRACT_WOBBLE.y) * CONTRACT_WOBBLE.z
	return fposmod((along / CONTRACT_WAVE + wobble) * CONTRACT_PERIOD, CONTRACT_PERIOD)

## 0..1 squeeze at time t_in_cycle (rise, hold, release, then rest).
static func contract_envelope(t_in_cycle: float) -> float:
	var t := fposmod(t_in_cycle, CONTRACT_PERIOD)
	if t < CONTRACT_RISE:
		return smoothstep(0.0, 1.0, t / CONTRACT_RISE)
	t -= CONTRACT_RISE
	if t < CONTRACT_HOLD:
		return 1.0
	t -= CONTRACT_HOLD
	if t < CONTRACT_RELEASE:
		return 1.0 - smoothstep(0.0, 1.0, t / CONTRACT_RELEASE)
	return 0.0

## Density added right now at p by the periodic squeeze (0..CONTRACT_GAIN).
static func contract_offset(p: Vector3, time: float) -> float:
	return CONTRACT_GAIN * contract_envelope(time + contract_phase(p))

## True during the CONTRACT_WARN seconds just before p starts squeezing.
static func contract_warning(p: Vector3, time: float) -> bool:
	var t := fposmod(time + contract_phase(p), CONTRACT_PERIOD)
	return t >= CONTRACT_PERIOD - CONTRACT_WARN

## 0..1 preview of the squeeze the wall at world point p is about to make,
## rising over the CONTRACT_SHOW_LEAD seconds before it starts and gone the
## moment it does. fdk_terrain_surface.gdshader draws exactly this on
## contractile faces from the field's contract_time; this copy exists so
## headless tests can hold it against the real squeeze. Change both together.
## The squeeze is stepped per grid corner, each with its own phase (corners
## of one cell start up to a few seconds apart), so the preview goes by the
## corners that move this point: those of the cell holding p (a surface vertex
## lies in the cell whose corners place it) that are near it. The far corners
## of an edge or corner cell sit deep in solid flesh and do not squeeze; they
## fade out between CONTRACT_NEAR_FROM and CONTRACT_NEAR_TO cells away.
## Corners on a chunk border never squeeze (FDKChunk._rebuild_contract_list)
## and are left out. The preview is the lead-in of the first of them and goes
## off while any of them is clenching (rise and hold): the wall blanches, then
## moves.
const CONTRACT_NEAR_FROM := 0.95
const CONTRACT_NEAR_TO := 1.15
static func contract_preview(p: Vector3, time: float, cell_size: float, chunk_size: int) -> float:
	var q := p / cell_size
	var cell := q.floor()
	var best := 0.0
	var busy := 0.0
	for k in range(8):
		var c := cell + Vector3(k & 1, (k >> 1) & 1, (k >> 2) & 1)
		if posmod(int(c.x), chunk_size) == 0 or posmod(int(c.y), chunk_size) == 0 or posmod(int(c.z), chunk_size) == 0:
			continue
		var near := 1.0 - smoothstep(CONTRACT_NEAR_FROM, CONTRACT_NEAR_TO, q.distance_to(c))
		if near <= 0.0:
			continue
		var t := fposmod(time + contract_phase(c * cell_size), CONTRACT_PERIOD)
		if t < CONTRACT_RISE + CONTRACT_HOLD:
			busy = maxf(busy, near)
		best = maxf(best, near * contract_lead_in(t))
	return best * (1.0 - busy)

## 0..1 through the CONTRACT_SHOW_LEAD seconds before a cycle's squeeze starts.
static func contract_lead_in(t_in_cycle: float) -> float:
	var t := fposmod(t_in_cycle, CONTRACT_PERIOD)
	return clampf((t - (CONTRACT_PERIOD - CONTRACT_SHOW_LEAD)) / CONTRACT_SHOW_LEAD, 0.0, 1.0)

## How each tissue looks when it is pulled and torn. One table for the terrain
## shader (pull_gain, wound), the tear feel (blood, strands, snap, recoil) and
## the drops, so a tissue reads the same in all three.
##   pull_gain       height of the drawn-out dome against plain flesh (1.0)
##   wound_color     wet rim round a fresh hole (linear rgb), wound_strength 0 = none
##   blood           colour of the drops; drops = how many the tear throws (0 = dry)
##   strands         wet strands from the rim to the fist, their colour
##                   (strand_color; alpha 0 = blood tinted like plain flesh)
##                   and thickness (strand_thin)
##   snap_from/to    seconds after the tear within which each strand breaks
##   recoil          scale of the view jolt
## Plain flesh (COMPRESSIVE) holds the values the game had before the table;
## the other tissues differ from it and it does not change.
const BLOOD := Color(0.86, 0.07, 0.1)
const LOOK_PLAIN := {
	"pull_gain": 1.0, "wound_color": Vector3(0.46, 0.02, 0.04), "wound_strength": 0.85,
	"blood": BLOOD, "drops": 18, "strands": 5, "strand_color": Color(0, 0, 0, 0), "strand_thin": 1.0,
	"snap_from": 0.07, "snap_to": 0.23, "recoil": 1.0,
}
const LOOK := {
	FAT: {"pull_gain": 1.35, "wound_color": Vector3(0.78, 0.62, 0.22), "wound_strength": 0.7,
		"blood": Color(0.80, 0.66, 0.25), "drops": 10, "strands": 8, "strand_color": Color(0.86, 0.76, 0.48), "strand_thin": 1.0,
		"snap_from": 0.15, "snap_to": 0.30, "recoil": 0.7},
	NERVE: {"pull_gain": 0.8, "wound_color": Vector3(0.55, 0.10, 0.04), "wound_strength": 0.85,
		"blood": BLOOD, "drops": 14, "strands": 7, "strand_color": Color(0.86, 0.74, 0.30), "strand_thin": 1.0,
		"snap_from": 0.03, "snap_to": 0.08, "recoil": 0.9},
	CONTRACTILE: {"pull_gain": 0.6, "wound_color": Vector3(0.30, 0.02, 0.03), "wound_strength": 0.9,
		"blood": Color(0.45, 0.03, 0.05), "drops": 22, "strands": 3, "strand_color": Color(0, 0, 0, 0), "strand_thin": 1.0,
		"snap_from": 0.20, "snap_to": 0.30, "recoil": 1.25},
	CARTILAGE: {"pull_gain": 0.25, "wound_color": Vector3(0.80, 0.78, 0.72), "wound_strength": 0.3,
		"blood": BLOOD, "drops": 4, "strands": 0, "strand_color": Color(0, 0, 0, 0), "strand_thin": 1.0,
		"snap_from": 0.07, "snap_to": 0.23, "recoil": 1.4},
	MEMBRANE: {"pull_gain": 0.4, "wound_color": Vector3(0.85, 0.80, 0.78), "wound_strength": 0.4,
		"blood": Color(0.90, 0.52, 0.55), "drops": 6, "strands": 2, "strand_color": Color(0, 0, 0, 0), "strand_thin": 1.0,
		"snap_from": 0.10, "snap_to": 0.18, "recoil": 1.0},
	CLOTH: {"pull_gain": 0.9, "wound_color": Vector3(0.46, 0.02, 0.04), "wound_strength": 0.0,
		"blood": BLOOD, "drops": 0, "strands": 0, "strand_color": Color(0, 0, 0, 0), "strand_thin": 1.0,
		"snap_from": 0.07, "snap_to": 0.23, "recoil": 1.0},
	HAIR: {"pull_gain": 0.7, "wound_color": Vector3(0.46, 0.02, 0.04), "wound_strength": 0.0,
		"blood": BLOOD, "drops": 0, "strands": 6, "strand_color": Color(0.16, 0.10, 0.07), "strand_thin": 0.45,
		"snap_from": 0.07, "snap_to": 0.23, "recoil": 1.0},
}

static func look(tissue: int) -> Dictionary:
	return LOOK.get(tissue, LOOK_PLAIN)

