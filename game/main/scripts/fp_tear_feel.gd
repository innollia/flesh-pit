extends Node3D

## How a tear feels (2026-11-03: "살을 팔때 이펙트가 작음 ... 뿅 뿅 하고
##사라지는 느낌"). The real removal, its density and the published hole stay
## exactly where the chewer and terrain put them; everything here is an
## additive visual on top of that real hole:
## - while pulling, the stretched flesh oozes a few drops (the stretch itself
##   is the terrain shader's press, with its own reach-distance cap)
## - at the snap: wet strands from the hole rim to the fist stretch and break,
##   the rim springs back (terrain shader snap), a big spray of bits and blood,
##   and a short view jolt (composed by fp_danger_show into camera offsets)
## - after: the last few hole rims stay wet with blood, fading over seconds.
## Work is bounded: MAX_STRANDS strand pieces (a broken strand draws two),
## MAX_WOUNDS shader slots.
## Each tissue tears its own way (FDKTissueRules.look of the torn cell): how
## far it stretches, the colour and number of drops, how many strands and
## when they break, how hard the view is yanked. Plain flesh is the look this
## had before; the terrain shader colours the wound rim from the same table.

const MAX_STRANDS := 16
const STRANDS_PER_TEAR := 5
const MAX_WOUNDS := FDKChunk.WOUND_SLOTS
const WOUND_LIFE := 14.0
const SNAP_OFF := 99.0
const SNAP_END := FDKChunk.SNAP_END
const JOLT_TIME := 0.3
## An overfull stomach makes the same tear heavier (heavy 0..1 = the stomach's
## overfill ratio at the tear): a longer, bigger, slower jolt that widens less.
const JOLT_TIME_HEAVY := 0.5
const JOLT_AMP := 0.035
const JOLT_AMP_HEAVY := 1.4
const JOLT_DECAY := 3.5
const JOLT_DECAY_HEAVY := 2.2
const JOLT_WIDEN := 0.05
const JOLT_WIDEN_HEAVY := 0.02
## The swallow that follows a tear that is eaten: a small nod of the head.
const NOD_TIME := 0.18
const NOD_DROP := 0.008
const STRAND_LIFE := 0.6
const BLOOD := FDKTissueRules.BLOOD

var terrain: FDKTerrainField
var gore: Node3D
## Where the torn flesh is held: Callable() -> Node3D (the hand chunk) or null.
var grip_node: Callable

var _snap_age := SNAP_OFF
var _snap_center := Vector3.ZERO
var _snap_toward := Vector3.BACK
var _wounds: Array = [] ## {pos: Vector3, age: float}
var _wounds_dirty := false
var _wound_push_wait := 0.0
var _strands: Array = []
var _strand_mm: MultiMeshInstance3D
var _jolt_t := JOLT_TIME
var _jolt_len := JOLT_TIME
var _jolt_heavy := 0.0
## The torn tissue's recoil scale (FDKTissueRules.look().recoil).
var _jolt_recoil := 1.0
## 0..1, set by the game every frame: how overfull the eater is.
var heavy := 0.0
var _nod_wait := -1.0
var _nod_t := NOD_TIME
var _jolt_dir := Vector2.ZERO
var _last_ratio := 0.0
var _seed := 0
## Strand instances written last tick (work count for the budget check).
var last_strand_writes := 0

func _ready() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# unit strand: a 5-sided tube from z=0 to z=-1, radius 1, fatter at the ends
	var sides := 5
	var rings := [[0.0, 1.0], [-0.5, 0.55], [-1.0, 1.0]]
	for r in range(rings.size() - 1):
		var z0: float = rings[r][0]
		var z1: float = rings[r + 1][0]
		var w0: float = rings[r][1]
		var w1: float = rings[r + 1][1]
		for k in range(sides):
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var p00 := Vector3(cos(a0) * w0, sin(a0) * w0, z0)
			var p01 := Vector3(cos(a1) * w0, sin(a1) * w0, z0)
			var p10 := Vector3(cos(a0) * w1, sin(a0) * w1, z1)
			var p11 := Vector3(cos(a1) * w1, sin(a1) * w1, z1)
			# both windings: thin enough that the cost is nil, and no face
			# vanishes whichever way the tube is seen
			for q in [p00, p10, p11, p00, p11, p01, p00, p11, p10, p00, p01, p11]:
				st.set_color(Color(1, 1, 1))
				st.set_uv(Vector2((q as Vector3).x * 0.5 + 0.5, -(q as Vector3).z))
				st.add_vertex(q)
	st.generate_normals()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = st.commit()
	mm.instance_count = MAX_STRANDS
	mm.visible_instance_count = 0
	_strand_mm = MultiMeshInstance3D.new()
	_strand_mm.name = "Strands"
	_strand_mm.multimesh = mm
	_strand_mm.material_override = FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_membrane_128.png", 1.0, true, 0.95, 0.25)
	_strand_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_strand_mm)

func _rand() -> float:
	_seed += 1
	return FDKLowPoly.hash3(_seed, _seed * 13 + 5, 29)

