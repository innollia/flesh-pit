extends Node3D

## Intact tumor lump (carried whole or eaten), one model per kind in
## FPProgression.TUMOR_KINDS order (docs/spec/03-restroom.md 10), each with
## what it does in the flesh:
##   0 core_knot    teratoma: smooth ball, teeth and a hair tuft    - lies still
##   1 core_bulb    cyst: translucent water balloon, a clot floats  - slowly swells and settles
##   2 mantle_coil  myoma: muscle cords wound like a ball of yarn   - squeezes with the 8 s contraction beat
##   3 mantle_sac   fetus in fetu: a sac with a small hand inside   - palm on the wall, pulls back when you come near
##   4 surface_star neuroma: yellow nerve strands in a star         - flashes when touched
##   5 surface_ear  accessory auricles: little ears in a bunch      - all the ears turn toward you together
## Origin = centre, about basketball-to-melon size. Public: set_variant(0..5),
## variant(), set_pulse(bool) (false = a still prop, e.g. in the hand),
## flash(), static build_mesh(kind) -> ArrayMesh (one opaque mesh, used by
## the tumor bag), static watch_pos/watch_on (the player's eye, set by
## fp_art_hookup every frame).

const K := preload("res://main/art/fp_art_kit.gd")
const R := 0.11
const KINDS := 6
## contraction beat (docs/spec/02-world-tissue.md 수축 조직의 주기 수축)
const BEAT := 8.0
const BEAT_RISE := 1.5
const BEAT_HOLD := 1.0
const BEAT_RELEASE := 2.0
const SAC_SHY := 2.5 ## m: the twin's hand leaves the wall inside this
const STAR_TOUCH := 0.9 ## m: the neuroma flashes when you are this close
const EAR_COUNT := 9

static var watch_pos := Vector3.ZERO
static var watch_on := false

var _mi: MeshInstance3D
var _parts: Array[Node3D] = []
var _variant := 0
var _pulse := true
var _time := 0.0
var _phase := 0.0
var _flash := 0.0
var _flash_cool := 0.0
var _shy := 0.0
var _glow: MeshInstance3D
var _float: Node3D
var _hand: Node3D
var _ears: Array[Node3D] = []

func _ready() -> void:
    _mi = K.add_mesh(self, "Tumor", ArrayMesh.new(), K.mat("tex_skin_128.png", 0.75, true))
    set_variant(_variant)

func set_variant(v: int) -> void:
    _variant = clampi(v, 0, KINDS - 1)
    if _mi == null:
        return
    for p in _parts:
        p.queue_free()
    _parts.clear()
    _ears.clear()
    _glow = null
    _float = null
    _hand = null
    _phase = K.h(int(global_position.x * 37.0), int(global_position.z * 53.0)) * BEAT if is_inside_tree() else 0.0
    match _variant:
        1:
            _mi.mesh = _floater_mesh()
            _float = _mi
            _part("Shell", _cyst_shell(), _clear_mat(Color(0.86, 0.72, 0.62, 0.42)))
        3:
            _mi.mesh = _sac_mesh(false)
            var h := Node3D.new()
            h.name = "TwinHand"
            add_child(h)
            _parts.append(h)
            K.add_mesh(h, "Hand", _hand_mesh(), K.mat("tex_skin_128.png", 0.6, true))
            _hand = h
            _part("Skin", _sac_mesh(true), _clear_mat(Color(0.95, 0.7, 0.66, 0.32)))
        4:
            _mi.mesh = build_mesh(4)
            var g := MeshInstance3D.new()
            g.name = "Flash"
            g.mesh = _star_mesh(1.06)
            var gm := StandardMaterial3D.new()
            gm.vertex_color_use_as_albedo = true
            gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            gm.albedo_color = Color(1, 1, 1, 0.0)
            gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
            g.material_override = gm
            add_child(g)
            _parts.append(g)
            _glow = g
        5:
            _mi.mesh = _ear_base_mesh()
            var em := K.mat("tex_skin_128.png", 0.5, true)
            var ear := _ear_mesh()
            for i in range(EAR_COUNT):
                var d := _ear_dir(i)
                var e := Node3D.new()
                e.name = "Ear%d" % i
                e.position = d * R * 0.66
                add_child(e)
                _parts.append(e)
                var mi := K.add_mesh(e, "Mesh", ear, em)
                mi.scale = Vector3.ONE * (1.1 + K.h(i, 61) * 0.45)
                e.set_meta("rest", d)
                _ears.append(e)
        _:
            _mi.mesh = build_mesh(_variant)

