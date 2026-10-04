class_name FPTissueTools
extends RefCounted

## Session D gameplay glue for main.gd (docs/plan/work-plan.md W10, W20,
## W24-W26): tissue-aware chewing (hardness, membrane needs a knife), the big
## saw's six-cell strokes, the blender (plug into nerves to charge, blend a
## pile, drink it) and the spray aim. main.gd holds one instance and calls in
## from its own frame steps; all numbers come from docs/spec.

## Blender (06-tools.md 2).
const BLENDER_CHARGE_MAX := 100.0
const BLEND_COST := 10.0
const CHARGE_RATE := 25.0
const CHARGE_CONTRACT_DELAY := 1.5
const CHARGE_CONTRACT_EVERY := 1.5
const BLEND_RATIO := 0.6
const SPIN_TIME := 1.5
const DRINK_TIME := 1.5
const DRINK_PITCH := 0.75 ## rad the head tips back while drinking
## How close to a nerve the blender has to be to stay plugged in.
const PLUG_REACH := 2.6

enum Blend { IDLE, SPIN, DRINK }

var m: Node3D
var blend_state: Blend = Blend.IDLE
var blend_t: float = 0.0
var _blend_amount: float = 0.0
var _blend_units: Dictionary = {}
var _pitch_before: float = 0.0
## Plugged-in charging: world point on the nerve and seconds plugged.
var plugged: bool = false
var plug_point: Vector3 = Vector3.ZERO
var plug_t: float = 0.0
var _next_contract: float = CHARGE_CONTRACT_DELAY
## Seconds since the last chew at a membrane without a blade (the hand pushes
## on it, nothing tears) -- for tests and the hand press visual.
var membrane_refusals: int = 0
## Tests hold the blend button without real input.
var hold_override: bool = false
## Contractions set off by charging (tests).
var contractions_caused: int = 0

func _init(main: Node3D) -> void:
	m = main

# --- chewing -------------------------------------------------------------------

## Mutation effects on tissue (05-mutations.md M08, M09, T6). Mutation ids
## are looked up loosely so this keeps working while the mutation list moves.
func tissue_opts() -> Dictionary:
	var o := {}
	var prog = m.progression
	if prog == null:
		return o
	# all_mutations() = bought + tumor (T1-T7); purchased_mutations() misses tumors
	var owned: Array = []
	if prog.has_method("all_mutations"):
		owned = prog.all_mutations()
	elif prog.has_method("purchased_mutations"):
		owned = prog.purchased_mutations()
	for id in owned:
		var s := String(id).to_lower()
		if s.begins_with("m08") or s.contains("web"):
			o["compress_hardness_scale"] = 0.7
		if s.begins_with("m09") or s.contains("thick_nail"):
			o["thick_nails"] = true
		if s.begins_with("t6") or s.contains("split_jaw") or s.contains("vertical_jaw"):
			o["split_jaw"] = true
	return o

func tool() -> String:
	return String(m.progression.equipped())

func can_grab_at(p: Vector3) -> bool:
	return FDKTissueRules.can_grab(m.terrain.tissue_at(p), tool(), tissue_opts())

## One frame of holding the eat input on `target` (hit + half a cell).
## Returns true while a chew is running.
func chew_at(target: Vector3, hit_pos: Vector3, dir: Vector3, delta: float) -> bool:
	var tissue: int = m.terrain.tissue_at(target)
	var opts := tissue_opts()
	var tl := tool()
	if not FDKTissueRules.can_grab(tissue, tl, opts):
		m.chewer.stop()
		m.terrain.set_press(hit_pos, -dir, 0.25) # the hand pushes, nothing gives
		membrane_refusals += 1
		return false
	# the chewer refuses inedible ids: a blade (or mutation) opens membrane
	m.terrain.inedible_tissues = PackedInt32Array() if tissue == FDKTissueRules.MEMBRANE else PackedInt32Array([FDKTissueRules.MEMBRANE])
	m.chewer.try_start(target)
	m.chewer.process_chew(delta * FDKTissueRules.chew_speed(tissue, tl, opts))
	m.terrain.inedible_tissues = PackedInt32Array([FDKTissueRules.MEMBRANE])
	return m.chewer.is_chewing()

