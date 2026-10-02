class_name FPMutationApply
extends Node

## Puts the owned mutations (docs/spec/05-mutations.md) into the running game.
## FPProgression holds the numbers; this node writes them into the stomach
## config, the player config, the lamp and camera, and runs the few
## mutations that act on their own (M16 cud stomach, M21 self-charging
## blender, M22 alien hand, M15 gulp, M17/M26 health, M24 glare, M29
## dormancy, T1 echo clicks, T7 rib fan). Add as a child of main and call
## setup(main). main.gd reads reach/crush time/body radius from progression.

## sound hooks (game/audio_HOOKUP.md)
signal tumor_eaten
signal alien_hand_tore
signal gulped
signal echo_click

var m: Node3D
var _eaten_n := 0
var _click_phase := 0.0
var _base_speed := {}
var _cud_t := 0.0
var _alien_t := 0.0
var _gulp_t := -1.0
var _echo_t := 0.0
var _last_health := 100.0
var _dormant_t := -1.0
var _still_t := 0.0
var _key := ""
var alien_tears := 0 ## cells the alien hand tore (tests)
var _extra_tearing := false
var codex: Node3D ## crayon tumor drawings on the restroom wall
var _codex_n := -1

func setup(main: Node3D) -> void:
	m = main
	# the player config resource may be shared: give this player its own
	m.player.config = m.player.config.duplicate()
	var c: Resource = m.player.config
	_base_speed = {"walk_speed": c.walk_speed, "crouch_speed": c.crouch_speed, "climb_speed": c.climb_speed}
	m.chewer.cell_torn.connect(_on_torn)
	m.died.connect(_on_died)
	codex = (load("res://main/art/fp_tumor_codex.gd") as GDScript).new()
	codex.name = "TumorCodex"
	codex.position = Vector3(FPRestroom.HALF.x - 0.002, 1.72, 0.25)
	codex.rotation.y = -PI * 0.5
	m.restroom.add_child(codex)
	apply_now()

## Recompute every static parameter (call after buying or loading).
func apply_now() -> void:
	var p: FPProgression = m.progression
	var sc: FDKStomachConfig = m.stomach_config
	sc.capacity = p.capacity()
	sc.overfill_capacity = p.overfill_capacity()
	sc.overfill_chew_multiplier = p.overfill_chew_multiplier()
	sc.base_chew_time = p.base_chew_time()
	var c: Resource = m.player.config
	var f := p.walk_speed_factor()
	for k in _base_speed.keys():
		c.set(k, float(_base_speed[k]) * f)
	if m.player_lamp != null:
		m.player_lamp.omni_range = 9.0 * p.light_range_factor()
	if m.player.camera != null:
		m.player.camera.fov = minf(170.0, 75.0 * p.fov() / FPProgression.BASE_FOV) if p.has_mutation("T5") else 75.0
	_key = ",".join(p.all_mutations())
	if m.stomach_view != null and m.stomach_view.has_method("set_forms"):
		m.stomach_view.set_forms(p.all_mutations())

func _process(delta: float) -> void:
	if m == null or m.ended:
		return
	var p: FPProgression = m.progression
	if ",".join(p.all_mutations()) != _key:
		apply_now()
	_step_codex()
	if m.progression.tumors_eaten != _eaten_n:
		_eaten_n = m.progression.tumors_eaten
		tumor_eaten.emit()
	_step_dormant(delta)
	if _dormant_t >= 0.0 or m.is_opening():
		return
	_step_hardness()
	_step_health(delta)
	step_timed(delta)