func variant() -> int:
    return _variant

func set_pulse(on: bool) -> void:
    _pulse = on

## The neuroma lights up for a moment (05: 건드리면 반짝 빛남, no contraction).
func flash() -> void:
    _flash = 1.0
    _flash_cool = 1.5

func _part(n: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
    var mi := K.add_mesh(self, n, mesh, mat)
    _parts.append(mi)
    return mi

static func _clear_mat(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.vertex_color_use_as_albedo = true
    m.albedo_color = c
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.roughness = 0.15
    m.metallic_specular = 0.8
    m.cull_mode = BaseMaterial3D.CULL_BACK
    return m

func _process(delta: float) -> void:
    _time += delta
    _flash_cool = maxf(_flash_cool - delta, 0.0)
    var near := INF
    if watch_on:
        near = global_position.distance_to(watch_pos)
    if not _pulse:
        scale = Vector3.ONE
        return
    match _variant:
        1:
            # a slow breath; the clot drifts inside
            var s := 1.0 + sin(_time * TAU / 6.5) * 0.07
            scale = Vector3(s, s, s)
            if _float != null:
                _float.position = Vector3(sin(_time * 0.7) * 0.02, sin(_time * 0.43) * 0.025, cos(_time * 0.55) * 0.02)
                _float.rotation = Vector3(_time * 0.3, _time * 0.21, 0)
        2:
            var k := _beat(fmod(_time + _phase, BEAT))
            scale = Vector3(1.0 - 0.12 * k, 1.0 + 0.06 * k, 1.0 - 0.12 * k)
        3:
            var target := 1.0 if near < SAC_SHY else 0.0
            _shy = move_toward(_shy, target, delta * (3.0 if target > _shy else 0.6))
            if _hand != null:
                # the palm rests on the inside of the skin facing you (or the
                # front when nobody is around), and draws back into the dark
                var face := Vector3.BACK
                if watch_on:
                    var to := global_transform.affine_inverse() * watch_pos
                    if to.length() > 0.01:
                        face = to.normalized()
                face = (_hand.get_meta("face", face) as Vector3).slerp(face, minf(1.0, delta * 1.5)).normalized()
                _hand.set_meta("face", face)
                var b := Basis(Quaternion(Vector3.FORWARD, face))
                _hand.basis = b * Basis(Vector3.RIGHT, lerpf(0.0, 0.9, _shy))
                _hand.position = face * lerpf(R * 0.68, R * 0.18, _shy)
        4:
            if near < STAR_TOUCH and _flash_cool <= 0.0:
                flash()
            _flash = maxf(_flash - delta * 2.5, 0.0)
            if _glow != null:
                (_glow.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.95, 0.5, _flash * 0.9)
        5:
            for e in _ears:
                var rest: Vector3 = e.get_meta("rest")
                var want := rest
                if near < 6.0:
                    var to := (global_transform.affine_inverse() * watch_pos - e.position).normalized()
                    # turn toward you, but an ear never faces back into the lump
                    want = rest.slerp(to, 0.8) if to.dot(rest) > -0.3 else rest
                var cur: Vector3 = e.get_meta("look", rest)
                cur = cur.slerp(want, minf(1.0, delta * 6.0)).normalized()
                e.set_meta("look", cur)
                e.basis = Basis(Quaternion(Vector3.FORWARD, cur))

## 0..1 squeeze of the contraction beat at time t in [0, BEAT).
static func _beat(t: float) -> float:
    if t < BEAT_RISE:
        return smoothstep(0.0, BEAT_RISE, t)
    t -= BEAT_RISE
    if t < BEAT_HOLD:
        return 1.0
    t -= BEAT_HOLD
    if t < BEAT_RELEASE:
        return 1.0 - smoothstep(0.0, BEAT_RELEASE, t)
    return 0.0

## One opaque mesh per kind (the tumor bag, a held tumor, capture).
static func build_mesh(kind: int) -> ArrayMesh:
    var st := K.begin()
    var I := Transform3D.IDENTITY
    match kind:
        0:
            # teratoma: a smooth fatty ball, human teeth breaking the skin and a
            # wet black hair tuft growing out of one side
            K.blob(st, I, Vector3.ZERO, Vector3(R * 0.95, R * 0.85, R * 0.9), 0.08, 57, Color(0.86, 0.72, 0.56), Color(0.78, 0.6, 0.46))
            for i in range(6):
                var d := Vector3(K.h(i, 7) - 0.5, K.h(i, 8) * 0.9 - 0.2, K.h(i, 9) - 0.5).normalized()
                var p := d * 0.9 / sqrt(pow(d.x / (R * 0.95), 2) + pow(d.y / (R * 0.85), 2) + pow(d.z / (R * 0.9), 2))
                K.blob(st, I, p * 0.98, Vector3(0.017, 0.009, 0.017), 0.3, 120 + i, Color(0.62, 0.24, 0.2), Color(0.72, 0.38, 0.32))
                K.lathe(st, Transform3D(Basis(Quaternion(Vector3.UP, d)), p), [Vector2(0.0, -0.012), Vector2(0.012, -0.004), Vector2(0.014, 0.008), Vector2(0.008, 0.017), Vector2(0.0, 0.016)], 6, [Color(0.92, 0.86, 0.68)])
            var tuft := Vector3(-0.55, 0.65, 0.5).normalized()
            for i in range(46):
                var j := Vector3(K.h(i, 17) - 0.5, K.h(i, 18) - 0.5, K.h(i, 19) - 0.5) * 0.5
                var d := (tuft + j).normalized()
                var root := d * R * 0.84
                var tip := root + (d + Vector3(0, -0.6, 0)).normalized() * (0.05 + K.h(i, 20) * 0.05)
                K.tube(st, I, [root, root.lerp(tip, 0.5) + d * 0.01, tip], [0.0022, 0.0016, 0.0006], 3, [Color(0.04, 0.03, 0.03)], false)
        1:
            # cyst for the bag: the shell opaque, the clot drawn on it
            _add_mesh_into(st, _floater_raw())
            K.blob(st, I, Vector3.ZERO, Vector3(R * 0.95, R * 1.0, R * 0.95), 0.04, 66, Color(0.82, 0.66, 0.58), Color(0.9, 0.78, 0.7))
        2:
            # myoma: muscle cords wound round and round like a ball of yarn
            K.blob(st, I, Vector3.ZERO, Vector3(R * 0.78, R * 0.78, R * 0.78), 0.2, 77, Color(0.42, 0.1, 0.16), Color(0.5, 0.14, 0.22))
            for c in range(9):
                var ax := Vector3(K.h(c, 81) - 0.5, K.h(c, 82) - 0.5, K.h(c, 83) - 0.5).normalized()
                var b := Basis(Quaternion(Vector3.UP, ax))
                var pts: Array = []
                var radii: Array = []
                for k in range(15):
                    var a := TAU * float(k) / 14.0
                    var rr := R * (0.84 + 0.05 * sin(a * 3.0 + c))
                    pts.append(b * Vector3(cos(a) * rr, sin(a * 2.0 + c) * 0.012, sin(a) * rr))
                    radii.append(0.011 + 0.004 * sin(a * 2.0 + c * 1.7))
                var col := Color(0.62, 0.16, 0.2).lerp(Color(0.48, 0.18, 0.4), K.h(c, 84))
                K.tube(st, I, pts, radii, 5, [col], false)
        3:
            _add_mesh_into(st, _sac_raw(true))
            var hand := _hand_raw()
            st.append_from(hand, 0, Transform3D(Basis(Vector3.UP, PI), Vector3(0, -0.01, R * 0.66)))
        4:
            _add_mesh_into(st, _star_raw(1.0))
        _:
            _add_mesh_into(st, _ear_base_raw())
            var ear := _ear_raw()
            for i in range(EAR_COUNT):
                var d := _ear_dir(i)
                var s := 1.1 + K.h(i, 61) * 0.45
                st.append_from(ear, 0, Transform3D(Basis(Quaternion(Vector3.FORWARD, d)).scaled(Vector3.ONE * s), d * R * 0.66))
    return K.finish(st, 7.0)

static func _add_mesh_into(st: SurfaceTool, mesh: ArrayMesh) -> void:
    st.append_from(mesh, 0, Transform3D.IDENTITY)

# --- cyst -------------------------------------------------------------------

static func _cyst_shell() -> ArrayMesh:
    var st := K.begin()
    K.blob(st, Transform3D.IDENTITY, Vector3.ZERO, Vector3(R * 0.95, R * 1.0, R * 0.95), 0.04, 66, Color(1, 0.9, 0.85), Color(0.95, 0.82, 0.78))
    # a few red vessels on the skin
    for v in range(4):
        var pts: Array = []
        var a0 := v * TAU / 4.0 + 0.4
        for k in range(7):
            var t := float(k) / 6.0
            var el := lerpf(-0.9, 0.9, t)
            var az := a0 + sin(t * 4.0 + v) * 0.3
            pts.append(Vector3(cos(az) * cos(el), sin(el) * 1.05, sin(az) * cos(el)) * R * 0.97)
        K.tube(st, Transform3D.IDENTITY, pts, [0.0015, 0.0025, 0.002, 0.0015], 3, [Color(0.7, 0.15, 0.15)], false)
    return K.finish(st, 30.0)

func _floater_mesh() -> ArrayMesh:
    return _floater_raw()

static func _floater_raw() -> ArrayMesh:
    # a curled dark clot with a stringy tail, floating in the fluid
    var st := K.begin()
    K.blob(st, Transform3D.IDENTITY, Vector3.ZERO, Vector3(0.028, 0.022, 0.03), 0.4, 91, Color(0.35, 0.06, 0.08), Color(0.5, 0.15, 0.12))
    K.tube(st, Transform3D.IDENTITY, [Vector3(0.02, 0, 0.01), Vector3(0.04, -0.012, 0.025), Vector3(0.045, -0.03, 0.01)], [0.006, 0.004, 0.002], 4, [Color(0.4, 0.1, 0.1)], false)
    return K.finish(st, 20.0)

# --- twin sac ---------------------------------------------------------------

func _sac_mesh(skin: bool) -> ArrayMesh:
    return _sac_raw(skin)

## skin = the thin outer sac; otherwise the dark inside (so the hand reads).
static func _sac_raw(skin: bool) -> ArrayMesh:
    var st := K.begin()
    if skin:
        K.blob(st, Transform3D.IDENTITY, Vector3.ZERO, Vector3(R * 0.82, R * 0.95, R * 0.8), 0.06, 101, Color(0.9, 0.66, 0.62), Color(0.8, 0.52, 0.52))
        # umbilical-like stalk where it grew from the wall
        K.tube(st, Transform3D.IDENTITY, [Vector3(0, -R * 0.9, 0.02), Vector3(0.02, -R * 1.1, 0.04), Vector3(0.0, -R * 1.25, 0.03)], [0.016, 0.012, 0.01], 5, [Color(0.6, 0.25, 0.3)], false)
    else:
        K.blob(st, Transform3D.IDENTITY, Vector3(0, 0, 0.02), Vector3(R * 0.55, R * 0.62, R * 0.5), 0.2, 102, Color(0.3, 0.06, 0.1), Color(0.42, 0.12, 0.14))
    return K.finish(st, 12.0)

func _hand_mesh() -> ArrayMesh:
    return _hand_raw()

## A small pale hand, palm facing -Z (flat against the sac wall).
static func _hand_raw() -> ArrayMesh:
    var st := K.begin()
    var skin := Color(0.92, 0.74, 0.68)
    K.blob(st, Transform3D.IDENTITY, Vector3.ZERO, Vector3(0.019, 0.022, 0.007), 0.05, 111, skin, skin.darkened(0.08))
    for f in range(5):
        var x := -0.014 + f * 0.007
        var base := Vector3(x, 0.018, 0.0)
        var fl := 0.022 if f in [1, 2, 3] else 0.016
        if f == 0:
            base = Vector3(-0.019, 0.0, 0.0)
            K.tube(st, Transform3D.IDENTITY, [base, base + Vector3(-0.01, 0.008, 0.0), base + Vector3(-0.014, 0.016, -0.002)], [0.0036, 0.003, 0.0022], 4, [skin], true)
            continue
        K.tube(st, Transform3D.IDENTITY, [base, base + Vector3(0, fl * 0.55, -0.001), base + Vector3(0, fl, -0.002)], [0.0034, 0.003, 0.0022], 4, [skin], true)
    return K.finish(st, 25.0)

# --- neuroma ----------------------------------------------------------------

func _star_mesh(grow: float) -> ArrayMesh:
    return _star_raw(grow)

## Yellow nerve strands branching out of a small knot in a star.
static func _star_raw(grow: float) -> ArrayMesh:
    var st := K.begin()
    var I := Transform3D.IDENTITY
    K.blob(st, I, Vector3.ZERO, Vector3(R * 0.42, R * 0.4, R * 0.42) * grow, 0.25, 121, Color(0.85, 0.7, 0.2), Color(0.7, 0.5, 0.15))
    for a in range(9):
        var d := _ear_dir(a + 20)
        var side := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
        var pts: Array = []
        for k in range(5):
            var t := float(k) / 4.0
            pts.append((d * R * lerpf(0.3, 1.25, t) + side * sin(t * 3.0 + a) * 0.01) * grow)
        K.tube(st, I, pts, [0.009 * grow, 0.007 * grow, 0.005 * grow, 0.003 * grow, 0.0012 * grow], 4, [Color(0.95, 0.82, 0.2)], false)
        # one or two twigs off each strand
        for b in range(2):
            var at: Vector3 = pts[2 + b]
            var tw := (d + side * (0.8 if b == 0 else -0.8)).normalized()
            K.tube(st, I, [at, at + tw * R * 0.22 * grow, at + (tw + d).normalized() * R * 0.34 * grow], [0.0035 * grow, 0.002 * grow, 0.0008 * grow], 3, [Color(0.98, 0.88, 0.3)], false)
    return K.finish(st, 15.0)

# --- ear bunch --------------------------------------------------------------

## Spread directions (Fibonacci on the upper and side half).
static func _ear_dir(i: int) -> Vector3:
    var n := 12.0
    var y := 1.0 - (float(i % 12) + 0.5) / n * 1.4
    var r := sqrt(maxf(0.0, 1.0 - y * y))
    var a := float(i) * 2.39996
    return Vector3(cos(a) * r, y, sin(a) * r).normalized()

func _ear_base_mesh() -> ArrayMesh:
    return _ear_base_raw()

static func _ear_base_raw() -> ArrayMesh:
    var st := K.begin()
    K.blob(st, Transform3D.IDENTITY, Vector3.ZERO, Vector3(R * 0.52, R * 0.5, R * 0.52), 0.3, 131, Color(0.84, 0.6, 0.52), Color(0.7, 0.42, 0.38))
    return K.finish(st, 10.0)

func _ear_mesh() -> ArrayMesh:
    return _ear_raw()

## One small human ear facing -Z: a flat shell, a curled rim, a lobe.
static func _ear_raw() -> ArrayMesh:
    var st := K.begin()
    var I := Transform3D.IDENTITY
    var skin := Color(0.84, 0.58, 0.5)
    var deep := skin.darkened(0.3)
    # tall flat shell, darker in the bowl
    K.blob(st, I, Vector3(0, 0.002, -0.002), Vector3(0.014, 0.027, 0.005), 0.04, 141, skin, skin.darkened(0.12))
    K.blob(st, I, Vector3(0.002, -0.002, -0.006), Vector3(0.007, 0.011, 0.003), 0.05, 144, deep, deep.darkened(0.2))
    # helix: the rim curls over the top and down the back, open at the front
    var rim: Array = []
    for k in range(10):
        var a := lerpf(0.35, PI * 1.55, float(k) / 9.0)
        rim.append(Vector3(cos(a) * 0.015, sin(a) * 0.027 + 0.002, -0.006))
    K.tube(st, I, rim, [0.003, 0.0052, 0.006, 0.006, 0.0058, 0.0055, 0.0052, 0.0046, 0.004, 0.003], 5, [skin.lightened(0.04)], false)
    # antihelix ridge inside the rim
    K.tube(st, I, [Vector3(-0.004, 0.016, -0.006), Vector3(-0.007, 0.006, -0.007), Vector3(-0.003, -0.008, -0.007)], [0.0016, 0.002, 0.0014], 3, [skin], false)
    # soft lobe at the bottom
    K.blob(st, I, Vector3(0.001, -0.026, -0.004), Vector3(0.007, 0.007, 0.004), 0.1, 142, skin, skin)
    return K.finish(st, 25.0)

func capture_setup() -> Dictionary:
    # capture only: all six kinds in two rows, live (with their behaviours)
    set_variant(0)
    for i in range(1, KINDS):
        var t: Node3D = load("res://main/art/fp_tumor.tscn").instantiate()
        t.position = Vector3((i % 3) * 0.3, -floorf(i / 3.0) * 0.3, 0)
        add_child(t)
        t.call("set_variant", i)
    position = Vector3(-0.3, 0.15, 0)
    watch_on = true
    watch_pos = Vector3(0.0, 0.0, 0.7)
    return {"cam_pos": Vector3(0.0, 0.0, 0.75), "look_at": Vector3(0, 0, 0), "env": "lit", "fov": 60.0}