## Every chew frame: `ratio` 0..1 toward the tear at real contact `contact`,
## `toward` from the wall toward the eater, `tissue` the id of the held cell.
func on_chew(ratio: float, contact: Vector3, toward: Vector3, tissue: int = FDKTissueRules.COMPRESSIVE) -> void:
	var look := FDKTissueRules.look(tissue)
	if gore != null and contact != Vector3.INF and int(look.drops) > 0:
		# the stretched flesh weeps as it nears the tear
		for edge in [0.55, 0.8, 0.93]:
			if _last_ratio < edge and ratio >= edge:
				gore.burst(contact + toward * 0.04, (toward * 0.3 + Vector3.DOWN).normalized(), 0, 2, look.blood, 0.35, 0.35)
	_last_ratio = ratio

## A real tear at `world_pos` (density already removed and published by the
## terrain this frame). `eye` is the camera position, `tissue` the id of the
## cell that came away.
func on_tear(world_pos: Vector3, eye: Vector3, tissue: int = FDKTissueRules.COMPRESSIVE) -> void:
	var look := FDKTissueRules.look(tissue)
	var drops := int(look.drops)
	_last_ratio = 0.0
	var toward := eye - world_pos
	toward = toward.normalized() if toward.length() > 0.01 else Vector3.UP
	# the front of the hole, where its rim faces the eater
	var mouth := world_pos + toward * 0.22
	_snap_center = mouth
	_snap_toward = toward
	_snap_age = 0.0
	_add_wound(world_pos)
	_spawn_strands(mouth, toward, look)
	if gore != null:
		# a fistful comes away: chunky bits and a wet spray out of the rim
		# (plain flesh: 18 drops and 10 more running down; a dry tissue none)
		gore.burst(mouth, toward, 6, drops, look.blood, 1.7, 0.75, 1.9)
		gore.burst(mouth - toward * 0.05, (toward + Vector3.DOWN * 1.2).normalized(), 2, roundi(drops * 10.0 / 18.0), look.blood, 0.7, 0.5, 1.4)
	_jolt_t = 0.0
	_jolt_recoil = float(look.recoil)
	_jolt_heavy = clampf(heavy, 0.0, 1.0)
	_jolt_len = lerpf(JOLT_TIME, JOLT_TIME_HEAVY, _jolt_heavy)
	_jolt_dir = Vector2(_rand() - 0.5, 1.0).normalized()
	# the first frame that shows the hole already shows its rim recoiling
	if terrain != null:
		terrain.set_snap(_snap_center, _snap_toward, 0.0)
		_push_wounds()

func _add_wound(at: Vector3) -> void:
	for w in _wounds:
		if (w.pos as Vector3).distance_to(at) < 0.2:
			w.age = 0.0
			_wounds_dirty = true
			return
	if _wounds.size() >= MAX_WOUNDS:
		_wounds.pop_front()
	_wounds.append({"pos": at, "age": 0.0})
	_wounds_dirty = true

func _spawn_strands(mouth: Vector3, toward: Vector3, look: Dictionary = FDKTissueRules.LOOK_PLAIN) -> void:
	var count := int(look.strands)
	var own: Color = look.strand_color
	var side := toward.cross(Vector3.UP)
	if side.length() < 0.1:
		side = toward.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(toward).normalized()
	for i in range(count):
		if _strands.size() >= MAX_STRANDS / 2:
			_strands.pop_front()
		var ang := TAU * (float(i) + _rand() * 0.6) / count
		var rad := 0.1 + 0.12 * _rand()
		_strands.append({
			"anchor": mouth + (side * cos(ang) + up * sin(ang)) * rad,
			"grip": mouth + toward * 0.4, # replaced by the fist while it holds the chunk
			"age": 0.0,
			"snap": lerpf(float(look.snap_from), float(look.snap_to), _rand()), # when it breaks
			"cut": 0.35 + 0.35 * _rand(), # where along it breaks
			"radius": (0.006 + 0.006 * _rand()) * float(look.strand_thin),
			"sag": Vector3.ZERO,
			"tail": Vector3.ZERO,
			# plain flesh: blood-wet membrane; a tissue with its own strands
			# (nerve cord, fat, hair) keeps its colour
			"color": BLOOD.lerp(Color(0.85, 0.42, 0.42), 0.25 + 0.35 * _rand()) if own.a <= 0.0 else Color(own.r, own.g, own.b).lightened(0.2 * _rand()),
		})

func tick(delta: float) -> void:
	if terrain != null:
		if _snap_age < SNAP_OFF:
			_snap_age += delta
			if _snap_age >= SNAP_END:
				_snap_age = SNAP_OFF
			terrain.set_snap(_snap_center, _snap_toward, _snap_age)
		if not _wounds.is_empty():
			var keep: Array = []
			for w in _wounds:
				w.age += delta
				if w.age < WOUND_LIFE:
					keep.append(w)
			# the rims fade over seconds: refresh the shader five times a second
			_wound_push_wait -= delta
			if keep.size() != _wounds.size() or _wound_push_wait <= 0.0:
				_wounds_dirty = true
			_wounds = keep
		if _wounds_dirty:
			_push_wounds()
	if _jolt_t < _jolt_len:
		_jolt_t += delta
	if _nod_wait >= 0.0:
		_nod_wait -= delta
		if _nod_wait < 0.0:
			_nod_t = 0.0
	elif _nod_t < NOD_TIME:
		_nod_t += delta
	_step_strands(delta)