## Chew time follows the aimed tissue's mutated hardness (ratio to its base).
func _step_hardness() -> void:
	var p: FPProgression = m.progression
	var base := p.base_chew_time()
	var hit: Dictionary = m._look_hit()
	if not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk"):
		var dir: Vector3 = m.player.get_look_ray()[1]
		var t: int = m.terrain.tissue_at(hit.position + dir * m.terrain_config.cell_size * 0.5)
		var b: float = float(FPProgression.TISSUE_HARDNESS.get(t, 1.0))
		# fp_tissue_tools (session D) already applies base hardness and
		# M08/M09/T6; only the rest (M12, M18) is added here as a ratio
		var bare := p.equipped() == ""
		var d := b
		if t == FPProgression.TISSUE_COMPRESSIVE and p.has_mutation("M08"):
			d *= 0.7
		if t == FPProgression.TISSUE_MEMBRANE and bare and p.has_mutation("M09") and not p.has_mutation("T6"):
			d *= 3.0
		base *= p.hardness(t, bare) / d
	m.stomach_config.base_chew_time = base

func _step_health(delta: float) -> void:
	var p: FPProgression = m.progression
	var h: float = m.hazard.health
	if h < _last_health and p.tissue_damage_factor() < 1.0:
		h = _last_health - (_last_health - h) * p.tissue_damage_factor()
	elif h > _last_health and p.health_regen_factor() > 1.0 and h < 100.0:
		h = minf(100.0, h + (h - _last_health) * (p.health_regen_factor() - 1.0))
	m.hazard.health = h
	_last_health = h
	if p.restroom_glare_factor() > 1.0 and m._flash > 0.0:
		m._flash = minf(1.0, m._flash + delta * 0.4) # decays at half speed

## Everything a mutation does on its own over time (tests call this).
func step_timed(delta: float) -> void:
	var p: FPProgression = m.progression
	var still: bool = (m.player.velocity as Vector3).length() < 0.05
	_still_t = _still_t + delta if still else 0.0
	# M16: the cud stomach shrinks the flesh inside every 60 s
	if p.has_mutation("M16") and m.stomach.fill > 0.0:
		_cud_t += delta
		while _cud_t >= FPProgression.CUD_PERIOD:
			_cud_t -= FPProgression.CUD_PERIOD
			m.stomach.fill *= 1.0 - FPProgression.CUD_SHRINK
			m.stomach.fill_changed.emit(m.stomach.fill, m.stomach_config.capacity, m.stomach_config.overfill_capacity)
	# M21: the blender in the left hand charges itself
	if p.blender_self_charge() > 0.0 and p.owns("blender"):
		m.blender_charge = minf(1.0, m.blender_charge + p.blender_self_charge() / 100.0 * delta)
	# M22: standing still, the left hand tears a cell in reach every 2 s
	if p.has_mutation("M22") and still and not m.restroom.contains(m.player.global_position):
		_alien_t += delta
		if _alien_t >= FPProgression.ALIEN_HAND_PERIOD:
			_alien_t = 0.0
			alien_tear()
	else:
		_alien_t = 0.0
	# M15: holding the flesh pile, a 3 s gulp swallows it whole (no packing)
	if p.can_lift_without_blender() and m.carried_flesh > 0.0 and Input.is_action_pressed("fdk_eat") and not p.owns("blender"):
		_gulp_t = maxf(0.0, _gulp_t) + delta
		if _gulp_t >= FPProgression.GULP_TIME:
			gulp()
	else:
		_gulp_t = -1.0
	# T1: each click lights outlines and marks thin / regrowing / squeezing /
	# nerve / tumor spots through the flesh (echo_pulse)
	if p.has_mutation("T1") and m.player_lamp != null:
		_echo_t += delta
		var k := fposmod(_echo_t, 1.2) / 1.2
		if k < _click_phase:
			echo_click.emit()
			echo_pulse(false)
		_click_phase = k
		m.player_lamp.light_color = Color(0.7, 0.85, 1.0)
		m.player_lamp.light_energy = 3.5 * exp(-k * 6.0)
		m.environment.ambient_light_energy = 0.02
	elif m.player_lamp != null:
		m.player_lamp.light_color = Color(1.0, 0.8, 0.72)
	_step_echo_marks(delta)
	# M23: arm hairs shiver HAIR_WARN_TIME before a squeeze reaches the player
	_step_hair_shiver(delta)
	# M25: the death marker keeps following the drifting drop
	if p.has_mutation("M25") and m.death_drop != null and m.death_drop.active and m.death_drop.marker != null:
		m.death_drop.marker.position = m.death_drop.current_position
		m.death_drop.last_known_position = m.death_drop.current_position

