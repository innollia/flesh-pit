extends Node3D

## Small bits and droplets thrown out of a tear or a splash. No engine
## particles: a few CPU-moved MultiMesh instances with the PS1 materials
## everything else uses. They fly, fall onto the floor found under the burst
## (one ray per burst), lie there squashed for a moment and shrink away.

const MAX_BITS := 48
const MAX_DROPS := 96
const GRAVITY := 9.8
const BLOOD := Color(0.42, 0.03, 0.05)
const BILE := Color(0.64, 0.7, 0.2)

var _bits: MultiMeshInstance3D
var _drops: MultiMeshInstance3D
var _live_bits: Array = []
var _live_drops: Array = []
var _seed := 0

func _ready() -> void:
	_bits = _make_layer("Bits", MAX_BITS, "res://addons/flesh_dig_kit/textures/tex_torn_chunk_128.png", 0.7, 0.45, 51)
	_drops = _make_layer("Drops", MAX_DROPS, "res://addons/flesh_dig_kit/textures/tex_membrane_128.png", 0.95, 0.3, 52)

func _make_layer(layer_name: String, count: int, tex: String, wet: float, lumps: float, seed: int) -> MultiMeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	FDKLowPoly.add_blob(st, Vector3.ZERO, Vector3.ONE, lumps, seed, Color(1, 1, 1), Color(0.86, 0.8, 0.8))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = FDKLowPoly.with_box_uvs(st.commit(), 0.7)
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = layer_name
	mi.multimesh = mm
	mi.material_override = FDKPs1Material.get_material(tex, 1.0, true, wet, 0.4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _rand() -> float:
	_seed += 1
	return FDKLowPoly.hash3(_seed, _seed * 7 + 3, 11)

func _spread(out: Vector3, cone: float) -> Vector3:
	var d := out + Vector3(_rand() - 0.5, _rand() - 0.5, _rand() - 0.5) * 2.0 * cone
	return d.normalized() if d.length() > 0.001 else Vector3.UP

## Throws `bits` flesh bits and `drops` droplets of `color` from `at`,
## mostly along `out` (spread by `cone`), at `speed` m/s give or take.
func burst(at: Vector3, out: Vector3, bits: int, drops: int, color: Color = BLOOD, speed: float = 1.4, cone: float = 0.7) -> void:
	if not is_inside_tree():
		return
	var floor_y := at.y - 2.5
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.02, at + Vector3.DOWN * 2.5)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		floor_y = (hit.position as Vector3).y
	for i in range(bits):
		if _live_bits.size() >= MAX_BITS:
			_live_bits.pop_front()
		var life := 0.9 + 0.6 * _rand()
		_live_bits.append({
			"pos": at, "vel": _spread(out, cone) * speed * (0.6 + 0.6 * _rand()) + Vector3.UP * 0.5,
			"life": life, "max": life, "size": 0.01 + 0.008 * _rand(),
			"color": Color(1, 1, 1).lerp(Color(0.8, 0.55, 0.55), _rand()),
			"spin": Vector3(_rand() - 0.5, _rand() - 0.5, _rand() - 0.5) * 30.0, "rot": Basis(),
			"floor": floor_y, "landed": false,
		})
	for i in range(drops):
		if _live_drops.size() >= MAX_DROPS:
			_live_drops.pop_front()
		var life := 0.6 + 0.5 * _rand()
		_live_drops.append({
			"pos": at, "vel": _spread(out, cone * 1.2) * speed * (0.8 + 0.8 * _rand()) + Vector3.UP * 0.4,
			"life": life, "max": life, "size": 0.0035 + 0.004 * _rand(),
			"color": color.lerp(color.darkened(0.35), _rand()),
			"spin": Vector3.ZERO, "rot": Basis(),
			"floor": floor_y, "landed": false,
		})

func live_count() -> int:
	return _live_bits.size() + _live_drops.size()

func _process(delta: float) -> void:
	_step(_live_bits, _bits.multimesh, delta, false)
	_step(_live_drops, _drops.multimesh, delta, true)

func _step(list: Array, mm: MultiMesh, delta: float, drop: bool) -> void:
	if list.is_empty():
		mm.visible_instance_count = 0
		return
	var keep: Array = []
	for p in list:
		p.life -= delta
		if p.life <= 0.0:
			continue
		if not p.landed:
			p.vel.y -= GRAVITY * delta
			p.vel *= 1.0 - 1.2 * delta
			p.pos += p.vel * delta
			if p.spin != Vector3.ZERO:
				p.rot = p.rot * Basis.from_euler(p.spin * delta)
			if p.pos.y <= p.floor + p.size * 0.5:
				p.pos.y = p.floor + p.size * 0.4
				p.landed = true
				# a landed piece lies a while, then shrinks
				p.life = minf(p.life + 0.6, p.max)
		keep.append(p)
	list.assign(keep)
	mm.visible_instance_count = list.size()
	for i in range(list.size()):
		var p: Dictionary = list[i]
		var fade := clampf(p.life / (0.35 * p.max), 0.0, 1.0)
		var s: float = p.size * fade
		var shape := Vector3(1.6, 0.35, 1.6) if p.landed else (Vector3(0.8, 0.8, 1.6) if drop else Vector3.ONE)
		var b: Basis = Basis.IDENTITY if p.landed else p.rot
		if drop and not p.landed and p.vel.length() > 0.2:
			# droplets stretch along their flight
			var f: Vector3 = p.vel.normalized()
			var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT
			b = Basis.looking_at(f, up)
		mm.set_instance_transform(i, Transform3D(b * Basis.from_scale(shape * s), p.pos))
		mm.set_instance_color(i, p.color)