## Seconds one tear takes at p with the current tool (tests / tuning).
func chew_time_at(p: Vector3) -> float:
	return FDKTissueRules.chew_time(m.terrain.tissue_at(p), tool(), m.stomach.chew_time_multiplier(), tissue_opts())

## Big saw stroke (06-tools.md 3): after the chewer's own cell, five more
## around it come away, and all of it goes straight to the stomach.
func on_cell_torn(world_pos: Vector3) -> int:
	if tool() != "big_saw":
		return 1
	var extra := 0
	var cs: float = m.terrain_config.cell_size
	var dir: Vector3 = m.player.get_look_ray()[1]
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.1:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(dir).normalized()
	for off in [side, -side, up, -up, dir, side + up, side - up, -side + up, -side - up, dir + side, dir - side, dir + up, dir - up, dir * 2.0]:
		if extra >= FDKTissueRules.SAW_TEAR_CELLS - 1:
			break
		var p: Vector3 = world_pos + off * cs
		if m.terrain.density_at(p) < 0.5 or not FDKTissueRules.can_grab(m.terrain.tissue_at(p), "big_saw"):
			continue
		m.terrain.dig_at(p, 1.0)
		m.stomach.add_flesh(m.stomach_config.flesh_per_cell)
		m.progression.on_flesh_eaten(m.shell_at(p))
		extra += 1
	return 1 + extra

# --- spray -----------------------------------------------------------------------

func spray(deep: bool) -> int:
	if not m.progression.one_handed_action_allowed():
		return -1
	var tier: int = m.progression.pick_spray_tier(deep)
	if tier < 0:
		return -1
	var hit: Dictionary = m._look_hit()
	if hit.is_empty() or not hit.collider.has_meta("fdk_terrain_chunk"):
		return -1
	var dir: Vector3 = m.player.get_look_ray()[1]
	return m.progression.sprays.use(m.terrain, hit.position, tier, dir)

# --- blender ---------------------------------------------------------------------

func charge_units() -> float:
	return float(m.blender_charge) * BLENDER_CHARGE_MAX

## Lights lit on the blender's side (10 lights, one per blend).
func charge_lights() -> int:
	return int(floor(charge_units() / BLEND_COST + 0.001))

## fp_blend pressed: aimed at nerve tissue -> plug in; else blend the pile.
func use_blender() -> bool:
	if not m.progression.owns("blender") or blend_state != Blend.IDLE:
		return false
	var hit: Dictionary = m._look_hit()
	if not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk"):
		var dir: Vector3 = m.player.get_look_ray()[1]
		if m.terrain.tissue_at(hit.position + dir * m.terrain_config.cell_size * 0.5) == FDKTissueRules.NERVE:
			plug_in(hit.position)
			return true
	return start_blend()

func plug_in(at: Vector3) -> void:
	plugged = true
	plug_point = at
	plug_t = 0.0
	_next_contract = CHARGE_CONTRACT_DELAY

func unplug() -> void:
	plugged = false

## Charging: 25 per second while plugged; 1.5 s in, and every 1.5 s after,
## that nerve sets off a contraction -- filling up always costs a squeeze.
func step_charge(delta: float, still_holding: bool) -> void:
	if not plugged:
		return
	if not (still_holding or hold_override) or m.player.global_position.distance_to(plug_point) > PLUG_REACH:
		unplug()
		return
	plug_t += delta
	m.blender_charge = minf(1.0, float(m.blender_charge) + CHARGE_RATE * delta / BLENDER_CHARGE_MAX)
	while plug_t >= _next_contract:
		_next_contract += CHARGE_CONTRACT_EVERY
		contractions_caused += 1
		var n = m._nearest_nerve(plug_point, 2.0)
		if n != null:
			n.disturb(0.8)
		else:
			m._on_nerve_disturbed(plug_point)