# --- T1 echo pulse -----------------------------------------------------------

## Kinds a T1 echo pulse tells apart (05-mutations.md 4: 얇은 곳, 재생 중인
## 곳, 수축 직전인 곳, 신경, 종양).
enum Echo { THIN, REGROW, SQUEEZE, NERVE, TUMOR }
const ECHO_COLORS := {
	Echo.THIN: Color(0.85, 0.95, 1.0),
	Echo.REGROW: Color(0.35, 1.0, 0.45),
	Echo.SQUEEZE: Color(0.8, 0.35, 1.0),
	Echo.NERVE: Color(1.0, 0.9, 0.2),
	Echo.TUMOR: Color(1.0, 0.2, 0.15),
}
const ECHO_RADIUS := 5.0
const ECHO_STEP := 0.5
const ECHO_THIN := 1.0 ## a wall thinner than this (m) reads as thin
const ECHO_SQUEEZE_LEAD := 2.5 ## s: "about to squeeze" window
signal echo_pulsed(counts: Dictionary)
var echo_marks: Array = [] ## [{pos, kind}] from the last pulse (tests)
var echo_counts: Dictionary = {}
var _echo_mm: MultiMeshInstance3D
var _echo_age := 99.0

## Offsets inside the pulse sphere, nearest first (built once).
static var _echo_offsets: Array = []
const ECHO_PER_FRAME := 450 ## samples per frame: the pulse spreads out in ~0.3 s
var _echo_scan := -1
var _echo_origin := Vector3.ZERO
var _echo_time := 0.0

static func _offsets() -> Array:
	if _echo_offsets.is_empty():
		var n := int(ECHO_RADIUS / ECHO_STEP)
		for ix in range(-n, n + 1):
			for iy in range(-n, n + 1):
				for iz in range(-n, n + 1):
					var off := Vector3(ix, iy, iz) * ECHO_STEP
					var dist := off.length()
					if dist <= ECHO_RADIUS and dist >= 0.3:
						_echo_offsets.append(off)
		_echo_offsets.sort_custom(func(x: Vector3, y: Vector3): return x.length_squared() < y.length_squared())
	return _echo_offsets

## Start a pulse from the player. immediate=true scans everything now
## (tests); otherwise the scan runs ECHO_PER_FRAME samples a frame and the
## marks appear as the pulse travels outward.
func echo_pulse(immediate: bool = true) -> Dictionary:
	_echo_origin = m.player.global_position + Vector3(0, 1.4, 0)
	_echo_time = m.terrain.contract_time
	_echo_age = 0.0
	echo_marks.clear()
	_echo_scan = 0
	var tn = m.get("tumor_nodes")
	if tn is Array:
		for tu in tn:
			if is_instance_valid(tu) and (tu as Node3D).is_visible_in_tree() and (tu as Node3D).global_position.distance_to(_echo_origin) <= ECHO_RADIUS * 2.0:
				echo_marks.append({"pos": (tu as Node3D).global_position, "kind": Echo.TUMOR})
	if immediate:
		_echo_scan_some(1 << 30)
	else:
		_draw_echo()
	return echo_counts

