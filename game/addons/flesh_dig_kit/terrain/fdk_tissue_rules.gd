class_name FDKTissueRules
extends RefCounted

## Tissue table and per-tissue rules (docs/spec/02-world-tissue.md 3,
## 01-body-eating.md 3, 06-tools.md 1/3). Pure data + static helpers: the
## chunk reads REGEN for its per-corner regrowth, the game asks can_grab /
## chew_time / tear_cells before and during a chew, and the terrain field
## drives the contractile tissue's periodic squeeze with contract_offset.

## Tissue ids (stored per cell). 2 is an unused legacy slot (old fat band);
## MELTED is never stored -- tissue_at reports it for sprayed cells.
const COMPRESSIVE := 0 ## core shell: puffy flesh, regrows fastest
const NERVE := 1 ## surface shell: yellow nerves packed in
const LEGACY_FAT := 2
const MEMBRANE := 3 ## around the restroom and on every shell boundary
const CONTRACTILE := 4 ## mantle shell: muscle-like, squeezes periodically
const MELTED := 5 ## sprayed: density 0 forever, inedible

## Shell index (0 core, 1 mantle, 2 surface) -> main tissue.
const SHELL_TISSUE := [COMPRESSIVE, CONTRACTILE, NERVE]

const HARDNESS := {COMPRESSIVE: 1.0, NERVE: 1.2, LEGACY_FAT: 1.0, MEMBRANE: 2.0, CONTRACTILE: 1.4}
const REGEN := {COMPRESSIVE: 1.5, NERVE: 0.8, LEGACY_FAT: 1.0, MEMBRANE: 0.0, CONTRACTILE: 1.0, MELTED: 0.0}

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
## Cells below this density count as empty for "touches an empty cell".
const EMPTY_DENSITY := 0.5

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
	var along := p.dot(Vector3(0.62, 0.31, 0.72))
	var wobble := sin(p.x * 0.9 + p.z * 0.4) * 0.35
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