## Pours the carried pile in and starts spinning (needs one blend of charge).
func start_blend() -> bool:
	if blend_state != Blend.IDLE or m.carried_flesh <= 0.0 or charge_units() < BLEND_COST - 0.001:
		return false
	_blend_amount = m.carried_flesh
	_blend_units = m.carried_units.duplicate()
	m.carried_flesh = 0.0
	m.carried_units.clear()
	m.blender_charge = maxf(0.0, (charge_units() - BLEND_COST) / BLENDER_CHARGE_MAX)
	blend_state = Blend.SPIN
	blend_t = 0.0
	m.progression.refresh_hands(m.carry_mode)
	return true

## Spin 1.5 s, then tip the head back and drink 1.5 s; the flesh lands in the
## stomach at 60% of its size when the drink finishes.
func step_blend(delta: float) -> void:
	_sync_blender_art()
	if blend_state == Blend.IDLE:
		return
	blend_t += delta
	var pivot: Node3D = m.player.camera_pivot
	if blend_state == Blend.SPIN and blend_t >= SPIN_TIME:
		blend_state = Blend.DRINK
		blend_t = 0.0
		_pitch_before = pivot.rotation.x
		m.blender_drunk.emit()
	if blend_state == Blend.DRINK:
		var k := clampf(blend_t / DRINK_TIME, 0.0, 1.0)
		pivot.rotation.x = _pitch_before + DRINK_PITCH * sin(k * PI)
		if blend_t >= DRINK_TIME:
			pivot.rotation.x = _pitch_before
			finish_drink()

func finish_drink() -> void:
	m.stomach.add_flesh(_blend_amount * BLEND_RATIO)
	for s in _blend_units.keys():
		m.progression.on_flesh_eaten(int(s), int(_blend_units[s]))
	_blend_amount = 0.0
	_blend_units.clear()
	blend_state = Blend.IDLE
	blend_t = 0.0

## Whole blend in one call (tests, old callers): spin + drink at once.
func blend_now() -> bool:
	if not start_blend():
		return false
	blend_state = Blend.DRINK
	m.blender_drunk.emit()
	finish_drink()
	return true

## 0 idle, 1 spinning, 2 drinking, and 0..1 progress (hands / art read it).
func blend_phase() -> int:
	return int(blend_state)

func blend_progress() -> float:
	match blend_state:
		Blend.SPIN: return clampf(blend_t / SPIN_TIME, 0.0, 1.0)
		Blend.DRINK: return clampf(blend_t / DRINK_TIME, 0.0, 1.0)
	return 0.0
# --- rest points -----------------------------------------------------------------

## Loading a game with another rest-point rotation: move the containers and
## the hollows to that game's layout (chunks already in the save keep theirs).
func relayout_rest_points(seed: int) -> void:
	if seed == int(m.rest_seed) or seed <= 0:
		return
	m.rest_seed = seed
	var pts: Array[Vector3] = FPWorldFeatures.rest_points(m.RESTROOM_CENTER, seed)
	var nodes: Array = []
	for c in m.get_children():
		if c.has_meta("rest_point"):
			nodes.append(c)
	m.rest_points = pts
	m._world_density_cache.clear()
	for i in range(mini(nodes.size(), pts.size())):
		(nodes[i] as Node3D).position = pts[i]
	var h := FPWorldFeatures.CONTAINER_HALF
	for p in pts:
		m.terrain.carve_sphere(p, 0.01) # makes sure the chunk exists
		m.terrain.fill_box_uniform(AABB(p - h, h * 2.0), 0.0, FDKTissueRules.COMPRESSIVE)
## Lamps show the charge; the jar spins and is tipped up while drinking.
var _drink_played := false
func _sync_blender_art() -> void:
	var ah = m.get("art_hookup")
	if ah == null or not is_instance_valid(ah):
		return
	var art = ah.get("blender")
	if art == null or not is_instance_valid(art):
		return
	if art.has_method("set_charge_lights"):
		art.call("set_charge_lights", charge_lights())
	if blend_state == Blend.SPIN:
		art.call("set_fill", clampf(_blend_amount / 40.0, 0.1, 1.0))
		art.call("set_spin", true)
		_drink_played = false
	elif blend_state == Blend.DRINK and not _drink_played:
		_drink_played = true
		art.call("set_spin", false)
		art.call("play_drink")