func _echo_scan_some(budget: int) -> void:
	var offs := _offsets()
	var t: FDKTerrainField = m.terrain
	var end := mini(offs.size(), _echo_scan + budget)
	for i in range(_echo_scan, end):
		var off: Vector3 = offs[i]
		var p := _echo_origin + off
		var d := t.density_at(p)
		var dir := off.normalized()
		if d < FDKTissueRules.EMPTY_DENSITY:
			# regrowing: an opened cell whose flesh is coming back
			if d > 0.15 and not t.is_sealed_at(p) and t.regen_multiplier_at(p) > 0.0:
				echo_marks.append({"pos": p, "kind": Echo.REGROW})
			continue
		# only the face of the wall the pulse hits
		if t.density_at(p - dir * ECHO_STEP) >= FDKTissueRules.EMPTY_DENSITY:
			continue
		var tissue := t.tissue_at(p)
		if tissue == FPProgression.TISSUE_NERVE:
			echo_marks.append({"pos": p, "kind": Echo.NERVE})
		elif tissue == FPProgression.TISSUE_CONTRACTILE and _squeeze_in(p, _echo_time) <= ECHO_SQUEEZE_LEAD:
			echo_marks.append({"pos": p, "kind": Echo.SQUEEZE})
		elif tissue != FPProgression.TISSUE_MEMBRANE and t.density_at(p + dir * ECHO_THIN) < FDKTissueRules.EMPTY_DENSITY:
			echo_marks.append({"pos": p, "kind": Echo.THIN})
	_echo_scan = end
	echo_counts = {}
	for k in ECHO_COLORS.keys():
		echo_counts[k] = 0
	for e in echo_marks:
		echo_counts[e.kind] = int(echo_counts[e.kind]) + 1
	_draw_echo()
	if _echo_scan >= offs.size():
		_echo_scan = -1
		echo_pulsed.emit(echo_counts)
## Seconds until the periodic squeeze at p starts (0 while squeezing).
static func _squeeze_in(p: Vector3, time: float) -> float:
	var c := fposmod(time + FDKTissueRules.contract_phase(p), FDKTissueRules.CONTRACT_PERIOD)
	if c < FDKTissueRules.CONTRACT_RISE + FDKTissueRules.CONTRACT_HOLD:
		return 0.0
	return FDKTissueRules.CONTRACT_PERIOD - c

func _draw_echo() -> void:
	if _echo_mm == null:
		_echo_mm = MultiMeshInstance3D.new()
		_echo_mm.name = "EchoMarks"
		_echo_mm.top_level = true
		_echo_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		sm.radial_segments = 4
		sm.rings = 2
		mm.mesh = sm
		_echo_mm.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true # the pulse sees through the flesh
		_echo_mm.material_override = mat
		m.add_child(_echo_mm)
	var mm2 := _echo_mm.multimesh
	mm2.instance_count = echo_marks.size()
	for i in range(echo_marks.size()):
		var e: Dictionary = echo_marks[i]
		var sc := 2.2 if e.kind == Echo.TUMOR else 1.0
		mm2.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sc), e.pos))
		mm2.set_instance_color(i, ECHO_COLORS[e.kind])
	_echo_mm.visible = true

func _step_echo_marks(delta: float) -> void:
	if _echo_mm == null:
		return
	if not m.progression.has_mutation("T1"):
		_echo_mm.visible = false
		_echo_scan = -1
		return
	if _echo_scan >= 0:
		_echo_scan_some(ECHO_PER_FRAME)
	_echo_age += delta
	var a := clampf(1.0 - _echo_age / 1.2, 0.0, 1.0)
	(_echo_mm.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.25 + 0.75 * a)

# --- M23 sensory hairs ------------------------------------------------------

signal hair_shiver_started ## sound hook: dry rustle of stiff arm hairs
var hair_shiver := 0.0 ## 0..1 how hard the arm hairs shake now
var hair_warnings := 0 ## warnings raised (tests)
var _shiver_on := false
var _shiver_scan_t := 0.0
var _squeeze_eta := 99.0

## Seconds until the next squeeze that will reach the player: the periodic
## squeeze of nearby contractile walls, or the nerve the blender is plugged
## into (fp_tissue_tools, read only).
func squeeze_eta() -> float:
	var eta := _squeeze_eta
	var tt = m.get("tissue_tools")
	if tt != null and tt.plugged:
		eta = minf(eta, maxf(0.0, float(tt._next_contract) - float(tt.plug_t)))
	return eta