func _push_wounds() -> void:
	var packed := PackedVector4Array()
	for w in _wounds:
		var fresh := 1.0 - smoothstep(WOUND_LIFE * 0.35, WOUND_LIFE, float(w.age))
		packed.append(Vector4(w.pos.x, w.pos.y, w.pos.z, fresh))
	terrain.set_wounds(packed)
	_wounds_dirty = false
	_wound_push_wait = 0.2

func _grip_position() -> Variant:
	if not grip_node.is_valid():
		return null
	var n = grip_node.call()
	if n is Node3D and (n as Node3D).is_inside_tree():
		return (n as Node3D).global_position
	return null

func _step_strands(delta: float) -> void:
	last_strand_writes = 0
	var mm := _strand_mm.multimesh
	if _strands.is_empty():
		mm.visible_instance_count = 0
		return
	var grip = _grip_position()
	var keep: Array = []
	for s in _strands:
		s.age += delta
		if s.age >= STRAND_LIFE:
			continue
		if s.age < s.snap and grip != null:
			s.grip = grip
		keep.append(s)
	_strands = keep
	var n := 0
	for s in _strands:
		if n + 2 > MAX_STRANDS:
			break
		var a: Vector3 = s.anchor
		var b: Vector3 = s.grip
		if s.age < s.snap:
			# stretched taut and thinning toward the break
			var thin := lerpf(1.0, 0.45, s.age / s.snap)
			_put(n, a, b, s.radius * thin, s.color)
			n += 1
		else:
			# broken: the wall half recoils and droops, the fist half whips in
			var t: float = s.age - s.snap
			var life: float = STRAND_LIFE - s.snap
			var fade := clampf(1.0 - t / life, 0.0, 1.0)
			var cut: Vector3 = a.lerp(b, s.cut)
			var back := 1.0 - exp(-t * 9.0)
			var droop := Vector3.DOWN * (0.6 * t * t + 0.05 * back)
			var wall_end: Vector3 = cut.lerp(a, back * 0.55) + droop
			_put(n, a, wall_end, s.radius * 0.8 * fade, s.color)
			n += 1
			var fist_end: Vector3 = cut.lerp(b, back * 0.85) + droop * 0.5
			_put(n, b, fist_end, s.radius * 0.7 * fade, s.color)
			n += 1
	mm.visible_instance_count = n
	last_strand_writes = n

func _put(i: int, from: Vector3, to: Vector3, radius: float, color: Color) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.002 or radius <= 0.0001:
		_strand_mm.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), from))
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	var b := Basis.looking_at(d / length, up)
	_strand_mm.multimesh.set_instance_transform(i, Transform3D(b * Basis.from_scale(Vector3(radius, radius, length)), from))
	_strand_mm.multimesh.set_instance_color(i, color)

## Camera offset (h, v) of the snap jolt for fp_danger_show; zero at rest.
func jolt_offset() -> Vector2:
	var nod := Vector2.ZERO
	if _nod_wait < 0.0 and _nod_t < NOD_TIME:
		var n := _nod_t / NOD_TIME
		nod = Vector2(0.0, -NOD_DROP * (1.0 - n) * (1.0 - n))
	if _jolt_t >= _jolt_len:
		return nod
	var u := _jolt_t / _jolt_len
	# kicked at once, one rebound, settled (a body yanked by its own hands)
	var k := exp(-u * lerpf(JOLT_DECAY, JOLT_DECAY_HEAVY, _jolt_heavy)) * sin(u * PI * 2.5 + 0.9)
	return _jolt_dir * JOLT_AMP * _jolt_recoil * lerpf(1.0, JOLT_AMP_HEAVY, _jolt_heavy) * k * (1.0 - u) + nod

## The torn flesh goes down `delay` seconds from now: the head nods once.
func on_swallow(delay: float) -> void:
	_nod_wait = maxf(delay, 0.0)

## Seconds the current (or last) jolt lasts (tests).
func jolt_length() -> float:
	return _jolt_len

## FOV scale of the jolt (a brief widening as the body is yanked back).
func jolt_fov() -> float:
	if _jolt_t >= _jolt_len:
		return 1.0
	var u := _jolt_t / _jolt_len
	return 1.0 + lerpf(JOLT_WIDEN, JOLT_WIDEN_HEAVY, _jolt_heavy) * sin(minf(u * 2.5, 1.0) * PI) * (1.0 - u)

func live_strands() -> int:
	return _strands.size()

func wound_count() -> int:
	return _wounds.size()

func snap_age() -> float:
	return _snap_age

func debug_state() -> Dictionary:
	return {"snap_age": _snap_age, "wounds": _wounds.size(), "strands": _strands.size(), "strand_writes": last_strand_writes, "jolt": str(jolt_offset()), "fov": jolt_fov()}