func _scan_squeeze() -> void:
	_squeeze_eta = 99.0
	var t: FDKTerrainField = m.terrain
	var pp: Vector3 = m.player.global_position + Vector3(0, 0.9, 0)
	var r := 2.0
	var s := 0.5
	var n := int(r / s)
	for ix in range(-n, n + 1):
		for iy in range(-n, n + 1):
			for iz in range(-n, n + 1):
				var p := pp + Vector3(ix, iy, iz) * s
				if p.distance_to(pp) > r:
					continue
				if t.tissue_at(p) != FPProgression.TISSUE_CONTRACTILE or t.density_at(p) < FDKTissueRules.EMPTY_DENSITY:
					continue
				var c := fposmod(t.contract_time + FDKTissueRules.contract_phase(p), FDKTissueRules.CONTRACT_PERIOD)
				_squeeze_eta = minf(_squeeze_eta, FDKTissueRules.CONTRACT_PERIOD - c)

func _step_hair_shiver(delta: float) -> void:
	if not m.progression.has_mutation("M23"):
		hair_shiver = 0.0
		_shiver_on = false
		return
	_shiver_scan_t -= delta
	if _shiver_scan_t <= 0.0:
		_shiver_scan_t = 0.2
		_scan_squeeze()
	else:
		_squeeze_eta -= delta
	var eta := squeeze_eta()
	var on := eta <= FPProgression.HAIR_WARN_TIME
	if on and not _shiver_on:
		hair_warnings += 1
		hair_shiver_started.emit()
	_shiver_on = on
	hair_shiver = clampf(1.0 - eta / FPProgression.HAIR_WARN_TIME, 0.2, 1.0) if on else 0.0
	_shake_bristles()

func _shake_bristles() -> void:
	var rig = m.get("hands_rig")
	if rig == null or not is_instance_valid(rig):
		return
	var tm := Time.get_ticks_msec() * 0.001
	for b in (rig as Node).find_children("MutDeco_Bristles*", "Node3D", true, false):
		var n3 := b as Node3D
		if not n3.has_meta("rest"):
			n3.set_meta("rest", n3.position)
		var rest: Vector3 = n3.get_meta("rest")
		var j := hair_shiver * 0.004
		n3.position = rest + Vector3(sin(tm * 71.0), cos(tm * 83.0), sin(tm * 59.0)) * j

## M22 / tests: tear one cell in reach with the left hand, even when full.
func alien_tear() -> bool:
	var hit: Dictionary = m._look_hit()
	if hit.is_empty() or not hit.collider.has_meta("fdk_terrain_chunk"):
		return false
	var dir: Vector3 = m.player.get_look_ray()[1]
	var at: Vector3 = hit.position + dir * m.terrain_config.cell_size * 0.5
	if not m.terrain.is_edible_at(at):
		return false
	m.terrain.dig_at(at, 1.0)
	m.stomach.add_flesh(m.stomach_config.flesh_per_cell)
	m.progression.on_flesh_eaten(m.shell_at(at))
	alien_tears += 1
	alien_hand_tore.emit()
	return true

## M15: the whole pile goes down at once, no blender packing.
func gulp() -> void:
	m.stomach.add_flesh(m.carried_flesh)
	for s in m.carried_units.keys():
		m.progression.on_flesh_eaten(int(s), int(m.carried_units[s]))
	m.carried_flesh = 0.0
	m.carried_units.clear()
	_gulp_t = -1.0
	gulped.emit()

## tear_cells > 1 (M07, M14): each tear also takes the next cells behind it.
func _on_torn(world_pos: Vector3) -> void:
	if _extra_tearing:
		return
	var n: int = m.progression.tear_cells() - 1
	if n <= 0:
		return
	_extra_tearing = true
	var dir: Vector3 = m.player.get_look_ray()[1]
	for i in range(n):
		var at: Vector3 = world_pos + dir * m.terrain_config.cell_size * float(i + 1)
		if m.terrain.density_at(at) < 0.5 or not m.terrain.is_edible_at(at):
			break
		m.terrain.dig_at(at, 1.0)
		if m.carry_mode:
			m.carried_flesh += m.stomach_config.flesh_per_cell
			var sh: int = m.shell_at(at)
			m.carried_units[sh] = int(m.carried_units.get(sh, 0)) + 1
		else:
			m.stomach.add_flesh(m.stomach_config.flesh_per_cell)
			m.progression.on_flesh_eaten(m.shell_at(at))
	_extra_tearing = false

## T7: standing still stops regrowth within 1.5 m (main adds these blockers).
func extra_regen_blockers() -> Array:
	var p: FPProgression = m.progression
	if p.has_mutation("T7") and _still_t > 0.2:
		var pp: Vector3 = m.player.global_position
		return [Vector4(pp.x, pp.y, pp.z, FPProgression.RIB_FAN_RADIUS)]
	return []

## M29: a crush death only curls the body up; 30 s later it wakes in the
## restroom with everything but the stomach flesh.
func _on_died(cause: String) -> void:
	var p: FPProgression = m.progression
	if cause != "crush" or not p.has_mutation("M29"):
		return
	var dd: FDKDeathDrop = m.death_drop
	var items: Dictionary = dd.items.duplicate(true)
	items["stomach_fill"] = 0.0
	items["pending_hairs"] = {}
	p.restore_death_payload(items)
	dd.active = false
	dd.visible = false
	_dormant_t = 0.0
	m.player.set_physics_process(false)

func is_dormant() -> bool:
	return _dormant_t >= 0.0

func _step_dormant(delta: float) -> void:
	if _dormant_t < 0.0:
		return
	_dormant_t += delta
	if _dormant_t >= FPProgression.DORMANT_WAKE:
		_dormant_t = -1.0
		m.player.set_physics_process(true)

func _step_codex() -> void:
	# session B posts a paper per settled tumor (main.drawing_nodes): dress
	# each one with the crayon sheet; the stand-alone wall codex is only a
	# fallback when that feature is absent
	var papers = m.get("drawing_nodes")
	if papers is Array:
		if codex != null:
			codex.visible = false
		for paper in papers:
			if not is_instance_valid(paper) or paper.has_meta("crayon"):
				continue
			paper.set_meta("crayon", true)
			var kind := String(paper.get_meta("tumor_kind", "core_knot"))
			if paper is MeshInstance3D:
				(paper as MeshInstance3D).mesh = null
			for c in paper.get_children():
				(c as Node3D).visible = false
			var one: Node3D = (load("res://main/art/fp_tumor_codex.gd") as GDScript).new()
			one.name = "Crayon"
			paper.add_child(one)
			one.rotation.y = -PI * 0.5
			one.call("set_found", [kind])
			var s: Node3D = one.call("sheet", kind)
			if s != null:
				s.position = Vector3.ZERO
		return
	var p: FPProgression = m.progression
	var n := p.tumors.codex_count()
	if n == _codex_n or codex == null:
		return
	_codex_n = n
	var found: Array = []
	for k in FPProgression.TUMOR_KINDS:
		if p.tumors.is_in_codex(k):
			found.append(k)
	codex.call("set_found", found)
## M03: 0..1 low hum in the ears while facing the restroom (none without M03).
func magnet_hum_level() -> float:
	if not m.progression.has_mutation("M03"):
		return 0.0
	var ray: Array = m.player.get_look_ray()
	var to: Vector3 = (m.RESTROOM_CENTER + Vector3(0, 1, 0)) - (ray[0] as Vector3)
	if to.length() < 0.5:
		return 0.0
	return clampf((to.normalized().dot(ray[1]) - 0.7) / 0.3, 0.0, 1.0)
