extends Node3D

const K := preload("res://main/art/fp_art_kit.gd")

## Ceiling vent (the shop). Local frame: the vent face lies on y=0 and the
## duct goes UP (+Y), so it is seen from below. Grate hinges down on its -X
## edge. Nothing of the being shows in the dark duct (no eyes, user
## 2026-11-03); when it offers, one slender arm per offered item comes down
## out of the black and holds its item out close in front of the player's
## eye, lying on the open, upturned palm.
## Public: set_open(0..1), play_open(), play_offer(), play_withdraw(),
## set_offer_items(kinds), take_item(i), item_node(i), hand_count(),
## begin_look(eye), end_look(), look_pose() (the head in under the vent),
## set_pile(n), play_spill(kinds, floor_y). set_eyes(), blink() and set_eye_mood() stay callable for the
## vent logic: the eyes never show, the mood only makes the fingers fidget.

const SIZE := 0.26
var _black_cover: MeshInstance3D
var _grate: Node3D
var _offers: Array = []
var _mood := 0.0
var _time := 0.0

func _ready() -> void:
    var metal := K.mat("tex_chrome_128.png", 0.2, false)
    # flange frame, 4 bevelled bars
    var st := K.begin()
    var c := Color(0.78, 0.8, 0.8)
    var ce := Color(0.95, 0.96, 0.96)
    K.rbox(st, K.T(Vector3(0, -0.01, SIZE + 0.03)), Vector3(SIZE + 0.06, 0.015, 0.03), 0.012, c, ce)
    K.rbox(st, K.T(Vector3(0, -0.01, -SIZE - 0.03)), Vector3(SIZE + 0.06, 0.015, 0.03), 0.012, c, ce)
    K.rbox(st, K.T(Vector3(SIZE + 0.03, -0.01, 0)), Vector3(0.03, 0.015, SIZE), 0.012, c, ce)
    K.rbox(st, K.T(Vector3(-SIZE - 0.03, -0.01, 0)), Vector3(0.03, 0.015, SIZE), 0.012, c, ce)
    # screws
    for sx in [-1, 1]:
        for sz in [-1, 1]:
            K.lathe(st, K.T(Vector3(sx * (SIZE + 0.03), -0.028, sz * (SIZE + 0.03)), Vector3(180, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.012, 0.0), Vector2(0.01, 0.006), Vector2(0.0, 0.008)], 6, [Color(0.6, 0.6, 0.62)])
            # slotted screw heads
            K.rbox(st, K.T(Vector3(sx * (SIZE + 0.03), -0.037, sz * (SIZE + 0.03)), Vector3(0, 45, 0)), Vector3(0.011, 0.0015, 0.0018), 0.0005, Color(0.2, 0.2, 0.21))
    # inner sleeve covering the seam between flange and duct walls
    K.rbox(st, K.T(Vector3(0, 0.012, SIZE + 0.004)), Vector3(SIZE + 0.008, 0.026, 0.005), 0.003, c, ce)
    K.rbox(st, K.T(Vector3(0, 0.012, -SIZE - 0.004)), Vector3(SIZE + 0.008, 0.026, 0.005), 0.003, c, ce)
    K.rbox(st, K.T(Vector3(SIZE + 0.004, 0.012, 0)), Vector3(0.005, 0.026, SIZE), 0.003, c, ce)
    K.rbox(st, K.T(Vector3(-SIZE - 0.004, 0.012, 0)), Vector3(0.005, 0.026, SIZE), 0.003, c, ce)
    K.add_mesh(self, "Flange", K.finish(st, 6.0), metal)
    # duct: inward-facing walls going up into black
    st = K.begin()
    var dark := Color(0.12, 0.12, 0.13)
    var black := Color(0.01, 0.01, 0.01)
    var hgt := 0.7
    for i in range(4):
        var t := K.T(Vector3.ZERO, Vector3(0, 90 * i, 0))
        var a := Vector3(-SIZE, 0, -SIZE)
        var b := Vector3(SIZE, 0, -SIZE)
        K.quad(st, t, a, b, b + Vector3(0, 0.25, 0), a + Vector3(0, 0.25, 0), Vector3(0, 0, 1), dark)
        K.quad(st, t, a + Vector3(0, 0.25, 0), b + Vector3(0, 0.25, 0), b + Vector3(0, hgt, 0), a + Vector3(0, hgt, 0), Vector3(0, 0, 1), black)
    K.quad(st, Transform3D.IDENTITY, Vector3(-SIZE, hgt, -SIZE), Vector3(SIZE, hgt, -SIZE), Vector3(SIZE, hgt, SIZE), Vector3(-SIZE, hgt, SIZE), Vector3.DOWN, black)
    K.add_mesh(self, "Duct", K.finish(st, 4.0), K.mat("tex_fixture_64.png", 0.1, false))
    # A closed vent reads as a clean black opening behind the grille.
    st = K.begin()
    K.quad(st, Transform3D.IDENTITY, Vector3(-SIZE, 0.01, -SIZE), Vector3(SIZE, 0.01, -SIZE), Vector3(SIZE, 0.01, SIZE), Vector3(-SIZE, 0.01, SIZE), Vector3.DOWN, Color.BLACK)
    _black_cover = K.add_mesh(self, "BlackOpening", K.finish(st), K.glow(Color.BLACK))
    # grate on a hinge
    _grate = K.pivot(self, "GrateHinge", Vector3(-SIZE, -0.02, 0))
    st = K.begin()
    var gc := Color(0.86, 0.87, 0.86)
    K.rbox(st, K.T(Vector3(SIZE, 0, SIZE - 0.015)), Vector3(SIZE, 0.012, 0.015), 0.006, gc)
    K.rbox(st, K.T(Vector3(SIZE, 0, -SIZE + 0.015)), Vector3(SIZE, 0.012, 0.015), 0.006, gc)
    K.rbox(st, K.T(Vector3(0.015, 0, 0)), Vector3(0.015, 0.012, SIZE), 0.006, gc)
    K.rbox(st, K.T(Vector3(2 * SIZE - 0.015, 0, 0)), Vector3(0.015, 0.012, SIZE), 0.006, gc)
    for i in range(9):
        var x := 0.05 + i * (2 * SIZE - 0.1) / 8.0
        K.rbox(st, K.T(Vector3(x, 0.005, 0), Vector3(0, 0, 38)), Vector3(0.004, 0.018, SIZE - 0.02), 0.002, Color(0.8, 0.81, 0.8), Color(0.95, 0.95, 0.95))
    # centre brace so the long slats do not read as loose sticks
    K.rbox(st, K.T(Vector3(SIZE, 0.012, 0)), Vector3(SIZE - 0.02, 0.006, 0.01), 0.003, gc)
    # hinge knuckles on the -X edge so the grate visibly hangs from something
    for hz in [-1, 1]:
        K.tube(st, Transform3D.IDENTITY, [Vector3(0, 0, hz * (SIZE - 0.09)), Vector3(0, 0, hz * (SIZE - 0.03))], [0.009, 0.009], 6, [Color(0.7, 0.71, 0.7)], true)
    K.add_mesh(_grate, "Grate", K.finish(st, 8.0), metal)
    # offered items: the being only ever shows the arms that hold them out
    # (docs/spec/03-restroom.md §7), one hand per item. The player picks
    # one up by hand, the others go back up.
    _build_pile()
    _arms = K.pivot(self, "BeingArm")
    _arms.visible = false
    set_offer_items(["spray_cheap", "barrier", "junk"])
    set_offer_extend(0.0)

# --- the being's hands ---------------------------------------------------------

## The hands are held out this far in front of the player's eye (level
## distance, toward the vent) and this much above it, so the items read up
## close (user 2026-11-03: "가까이서 보게"); right under the vent they stay
## higher so they do not hang in the face. The arms reach at most REACH_MAX
## from the lip.
const HAND_AHEAD := 0.46
const HAND_LIFT := 0.08
const HAND_LIFT_UNDER := 0.4
const REACH_MAX := 1.4
## Lip height of the opening (the arm leaves the black here) and the lowest
## the hand cluster's middle may hang above it.
const LIP_Y := -0.03
const BELOW_LIP := 0.32
## Hands side by side (metres between wrists) and rows of at most ROW_MAX.
const SPACING := 0.16
const ROW_GAP := 0.21
const ROW_MAX := 5
## Each hand past the third pushes the fan this much further out, so a wide
## offer still fits the view without the hands crowding each other.
const AHEAD_PER_HAND := 0.035
## The arm (user 2026-11-09 "팔을 일자로만 뻗어서 이상함"): a shoulder up in
## the dark of the duct, the upper arm coming down out of the opening to a
## softly bent elbow, a forearm of a real length sloping down toward the
## player and turning the palm up, and the wrist lifting the hand back a
## little to offer. FOREARM is elbow to wrist (shorter only on a short reach);
## SHOULDER_UP is the shoulder above the lip.
const FOREARM := 0.255
## Inside angle at the elbow (radians; pi is a straight arm), each arm its
## own by up to ELBOW_VARY, the elbow pointing away from the eye and out.
const ELBOW_ANGLE := 2.45
const ELBOW_VARY := 0.14
const SHOULDER_UP := 0.12
## The wrist never bends further than this from the forearm line (a soft
## extension, comfortable, never a broken-back wrist).
const WRIST_MAX := 0.62
## The palm turns up to the eye: its normal is the way up weighted by
## PALM_UP plus the way to the eye, so the item lies in it and the eye sees
## into the palm.
const PALM_UP := 0.72
## Share of the offer tween spent coming straight down out of the duct
## before the forearm swings out toward the player.
const DROP_PHASE := 0.42
## Where the item sits (hand frame: fingers down -Y, palm +Z, thumb +X): in
## the hollow of the open palm a little below its middle, its bottom resting
## on the skin (user 2026-11-09 "물건이 손에 잘 안 올라가있음").
const SEAT := Vector2(0.001, -0.058)
## The item presses this far into the soft palm, so it reads as lying on it.
const SEAT_SINK := 0.0012
## Offered items at this share of their real size (they are what the hand
## then carries to the belt), so the hand still shows round them.
const ITEM_SCALE := 0.62
## Longest and shortest side (item units, before ITEM_SCALE) an item may
## have across the palm; bigger ones are shrunk to fit.
const ITEM_SPAN := 0.15
const ITEM_BREADTH := 0.11
## Bright porcelain skin with living warmth: rosy knuckles and fingertips, a
## cooler shade in the creases at the finger roots, and glossy almond nails
## in a soft rose (user 2026-11-03, 11-08 "손이 아직 덜 예뻐"): a hand that
## makes you expect a very beautiful person.
const SKIN := Color(1.0, 0.885, 0.83)
const SKIN_SHADE := Color(0.95, 0.8, 0.76)
const SKIN_BLUSH := Color(1.0, 0.815, 0.775)
const SKIN_CREASE := Color(0.95, 0.79, 0.76)
## The knuckles only a breath warmer than the skin round them.
const SKIN_KNUCKLE := Color(1.0, 0.85, 0.805)
## Nails carry alpha below 1: the being's shader gives them a glossy sheen.
const NAIL := Color(0.85, 0.44, 0.5, 0.7)
const NAIL_MOON := Color(0.95, 0.66, 0.68, 0.72)
const NAIL_TIP := Color(0.93, 0.56, 0.6, 0.7)
## Hand proportions from photo references of slim women's hands, drawn a
## little toward the hand-model ideal (user 2026-11-08): back of the hand
## (wrist to knuckle) 0.076 m, middle finger from its knuckle about 1.22 of
## that; index 0.93, ring 0.95, little 0.77, thumb 0.66 of the middle finger.
## The palm tapers from a slim wrist (0.67 of the knuckle breadth) and
## rounds into the knuckles, which the finger bases fill edge to edge, so
## the outline runs from wrist to fingertips with no shelf (11-09: the palm
## read as a box). Hand frame: wrist at 0, fingers down -Y, palm +Z, thumb +X.
const PALM_LEN := 0.086
const PALM_HALF := 0.0282
const WRIST_HALF := 0.0222
## The knuckle (MCP) sits this far inside the finger root line.
const MCP_IN := 0.01
## Fingers index to little: x, finger root height (share of the palm
## length: the knuckles run in a gentle arc, the middle furthest), length
## from the knuckle, base radius, sideways splay (degrees), curl share
## (each finger toward the little one curls a little more).
const FINGERS := [
    [0.0197, 0.958, 0.0858, 0.0064, -4.5, 0.8],
    [0.0066, 1.0, 0.0928, 0.0066, -0.8, 1.0],
    [-0.0066, 0.972, 0.0882, 0.0062, 2.2, 1.12],
    [-0.0188, 0.89, 0.0712, 0.0053, 8.0, 1.36],
]
const PHALANX := [0.45, 0.28, 0.27]
const TAPER := 0.72
const THUMB_LEN := 0.062
## The thumb leaves the thenar mound here and lies relaxed, open from the
## index (degrees: forward toward the palm, out from the fingers, and its own
## turn so the nail faces out to the side).
const THUMB_ROOT := Vector3(0.0272, -0.04, 0.0066)
const THUMB_POSE := Vector3(-24, 0, 34)
const THUMB_TWIST := -62.0
## Curl offering (the fingers rise softly round the item), up close, and
## when gripping on the take; per joint the middle (PIP) bends most.
const CURL_REST := 0.5
const CURL_GRIP := 1.2
const JOINT_SHARE := [0.42, 1.0, 0.62]

var _arms: Node3D
## One rig per hand: {root, upper, fore, elbow, hand, palm, slot, fingers, thumb, chir, ...}.
var _rigs: Array = []
var _count := 0
## Something is on offer (false once taken or cleared: the arms only go up).
var _wanted := false
var _extend := 0.0
var _curl := 0.0
var _hand_tw: Tween
## Smoothed middle of the hand cluster (vent frame), snapped on first show.
var _center := Vector3(0, -0.6, 0.3)
var _side := Vector3(0, 0, 1)
var _snap := true
var _meshes: Dictionary = {}
var _skin_mat: Material
## Height of the palm's skin under the item seat (hand frame z).
var _seat_z := 0.012

## The being's own soft skin (user 2026-11-03: the low-poly facets should
## not show; 11-08: still not pretty enough): smooth shared-vertex normals
## from _tube(), a wrapped (half-Lambert) key light so the shade side never
## goes hard, a warm subsurface-like glow where the light wraps into shade,
## at the thin silhouette and in the flushed fingertips and knuckles, a soft
## moisturised sheen, a faint cool rim, and a glossy coat on the nails
## (vertex alpha below 1 marks them). Above the lip of the opening the arm
## fades into the dark of the duct. Unshaded like the body's skin pipeline,
## so the bright ceiling lamp cannot blow it out; the player's skin material
## (FDKSkinMaterial) is not touched.
const SKIN_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 key_dir = vec3(0.35, 0.85, 0.4);
uniform vec3 fill_dir = vec3(-0.6, -0.2, 0.5);
uniform vec3 warm : source_color = vec3(1.0, 0.5, 0.42);
uniform float wrap_lo = 0.66;
uniform float wrap_hi = 1.04;
uniform float sss = 0.24;
uniform float rim = 0.12;
uniform float sheen = 0.05;
uniform float nail_gloss = 0.7;
uniform float lip_y = 1000.0;
varying vec3 wn;
varying float wy;
void vertex() {
    // the forearm is stretched along its length: the normal matrix keeps it round
    wn = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
    vec3 n = normalize(wn);
    if (!FRONT_FACING) { n = -n; }
    vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
    vec3 l = normalize(key_dir);
    float ndl = dot(n, l);
    float wrap = pow(clamp(ndl * 0.5 + 0.5, 0.0, 1.0), 1.3);
    float fill = clamp(dot(n, normalize(fill_dir)) * 0.5 + 0.5, 0.0, 1.0);
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    float fres = pow(1.0 - ndv, 2.4);
    vec3 base = COLOR.rgb;
    float nail = clamp((1.0 - COLOR.a) * 4.0, 0.0, 1.0);
    // flushed skin (fingertips, knuckles) lets more warm light through
    float flush = clamp((base.g < 0.86 ? 0.86 - base.g : 0.0) * 14.0, 0.0, 1.0) * (1.0 - nail);
    vec3 col = base * mix(wrap_lo, wrap_hi, wrap) * mix(0.97, 1.03, fill);
    // light passing through thin skin: warm where it wraps into shade and at the silhouette
    col += base * warm * (sss + 0.1 * flush) * (1.0 - wrap * (1.0 - 0.5 * flush)) * (1.0 - nail);
    col = mix(col, col * mix(vec3(1.0), warm * 1.3, 0.55), fres * 0.4 * (1.0 - nail));
    col += vec3(0.92, 0.95, 1.0) * rim * fres * wrap;
    vec3 h = normalize(l + v);
    float nh = max(dot(n, h), 0.0);
    // skin: a broad soft sheen; nails: a tight lacquer highlight and a reflection at grazing angles
    col += vec3(1.0, 0.97, 0.95) * pow(nh, 14.0) * sheen * (1.0 - nail);
    col += vec3(1.0) * (pow(nh, 70.0) * nail_gloss + pow(nh, 12.0) * 0.12 + fres * 0.3) * nail;
    // the arm comes out of the black of the duct
    col *= 1.0 - 0.985 * smoothstep(lip_y - 0.03, lip_y + 0.22, wy);
    ALBEDO = col;
}
"""

func _skin() -> Material:
    if _skin_mat == null:
        var sh := Shader.new()
        sh.code = SKIN_SHADER
        var m := ShaderMaterial.new()
        m.shader = sh
        _skin_mat = m
    return _skin_mat

## Smooth tube for the being's arms and hands: rings of `sides` points round
## `pts` (mostly along Y), an ellipse rx across X and rz through Z, colours
## blended ring to ring, each end closed by a rounded dome `dome0`/`dome1`
## long (0 leaves it open). `arch` (per ring) lifts each point by arch * |x|
## on the little-finger side (-X) and a third of that on the index side, so
## the palm's knuckle line arches like the photos; `bend` (per ring) lets the
## X edges dip toward +Z (a nail's curve across the finger, the domed back
## of the hand). Vertices are shared and indexed, so generate_normals shades
## it round, with no facets.
static func _tube(st: SurfaceTool, base: int, pts: Array, rx: Array, rz: Array, cols: Array, sides: int, dome0: float = 0.0, dome1: float = 0.0, arch: Array = [], bend: Array = []) -> int:
    # each ring: [centre, rx, rz, arch, bend, colour]
    var rs: Array = []
    var n := pts.size()
    var col_at := func(i: int) -> Color: return cols[mini(i, cols.size() - 1)]
    var arch_at := func(i: int) -> float: return float(arch[i]) if i < arch.size() else 0.0
    var bend_at := func(i: int) -> float: return float(bend[i]) if i < bend.size() else 0.0
    if dome0 > 0.0:
        var d0: Vector3 = ((pts[0] as Vector3) - (pts[1] as Vector3)).normalized()
        for k in range(4):
            var t := (0.12 + 0.88 * float(k) / 4.0) * PI * 0.5
            rs.append([(pts[0] as Vector3) + d0 * dome0 * cos(t), float(rx[0]) * sin(t), float(rz[0]) * sin(t), arch_at.call(0), bend_at.call(0) * sin(t), col_at.call(0)])
    for i in range(n):
        rs.append([pts[i], float(rx[i]), float(rz[i]), arch_at.call(i), bend_at.call(i), col_at.call(i)])
    if dome1 > 0.0:
        var d1: Vector3 = ((pts[n - 1] as Vector3) - (pts[n - 2] as Vector3)).normalized()
        var cl: Color = col_at.call(n - 1)
        for k in range(1, 5):
            var t := (1.0 - 0.88 * float(k) / 4.0) * PI * 0.5
            rs.append([(pts[n - 1] as Vector3) + d1 * dome1 * cos(t), float(rx[n - 1]) * sin(t), float(rz[n - 1]) * sin(t), arch_at.call(n - 1), bend_at.call(n - 1) * sin(t), cl])
    for r in rs:
        st.set_color(r[5])
        for j in range(sides):
            var a := TAU * float(j) / float(sides)
            var x := cos(a) * float(r[1])
            var y := float(r[3]) * (-x if x < 0.0 else x * 0.33)
            var cx := cos(a)
            var z := sin(a) * float(r[2]) + float(r[4]) * cx * cx
            st.add_vertex((r[0] as Vector3) + Vector3(x, y, z))
    for i in range(rs.size() - 1):
        for j in range(sides):
            var k := (j + 1) % sides
            var a0 := base + i * sides + j
            var a1 := base + i * sides + k
            var b0 := base + (i + 1) * sides + j
            var b1 := base + (i + 1) * sides + k
            st.add_index(a0)
            st.add_index(b1)
            st.add_index(a1)
            st.add_index(a0)
            st.add_index(b0)
            st.add_index(b1)
    var count := rs.size() * sides
    # the poles: one vertex closing each dome
    if dome0 > 0.0:
        var d0: Vector3 = ((pts[0] as Vector3) - (pts[1] as Vector3)).normalized()
        st.set_color(col_at.call(0))
        st.add_vertex((pts[0] as Vector3) + d0 * dome0)
        for j in range(sides):
            st.add_index(base + count)
            st.add_index(base + j)
            st.add_index(base + (j + 1) % sides)
        count += 1
    if dome1 > 0.0:
        var d1: Vector3 = ((pts[n - 1] as Vector3) - (pts[n - 2] as Vector3)).normalized()
        st.set_color(col_at.call(n - 1))
        st.add_vertex((pts[n - 1] as Vector3) + d1 * dome1)
        var last := base + (rs.size() - 1) * sides
        for j in range(sides):
            st.add_index(base + count)
            st.add_index(last + (j + 1) % sides)
            st.add_index(last + j)
        count += 1
    return base + count

static func _smooth_begin() -> SurfaceTool:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    return st

static func _smooth_finish(st: SurfaceTool) -> ArrayMesh:
    st.generate_normals()
    # generate_normals hands back loose triangles: share the corners again
    st.index()
    return st.commit()

## The same mesh reflected across x = 0 (a left hand from a right one):
## positions and normals mirrored, the winding turned so it still faces out.
static func _mirrored(mesh: ArrayMesh) -> ArrayMesh:
    var arr: Array = mesh.surface_get_arrays(0)
    var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
    for i in range(vs.size()):
        vs[i] = Vector3(-vs[i].x, vs[i].y, vs[i].z)
    for i in range(ns.size()):
        ns[i] = Vector3(-ns[i].x, ns[i].y, ns[i].z)
    arr[Mesh.ARRAY_VERTEX] = vs
    arr[Mesh.ARRAY_NORMAL] = ns
    arr[Mesh.ARRAY_TANGENT] = null
    var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
    for i in range(0, idx.size(), 3):
        var t := idx[i + 1]
        idx[i + 1] = idx[i + 2]
        idx[i + 2] = t
    arr[Mesh.ARRAY_INDEX] = idx
    var out := ArrayMesh.new()
    out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
    return out

func _build_meshes() -> void:
    if not _meshes.is_empty():
        return
    # Silhouettes stay round (user 2026-11-03: the angles should not show):
    # 14-24 sided rings, more rings where the outline curves, shared
    # vertices so the shading runs smooth over the whole hand.
    var st := _smooth_begin()
    # forearm, built one unit long from the wrist (0) up to the elbow (1);
    # the rig stretches it along Y to the real length. Slim at the wrist,
    # swelling softly toward the elbow, a flat oval that turns with the hand.
    var wr := WRIST_HALF
    _tube(st, 0, [Vector3(0, -0.03, 0), Vector3(0, 0.06, 0), Vector3(0, 0.2, 0), Vector3(0, 0.5, 0), Vector3(0, 0.8, 0), Vector3(0, 1.0, 0)], [wr * 0.98, wr * 1.04, wr * 1.14, wr * 1.3, wr * 1.34, wr * 1.26], [wr * 0.64, wr * 0.68, wr * 0.8, wr * 1.0, wr * 1.06, wr * 1.06], [SKIN, SKIN, SKIN, SKIN, SKIN, SKIN_SHADE], 18)
    _meshes["fore"] = _smooth_finish(st)
    # upper arm, built one unit long from the elbow (0) up to the shoulder in
    # the duct (1); slim, round, a little fuller toward the shoulder
    st = _smooth_begin()
    _tube(st, 0, [Vector3(0, -0.02, 0), Vector3(0, 0.25, 0), Vector3(0, 0.6, 0), Vector3(0, 1.0, 0), Vector3(0, 1.3, 0)], [0.027, 0.03, 0.032, 0.033, 0.033], [0.026, 0.029, 0.031, 0.032, 0.032], [SKIN_SHADE, SKIN, SKIN, SKIN_SHADE], 18)
    _meshes["upper"] = _smooth_finish(st)
    # the elbow, a soft round joint where the two meet
    st = _smooth_begin()
    _tube(st, 0, [Vector3(0, -0.01, 0), Vector3(0, 0.01, 0)], [0.0275, 0.0275], [0.027, 0.027], [SKIN_SHADE], 18, 0.017, 0.017)
    _meshes["elbow"] = _smooth_finish(st)
    # wrist and palm: the slim wrist widening in a soft curve to the
    # knuckles, its end in a gentle arc down toward the little finger and
    # rounded off; the back of the hand domed, the palm side fuller. The
    # thenar mound carries the thumb out of the palm with a thin web to the
    # index root. No separate knuckle bumps: only a flush of colour there.
    st = _smooth_begin()
    var ys := [0.016, 0.006, -0.006, -0.019, -0.032, -0.045, -0.057, -0.066, -0.073, -0.079]
    var rx := [wr * 0.9, wr * 0.92, wr * 0.97, PALM_HALF * 0.84, PALM_HALF * 0.9, PALM_HALF * 0.95, PALM_HALF * 0.985, PALM_HALF, PALM_HALF * 0.985, PALM_HALF * 0.94]
    var rz := [wr * 0.6, wr * 0.6, 0.0118, 0.0121, 0.0124, 0.0124, 0.012, 0.0114, 0.0107, 0.0099]
    var bend := [0.0, 0.0004, 0.0016, 0.0026, 0.0032, 0.0034, 0.0032, 0.0028, 0.0022, 0.0016]
    var arch := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.02, 0.07, 0.16, 0.24]
    var pts: Array = []
    for k in range(ys.size()):
        pts.append(Vector3(0, float(ys[k]), 0.0005))
    var cols: Array = []
    for k in range(ys.size()):
        cols.append(SKIN if k < ys.size() - 2 else SKIN_KNUCKLE)
    var vi := _tube(st, 0, pts, rx, rz, cols, 24, 0.0, 0.0065, arch, bend)
    # the thenar mound along the thumb's metacarpal
    var tr := THUMB_ROOT
    vi = _tube(st, vi, [Vector3(0.008, -0.002, 0.003), Vector3(0.0145, -0.013, 0.0052), Vector3(0.0205, -0.025, 0.0064), Vector3(0.025, -0.034, 0.0066), tr], [0.0085, 0.0108, 0.0108, 0.0094, 0.0082], [0.0068, 0.0084, 0.0086, 0.0082, 0.0076], [SKIN], 16, 0.004, 0.004)
    # the web from the thumb's root to the index knuckle, thin and soft
    vi = _tube(st, vi, [tr + Vector3(0.001, -0.004, -0.0006), Vector3(0.0262, -0.054, 0.004), Vector3(0.0232, -0.066, 0.0026)], [0.0066, 0.0056, 0.0042], [0.0044, 0.0038, 0.0032], [SKIN], 14, 0.003, 0.003)
    _meshes["palm"] = _smooth_finish(st)
    _meshes["palm_l"] = _mirrored(_meshes["palm"])
    # the palm's skin under the item seat: the highest palm-side point there
    var top := -1.0
    for v in (_meshes["palm"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
        if absf(v.x - SEAT.x) < 0.009 and absf(v.y - SEAT.y) < 0.009:
            top = maxf(top, v.z)
    _seat_z = top if top > 0.0 else 0.012
    for i in range(FINGERS.size()):
        var f: Array = FINGERS[i]
        var length: float = f[2]
        var r: float = f[3]
        var rm := lerpf(r, r * TAPER, 0.48)
        var rd := lerpf(r, r * TAPER, 0.78)
        _meshes["f%d_0" % i] = _bone_mesh(length * PHALANX[0], r, rm * 1.02, false, SKIN_CREASE)
        _meshes["f%d_1" % i] = _bone_mesh(length * PHALANX[1], rm, rd, false, SKIN)
        _meshes["f%d_2" % i] = _bone_mesh(length * PHALANX[2], rd, r * TAPER, true, SKIN)
    _meshes["thumb_p"] = _bone_mesh(THUMB_LEN * 0.53, 0.0078, 0.0071, false, SKIN)
    _meshes["thumb_d"] = _bone_mesh(THUMB_LEN * 0.47, 0.0071, 0.0057, true, SKIN)

## One finger segment hanging down -Y from its joint: a 16-sided tube a
## little wider than deep, rounded at both ends so a bent joint stays one
## soft bulge, tapering from r0 to r1, its far joint faintly flushed (the
## knuckle) and its root ring `root_col` (the crease at the finger root).
## The tip segment swells into a soft pad on the palm side, ends in a
## rounded tip and carries an almond nail on its back (-Z): curved across
## the finger, a pale moon at the cuticle, 0.62 of the segment long, 0.8 of
## the fingertip wide, its free edge running 3 mm past the tip to a soft
## point.
func _bone_mesh(length: float, r0: float, r1: float, tip: bool, root_col: Color) -> ArrayMesh:
    var st := _smooth_begin()
    var d0 := 0.86
    if tip:
        var py := [0.0, -length * 0.3, -length * 0.62, -length * 0.85, -length]
        var px := [r0, lerpf(r0, r1, 0.4) * 1.01, r1 * 1.02, r1 * 0.94, r1 * 0.74]
        var pz := [r0 * d0, lerpf(r0, r1, 0.4) * d0, r1 * 0.9, r1 * 0.84, r1 * 0.66]
        var pts: Array = []
        for k in range(py.size()):
            # the pad: the tip's centre shifts toward the palm side
            pts.append(Vector3(0, float(py[k]), r1 * 0.12 * float(k) / float(py.size() - 1)))
        var vi := _tube(st, 0, pts, px, pz, [root_col, SKIN, SKIN, SKIN_BLUSH, SKIN_BLUSH], 16, r0 * 0.35, r1 * 0.62)
        # the nail: almond, on the back of the tip, following its surface
        var w := r1 * 0.8
        var y_c := -length * 0.36
        var y_end := -length - r1 * 0.62 - 0.003
        var ts := [0.0, 0.1, 0.3, 0.55, 0.75, 0.9, 1.0]
        var ws := [0.62, 0.9, 1.0, 0.98, 0.84, 0.58, 0.24]
        var npts: Array = []
        var nrx: Array = []
        var nrz: Array = []
        var nbend: Array = []
        var ncol: Array = []
        for k in range(ts.size()):
            var t: float = ts[k]
            var y := lerpf(y_c, y_end, t)
            # the finger's back surface under the nail (z < 0), the free edge
            # carrying on a touch past the round tip
            var surf := lerpf(lerpf(r0, r1, 0.4) * d0, r1 * 0.88, clampf(t * 1.6, 0.0, 1.0))
            if t > 0.7:
                surf = lerpf(r1 * 0.88, r1 * 0.5, (t - 0.7) / 0.3)
            npts.append(Vector3(0, y, -surf - 0.0004 + r1 * 0.12 * clampf(-y / length, 0.0, 1.0)))
            nrx.append(w * float(ws[k]))
            nrz.append(0.00055)
            nbend.append(w * 0.32 * float(ws[k]))
            ncol.append(NAIL_MOON if k == 0 else NAIL_TIP if k >= ts.size() - 2 else NAIL)
        _tube(st, vi, npts, nrx, nrz, ncol, 14, 0.0012, 0.0008, [], nbend)
    else:
        var pts := [Vector3(0, 0.0, 0), Vector3(0, -length * 0.3, 0), Vector3(0, -length * 0.7, 0), Vector3(0, -length, 0)]
        _tube(st, 0, pts, [r0 * 1.02, lerpf(r0, r1, 0.3) * 0.96, lerpf(r0, r1, 0.7) * 0.96, r1 * 1.03], [r0 * d0, lerpf(r0, r1, 0.3) * d0 * 0.94, lerpf(r0, r1, 0.7) * d0 * 0.94, r1 * d0], [root_col, SKIN, SKIN, SKIN_KNUCKLE], 16, r0 * 0.35, r1 * 0.7)
    return _smooth_finish(st)

func _new_rig(index: int) -> Dictionary:
    _build_meshes()
    var skin := _skin()
    var root := K.pivot(_arms, "Hand%d" % index)
    var upper := K.add_mesh(root, "UpperArm", _meshes["upper"], skin)
    var fore := K.add_mesh(root, "Forearm", _meshes["fore"], skin)
    var elbow := K.add_mesh(root, "Elbow", _meshes["elbow"], skin)
    var hand := K.pivot(root, "Palm")
    var palm := K.add_mesh(hand, "Hand", _meshes["palm"], skin)
    var fingers: Array = []
    for i in range(FINGERS.size()):
        var f: Array = FINGERS[i]
        var length: float = f[2]
        var root_y := -PALM_LEN * float(f[1])
        var prox := K.pivot(hand, "Finger%d" % i, Vector3(float(f[0]), root_y + MCP_IN, 0.0))
        K.add_mesh(prox, "Bone", _meshes["f%d_0" % i], skin)
        var mid := K.pivot(prox, "Mid", Vector3(0, -length * PHALANX[0], 0))
        K.add_mesh(mid, "Bone", _meshes["f%d_1" % i], skin)
        var tip := K.pivot(mid, "Tip", Vector3(0, -length * PHALANX[1], 0))
        K.add_mesh(tip, "Bone", _meshes["f%d_2" % i], skin)
        fingers.append([prox, mid, tip, float(f[5])])
    # the thumb leaves the thenar mound and lies open beside the item
    var tp := K.pivot(hand, "Thumb", THUMB_ROOT)
    K.add_mesh(tp, "Bone", _meshes["thumb_p"], skin)
    var td := K.pivot(tp, "Tip", Vector3(0, -THUMB_LEN * 0.53, 0))
    K.add_mesh(td, "Bone", _meshes["thumb_d"], skin)
    var slot := K.pivot(hand, "Offer%d" % index, Vector3(SEAT.x, SEAT.y, _seat_z))
    # each hand its own relaxed cascade (index to little), so no two are clones
    var vary: Array = []
    for i in range(4):
        vary.append(sin(float(index) * 1.7 + float(i) * 2.9 + 0.6) * 0.14)
    var rig := {"root": root, "upper": upper, "fore": fore, "elbow": elbow, "hand": hand, "palm": palm, "slot": slot, "fingers": fingers, "thumb": [tp, td], "rot": Quaternion.IDENTITY, "chir": 0.0, "mirror": 1.0,
        # each arm its own: forearm droop, its sideways turn, the palm's tilt
        "bend": ELBOW_ANGLE + sin(float(index) * 2.1 + 0.3) * ELBOW_VARY,
        "yaw": sin(float(index) * 1.37 + 1.1) * 0.35,
        "tilt": sin(float(index) * 2.9 + 0.7) * 0.12,
        "roll": sin(float(index) * 2.3 + 0.4) * 0.14, "vary": vary}
    _set_chirality(rig, 1.0)
    # render layers: set_offer_items, the only caller, tags every arm after
    return rig

## A right hand (thumb on +X, c = 1) or a left one (c = -1): the palm mesh
## and the finger and thumb roots reflected, so every thumb opens outward.
func _set_chirality(rig: Dictionary, c: float) -> void:
    if float(rig["chir"]) == c:
        return
    rig["chir"] = c
    (rig["palm"] as MeshInstance3D).mesh = _meshes["palm"] if c > 0.0 else _meshes["palm_l"]
    for i in range(FINGERS.size()):
        var f: Array = FINGERS[i]
        var prox: Node3D = rig["fingers"][i][0]
        prox.position.x = float(f[0]) * c
    var tp: Node3D = rig["thumb"][0]
    tp.position = Vector3(THUMB_ROOT.x * c, THUMB_ROOT.y, THUMB_ROOT.z)
    var slot: Node3D = rig["slot"]
    slot.position.x = SEAT.x * c

## Mirror a rotation for a left hand (reflect across x = 0).
static func _mirror_basis(b: Basis, c: float) -> Basis:
    if c > 0.0:
        return b
    var m := Basis.from_scale(Vector3(-1, 1, 1))
    return m * b * m

func item_node(index: int) -> Node3D:
    return _offers[index] if index >= 0 and index < _offers.size() else null

## Hands out (or on their way) now.
func hand_count() -> int:
    return _count if _arms != null and _arms.visible else 0

## Item kinds: spray_cheap, spray_expensive, barrier, knife, blender_box,
## saw_box, canary_feed, tumor_bag, junk (FPItemArt models, the same the
## player's hand carries to the belt). One hand comes out per item, however
## many there are. An empty list sends the arms back up.
func set_offer_items(kinds: Array) -> void:
    _wanted = not kinds.is_empty()
    if kinds.is_empty():
        if _extend > 0.0 and is_inside_tree():
            _hand_to(0.0, 0.3, Tween.EASE_IN)
        else:
            set_offer_extend(0.0)
        return
    while _rigs.size() < kinds.size():
        _rigs.append(_new_rig(_rigs.size()))
    _offers.clear()
    _count = kinds.size()
    for i in range(_rigs.size()):
        var rig: Dictionary = _rigs[i]
        var slot: Node3D = rig["slot"]
        for ch in slot.get_children():
            slot.remove_child(ch)
            ch.queue_free()
        (rig["root"] as Node3D).visible = i < _count
        rig["rot"] = Quaternion.IDENTITY
        slot.visible = i < _count
        if i < _count:
            var item := FPItemArt.make(str(kinds[i]), i)
            slot.add_child(item)
            # the same render layers as the rest of the vent (the restroom tags them)
            FPItemArt.set_layers(item, _black_cover.layers)
            # lying in the palm: its middle over the seat, its underside on the skin
            # big things come smaller, so each still fits the open palm
            # lying on its broad side, its thinnest way up out of the palm
            var box := _box_of(item)
            if box.size.z > box.size.y * 1.1:
                item.rotate_x(PI * 0.5)
                box = _box_of(item)
            var fit := minf(1.0, minf(ITEM_SPAN / maxf(box.size.x, box.size.y), ITEM_BREADTH / maxf(0.001, minf(box.size.x, box.size.y))))
            item.scale = Vector3.ONE * fit
            var mid := box.get_center()
            item.position = -Vector3(mid.x, mid.y, box.position.z) * fit - Vector3(0, 0, SEAT_SINK / ITEM_SCALE)
            slot.rotation_degrees = Vector3(0, 0, -5.0 + 4.0 * float(i % 3))
            slot.scale = Vector3.ONE * ITEM_SCALE
            _offers.append(slot)
    _set_curl(0.0)
    # new hands come out holding as they will be seen
    _look_w = 1.0 if looking() else 0.0
    var lit := _black_cover.layers
    for n in _arms.find_children("*", "VisualInstance3D", true, false):
        (n as VisualInstance3D).layers = lit
    _snap = true
    _place_hands(0.0)

## An item's outline turned as it lies (all its meshes, before it is moved
## or scaled into place).
static func _box_of(item: Node3D) -> AABB:
    var box := AABB()
    var first := true
    for n in item.find_children("*", "MeshInstance3D", true, false):
        var mi := n as MeshInstance3D
        var t := Transform3D.IDENTITY
        var p: Node = mi
        while p != item and p != null:
            t = (p as Node3D).transform * t
            p = p.get_parent()
        var b: AABB = Transform3D(item.basis, Vector3.ZERO) * t * mi.get_aabb()
        box = b if first else box.merge(b)
        first = false
    return box

## Take the item in `index` (the player's hand picks it); the others are
## pulled back into the dark at once.
func take_item(index: int) -> void:
    _wanted = false
    if _hand_tw != null:
        _hand_tw.kill()
    _hand_tw = create_tween()
    var slot: Node3D = item_node(index)
    # the player's hand closes on it about 0.3 s in; then it is gone from the palm
    _hand_tw.tween_interval(0.3)
    if slot != null:
        _hand_tw.tween_callback(func(): slot.visible = false)
    # the fingers close on what is left and the arms draw it back up
    _hand_tw.tween_method(_set_curl, 0.0, 1.0, 0.16)
    _hand_tw.tween_method(set_offer_extend, _extend, 0.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _set_curl(c: float) -> void:
    _curl = clampf(c, 0.0, 1.0)
    _pose_fingers()

## Capture only: fingers straight and together, thumb at its rest splay,
## to lay the hand beside the flat reference photos.
var flat_pose := false

## The thumb's rest pose for a hand of chirality `c`, its tip bent `flex` degrees.
static func _thumb_basis(c: float) -> Basis:
    var b := Basis.from_euler(Vector3(deg_to_rad(THUMB_POSE.x), 0.0, deg_to_rad(THUMB_POSE.z))) * Basis(Vector3.UP, deg_to_rad(THUMB_TWIST))
    return _mirror_basis(b, c)

func _pose_fingers() -> void:
    if flat_pose:
        for rig in _rigs:
            var c: float = rig["chir"]
            for i in range(4):
                var f: Array = rig["fingers"][i]
                (f[0] as Node3D).basis = Basis(Vector3.BACK, deg_to_rad(float(FINGERS[i][4]) * 0.5 * c))
                for j in range(1, 3):
                    (f[j] as Node3D).rotation.x = 0.0
            (rig["thumb"][0] as Node3D).basis = _mirror_basis(Basis.from_euler(Vector3(deg_to_rad(-6.0), 0.0, deg_to_rad(24.0))) * Basis(Vector3.UP, deg_to_rad(THUMB_TWIST)), c)
            (rig["thumb"][1] as Node3D).rotation_degrees = Vector3(-4, 0, 0)
        return
    for ri in range(mini(_count, _rigs.size())):
        var rig: Dictionary = _rigs[ri]
        var c: float = rig["chir"]
        for i in range(4):
            var f: Array = rig["fingers"][i]
            var k: float = float(f[3]) + float(rig["vary"][i])
            # a slow breath through the fingers, quicker when the being is impatient
            var fidget := sin(_time * lerpf(1.6, 5.0, _mood) + i * 0.9 + ri * 1.7) * lerpf(0.02, 0.05, _mood)
            var cv := lerpf(lerpf(CURL_REST, LOOK_CURL, _look_w), CURL_GRIP, _curl) + fidget
            # the fingers rise softly round the item in the palm (toward +Z)
            (f[0] as Node3D).basis = Basis(Vector3.BACK, deg_to_rad(float(FINGERS[i][4]) * c)) * Basis(Vector3.RIGHT, -cv * k * float(JOINT_SHARE[0]))
            for j in range(1, 3):
                (f[j] as Node3D).rotation.x = -cv * k * float(JOINT_SHARE[j])
        var th: Array = rig["thumb"]
        (th[0] as Node3D).basis = _thumb_basis(c) * Basis(Vector3.RIGHT, -0.5 * _curl)
        (th[1] as Node3D).rotation_degrees = Vector3(-14.0 - 30.0 * _curl, 0, 0)

func _hand_to(target: float, secs: float, ease_type: Tween.EaseType) -> void:
    if _hand_tw != null:
        _hand_tw.kill()
    _hand_tw = create_tween()
    _hand_tw.tween_method(set_offer_extend, _extend, target, secs).set_trans(Tween.TRANS_SINE).set_ease(ease_type)

func _process(delta: float) -> void:
    _time += delta
    if not _spill.is_empty():
        step_spill(delta)
    if _arms != null and _arms.visible:
        _place_hands(delta)
        _pose_fingers()
    else:
        _snap = true

func _eye() -> Vector3:
    var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
    if cam == null:
        return Vector3(0.55, -1.0, 0.55)
    return to_local(cam.global_position)

## Middle of the hand cluster: HAND_AHEAD in front of the eye toward the
## vent and a little above it (higher when standing right under the vent),
## below the ceiling and within the arms' reach.
func _cluster_target(eye: Vector3) -> Vector3:
    var lip := Vector3(0, LIP_Y, 0)
    var h := Vector3(-eye.x, 0.0, -eye.z)
    var hd := h.length()
    var dir := h / hd if hd > 0.05 else Vector3.RIGHT
    var lift := lerpf(HAND_LIFT_UNDER, HAND_LIFT, clampf(hd / 0.9, 0.0, 1.0))
    var ahead := HAND_AHEAD + AHEAD_PER_HAND * float(maxi(_count - 3, 0))
    var t := eye + dir * minf(hd, ahead) + Vector3(0, lift, 0)
    var off := t - lip
    if off.length() > REACH_MAX:
        t = lip + off.normalized() * REACH_MAX
    t.y = minf(t.y, LIP_Y - BELOW_LIP)
    # over the open grate's side the hands hang below its lower edge
    if t.x < -SIZE:
        t.y = minf(t.y, LIP_Y - 0.78)
    return t

# --- the head in under the vent -------------------------------------------------

## Where the eye sits for the look (local: LOOK_BACK out from the vent toward
## where the head came from, LOOK_DOWN below the face) and how far along the
## view the wrists of 3 hands float; each hand past the third pushes them
## LOOK_AHEAD_PER_HAND further up to a full row and LOOK_AHEAD_PAST_ROW past
## it, so 8 still fit. The view rises at LOOK_RISE.
const LOOK_BACK := 0.6
const LOOK_DOWN := 0.84
const LOOK_RISE := 0.3
const LOOK_AHEAD := 0.4
const LOOK_AHEAD_PER_HAND := 0.07
const LOOK_AHEAD_PAST_ROW := 0.02
## The hands reach toward the eye from the wrist: the wrists float this much
## above the middle of the view so the open palms, not the forearms, are in
## the centre.
const LOOK_WRIST_UP := 0.07
## The fan bends round the eye less up close, so the outer hands stay in frame.
const LOOK_ARC := 0.5
## Up close the hands stand this share of SPACING apart.
const LOOK_SPREAD := 0.88
## Up close the items are this much of their real size: the hand shows, not the item.
const LOOK_ITEM_SCALE := 0.47
## The head always comes in from this side of the vent: the open room, with
## the hanging grate edge-on at the side of the view.
const LOOK_FROM := Vector3(0.33, 0.0, 1.0)
## Up close the fingers rise a touch less, so their whole length shows.
const LOOK_CURL := 0.44
var _look_flat := Vector3.ZERO
## 0..1 how far the hands have changed to the close-up hold.
var _look_w := 0.0

## Which way the head comes in from, seen from the vent.
func begin_look(_eye_world: Vector3) -> void:
    _look_flat = LOOK_FROM.normalized()

func end_look() -> void:
    _look_flat = Vector3.ZERO

func looking() -> bool:
    return _look_flat != Vector3.ZERO

func _look_dir() -> Vector3:
    return (Vector3.UP * LOOK_RISE - _look_flat).normalized()

func _look_eye() -> Vector3:
    return _look_flat * LOOK_BACK + Vector3.DOWN * LOOK_DOWN

## The eye of the look, in world space. It never depends on the offer, so
## the head holds still while hands come and go.
func look_pose() -> Transform3D:
    var eye := to_global(_look_eye())
    var at := to_global(_look_eye() + _look_dir())
    return Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye)

func _look_cluster() -> Vector3:
    var dir := _look_dir()
    var up := (Vector3.UP - dir * dir.y).normalized()
    var ahead := LOOK_AHEAD + LOOK_AHEAD_PER_HAND * float(clampi(_count - 3, 0, 2)) + LOOK_AHEAD_PAST_ROW * float(maxi(_count - ROW_MAX, 0))
    return _look_eye() + dir * ahead + up * LOOK_WRIST_UP

## The hands follow the player slowly; every hand keeps a neutral wrist on
## the way down and only turns its palm up to the eye as the forearm swings out.
func _place_hands(delta: float) -> void:
    if _count <= 0 or _rigs.is_empty():
        return
    if _skin_mat != null and is_inside_tree():
        (_skin_mat as ShaderMaterial).set_shader_parameter("lip_y", to_global(Vector3(0, LIP_Y, 0)).y)
    var eye := _look_eye() if looking() else _eye()
    var target := _look_cluster() if looking() else _cluster_target(eye)
    var k := 1.0 if _snap else 1.0 - exp((-6.0 if looking() else -2.5) * delta)
    _center = _center.lerp(target, k)
    # the row runs across the line of sight, level
    var fwd := _center - eye
    var side := Vector3(fwd.z, 0.0, -fwd.x)
    if side.length() > 0.05:
        _side = _side.slerp(side.normalized(), k) if not _snap else side.normalized()
    _snap = false
    var view_up := _side.cross(fwd.normalized()).normalized()
    if view_up.y < 0.0:
        view_up = -view_up
    _look_w = move_toward(_look_w, 1.0 if looking() else 0.0, delta * 3.0)
    var item_scale := lerpf(ITEM_SCALE, LOOK_ITEM_SCALE, _look_w)
    var rows := int(ceil(float(_count) / float(ROW_MAX)))
    var e := _extend
    for i in range(_count):
        var rig: Dictionary = _rigs[i]
        var row := floori(float(i) / float(ROW_MAX))
        var in_row := mini(ROW_MAX, _count - row * ROW_MAX)
        var col := i % ROW_MAX
        var a := (float(col) - (in_row - 1) * 0.5) * SPACING
        var b := (float(row) - (rows - 1) * 0.5) * ROW_GAP
        # a shallow arc round the eye, and a little life in each hand
        var sway := Vector3(sin(_time * 0.9 + i * 2.3), sin(_time * 0.7 + i * 1.1) * 0.6, cos(_time * 0.8 + i * 1.9)) * 0.006
        # rows stagger by half a hand; the later rows hang higher and further
        # back, between the arms of the front row, clear of the player's hands
        if rows > 1:
            a += SPACING * (0.25 if row % 2 == 1 else -0.25)
        # up close the open palms reach wider than a hanging hand: a little closer together
        a *= lerpf(1.0, LOOK_SPREAD, _look_w)
        var arc := LOOK_ARC if looking() else 1.1
        var w_end := _center + _side * a + view_up * b - fwd.normalized() * (a * a * arc - 0.12 * float(row)) + sway
        # where the arm leaves the opening: above its hand, kept inside the frame
        var lip := Vector3(_center.x * 0.3, LIP_Y, _center.z * 0.3) + _side * a * 0.9 + Vector3(view_up.x, 0, view_up.z) * b * 0.6
        lip.x = clampf(lip.x, -SIZE + 0.045, SIZE - 0.045)
        lip.z = clampf(lip.z, -SIZE + 0.045, SIZE - 0.045)
        rig["side_a"] = a
        _pose_arm(rig, lip, w_end, e, eye, delta)
        var slot: Node3D = rig["slot"]
        slot.scale = Vector3.ONE * item_scale

## The final arm for a wrist at `w`: a two-bone chain from the shoulder in
## the duct, the forearm FOREARM long, bent to the arm's own elbow angle with
## the elbow pointing away from the eye and outward (kept
## under the lip and, beside the hanging grate, inside its edge so the upper
## arm comes down clear of it), and the hand's basis with the palm up to
## the eye. Returns [elbow, hand basis].
func _arm_target(rig: Dictionary, lip: Vector3, w: Vector3, eye: Vector3) -> Array:
    var out := Vector3(w.x - lip.x, 0.0, w.z - lip.z)
    var flat_eye := Vector3(eye.x - w.x, 0.0, eye.z - w.z)
    if out.length() < 0.03:
        out = flat_eye
    if out.length() < 0.01:
        out = Vector3(-_side.z, 0, _side.x)
    out = out.normalized()
    # toward the eye on the whole, each arm a little its own way
    if flat_eye.length() > 0.01:
        out = out.slerp(flat_eye.normalized(), 0.5)
    # the elbow: a two-bone chain from the shoulder up in the duct, the
    # forearm FOREARM long (shorter only on a short reach), bent to
    # the arm's own inside angle, pointing away from the eye and outward
    var sh := lip + Vector3.UP * SHOULDER_UP
    var sw := sh - w
    var d := sw.length()
    var theta: float = rig["bend"]
    var lf := minf(FOREARM, d * 0.48)
    var ang_s := asin(clampf(lf * sin(theta) / d, -1.0, 1.0))
    var ang_w := PI - theta - ang_s
    var away := (w - eye)
    away.y = maxf(away.y, 0.0)
    away = away.normalized() + _side * signf(float(rig.get("side_a", 0.0))) * 0.5 + Vector3.UP * 0.2
    away = away.rotated(Vector3.UP, float(rig["yaw"]))
    var swn := sw / d
    var perp := away - swn * away.dot(swn)
    perp = perp.normalized() if perp.length() > 0.01 else Vector3.UP.cross(swn).normalized()
    var el := w + (swn * cos(ang_w) + perp * sin(ang_w)) * lf
    el.y = minf(el.y, LIP_Y - 0.09)
    if w.x < -SIZE + 0.02 and el.x < -SIZE + 0.04:
        # beside the hanging grate: the elbow stays inside its edge and below
        # it, the forearm passing under the grate's lower edge
        el.x = -SIZE + 0.04
        el.y = minf(el.y, maxf(w.y + 0.04, LIP_Y - 0.66))
    var fdir := (w - el).normalized()
    # the palm: up and toward the eye; the fingers carry on the forearm's
    # line in that plane, which lifts the hand back a little at the wrist
    var to_eye := (eye - w).normalized()
    var n := (Vector3.UP * PALM_UP + to_eye).normalized()
    n = n.rotated(out.cross(Vector3.UP).normalized(), float(rig["tilt"]))
    var g := fdir - n * fdir.dot(n)
    if g.length() < 0.05:
        g = out
    g = g.normalized()
    var ang := fdir.angle_to(g)
    if ang > WRIST_MAX:
        g = fdir.slerp(g, WRIST_MAX / ang).normalized()
        n = (n - g * n.dot(g)).normalized()
    # a little roll about the fingers, each hand its own
    n = n.rotated(g, float(rig["roll"]))
    var y_ax := -g
    var z_ax := n
    var x_ax := y_ax.cross(z_ax).normalized()
    return [el, Basis(x_ax, y_ax, z_ax)]

## Arm and hand for offer progress `e`: first straight down out of the duct
## (fingers hanging, wrist straight), then the elbow comes out and bends, the
## forearm swings out toward the player turning the palm up, and the wrist
## lifts the hand to offer.
func _pose_arm(rig: Dictionary, lip: Vector3, w_end: Vector3, e: float, eye: Vector3, delta: float) -> void:
    var tgt := _arm_target(rig, lip, w_end, eye)
    var el_end: Vector3 = tgt[0]
    var hb_end: Basis = tgt[1]
    # thumbs open outward: a left hand on one side of the fan, a right on the other
    var a: float = rig.get("side_a", 0.0)
    var c := 1.0
    if absf(a) > 0.001 and hb_end.x.dot(_side) * a < 0.0:
        c = -1.0
    _set_chirality(rig, c)
    # hanging: fingers straight down, the palm toward the player
    var flat := Vector3(eye.x - lip.x, 0.0, eye.z - lip.z)
    flat = flat.normalized() if flat.length() > 0.01 else Vector3(-_side.z, 0, _side.x)
    var hang := Basis(Vector3.UP.cross(flat).normalized(), Vector3.UP, flat)
    var el_drop := lip + Vector3.DOWN * 0.1
    var fore_len := el_end.distance_to(w_end)
    var w: Vector3
    var el: Vector3
    var hb: Basis
    var swing := 0.0
    if e < DROP_PHASE:
        var u := smoothstep(0.0, 1.0, e / DROP_PHASE)
        el = (lip + Vector3.UP * (fore_len + 0.45)).lerp(el_drop, u)
        w = el + Vector3.DOWN * fore_len
        hb = hang
    else:
        swing = smoothstep(0.0, 1.0, (e - DROP_PHASE) / (1.0 - DROP_PHASE))
        el = el_drop.lerp(el_end, swing)
        var fdir := Vector3.DOWN.slerp((w_end - el_end).normalized(), swing)
        w = el + fdir * fore_len
        hb = Basis(hang.get_rotation_quaternion().slerp(hb_end.get_rotation_quaternion(), swing))
    var q := hb.get_rotation_quaternion()
    var prev: Quaternion = rig["rot"]
    var kq := 1.0 if delta <= 0.0 else 1.0 - exp(-10.0 * delta)
    q = prev.slerp(q, kq) if prev != Quaternion.IDENTITY else q
    rig["rot"] = q
    # the upper arm from the shoulder up in the duct down to the elbow
    var sh := lip + Vector3.UP * SHOULDER_UP
    sh.y = maxf(sh.y, el.y + 0.1)
    var up_v := sh - el
    var upper: MeshInstance3D = rig["upper"]
    upper.transform = Transform3D(_frame(up_v.normalized(), up_v.length()), el)
    var el_mesh: MeshInstance3D = rig["elbow"]
    el_mesh.transform = Transform3D(_frame(up_v.normalized(), 1.0), el)
    var fore: MeshInstance3D = rig["fore"]
    var arm := el - w
    var along := arm.normalized() if arm.length() > 0.001 else Vector3.UP
    fore.transform = Transform3D(_frame(along, arm.length()), w)
    var hand: Node3D = rig["hand"]
    hand.transform = Transform3D(Basis(q), w)
    # the forearm's flat oval turns with the wrist (the palm turning up turns
    # the forearm), so the wrist flows into the back of the hand with no edge
    var hx := Basis(q).x
    hx = hx - along * hx.dot(along)
    if hx.length() > 0.05 and arm.length() > 0.001:
        hx = hx.normalized()
        fore.transform = Transform3D(Basis(hx, along * arm.length(), hx.cross(along).normalized()), w)

## A basis whose Y axis runs along `dir` scaled to `length` (X, Z unit).
static func _frame(dir: Vector3, length: float) -> Basis:
    var ref := Vector3.FORWARD if absf(dir.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
    var x := ref.cross(dir).normalized()
    var z := x.cross(dir).normalized()
    return Basis(x, dir * maxf(length, 0.001), z)

func set_open(amount: float) -> void:
    _black_cover.visible = amount < 0.02
    _grate.rotation_degrees.z = -100.0 * clampf(amount, 0.0, 1.0)

func play_open() -> void:
    var tw := create_tween()
    tw.tween_method(set_open, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The being shows no eyes (user 2026-11-03: "환풍구에 눈 항상 보이지 않게").
## Kept so the vent logic and art tests can still call them.
func blink() -> void:
    pass

func set_eyes(_show: bool) -> void:
    pass

func set_eye_mood(frantic: float) -> void:
    _mood = clampf(frantic, 0.0, 1.0)

## Teeth the player put on the lip, waiting to be looked at (one per tooth).
const PILE_MAX := 60
var _pile: MultiMeshInstance3D

func _build_pile() -> void:
    _pile = MultiMeshInstance3D.new()
    _pile.name = "TeethPile"
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    var st := K.begin()
    K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, -0.004), Vector2(0.0075, -0.003), Vector2(0.009, 0.002), Vector2(0.008, 0.006), Vector2(0.004, 0.0085), Vector2(0.0, 0.007)], 6, [Color(0.9, 0.84, 0.66)])
    mm.mesh = K.finish(st, 60.0)
    mm.instance_count = PILE_MAX
    for i in range(PILE_MAX):
        # a small heap on the near lip, growing in rings
        var ring := int(sqrt(float(i)))
        var a := float(i) * 2.39996
        var r := 0.012 * float(ring)
        var pos := Vector3(cos(a) * r, -0.004 - 0.006 * float(ring % 3), SIZE - 0.05 + sin(a) * r * 0.6)
        mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(K.h(i, 1), K.h(i, 2), K.h(i, 3)) * TAU).scaled(Vector3.ONE * 2.2), pos))
    mm.visible_instance_count = 0
    _pile.multimesh = mm
    _pile.material_override = K.mat("tex_ceramic_64.png", 0.5, false)
    _pile.custom_aabb = AABB(Vector3(-0.2, -0.1, -0.2), Vector3(0.4, 0.2, 0.6))
    add_child(_pile)

func set_pile(n: int) -> void:
    if _pile != null:
        _pile.multimesh.visible_instance_count = clampi(n, 0, PILE_MAX)

func pile_count() -> int:
    return _pile.multimesh.visible_instance_count if _pile != null else 0

## 0 = the arms are up in the black duct, 1 = held out in front of the player.
func set_offer_extend(t: float) -> void:
    _extend = clampf(t, 0.0, 1.0)
    _arms.visible = _extend > 0.001 and _count > 0
    if _arms.visible:
        _place_hands(0.0)

func play_offer() -> void:
    if not _wanted:
        return
    _snap = true
    _hand_to(1.0, 1.4, Tween.EASE_IN_OUT)

func play_withdraw() -> void:
    _hand_to(0.0, 0.4, Tween.EASE_IN)

# --- absurd overpay: things spill out -------------------------------------------

## "큭 켘." and early items spill out of the duct (spec 03-restroom §7 거래
## 규칙). They are the player's at once (FPVent grants them before this), so
## each one tumbles out of the black, bounces on the floor under the vent,
## lies there a moment and is then swept to the player's waist, the way a
## taken item goes to the belt. Real size, no collision with the room.
const SPILL_GAP := 0.16
const SPILL_GRAVITY := 9.8
const SPILL_BOUNCE := 0.32
## Seconds an item lies on the floor before it goes to the waist.
const SPILL_REST := 1.5
const SPILL_STOW := 0.45
## The waist below the eye, where the item is swept to.
const SPILL_WAIST := 0.72
## Pitch that lays an item down on the floor: items are modelled to face out
## of the being's palm (+Z), so a knife would otherwise stand on its edge.
const SPILL_LIE := {"knife": -PI * 0.5}
var _spill: Array = []
var _spill_root: Node3D
var _spill_floor := -2.57

## Item kinds as for set_offer_items; `floor_y` is the room floor in this
## node's frame (the vent face is y = 0).
func play_spill(kinds: Array, floor_y: float) -> void:
    _spill_floor = floor_y
    if _spill_root == null:
        _spill_root = K.pivot(self, "Spill")
    var eye := _eye()
    var toward := Vector3(eye.x, 0.0, eye.z)
    toward = toward.normalized() if toward.length() > 0.05 else Vector3(0, 0, 1)
    for i in range(kinds.size()):
        var item := FPItemArt.make(str(kinds[i]), 40 + i)
        item.name = "Spilled%d" % _spill.size()
        _spill_root.add_child(item)
        FPItemArt.set_layers(item, _black_cover.layers)
        item.visible = false
        # out of the dark above the lip, a little apart, each kicked a bit
        # toward the player and to its own side
        var side := Vector3(-toward.z, 0.0, toward.x) * (K.h(i, 7) - 0.5) * 1.4
        var start := Vector3((K.h(i, 3) - 0.5) * 0.24, 0.18, (K.h(i, 5) - 0.5) * 0.24)
        var vel := toward * (0.35 + 0.45 * K.h(i, 9)) + side + Vector3(0, -0.2, 0)
        var spin := Vector3(K.h(i, 11) - 0.5, K.h(i, 13) - 0.5, K.h(i, 17) - 0.5) * 18.0
        item.position = start
        item.rotation = Vector3(K.h(i, 19), K.h(i, 23), K.h(i, 29)) * TAU
        _spill.append({"node": item, "vel": vel, "spin": spin, "wait": float(i) * SPILL_GAP, "state": "fall", "t": 0.0, "bounced": false, "lie": float(SPILL_LIE.get(str(kinds[i]), 0.0))})

## Items still on their way (falling, lying or going to the waist).
func spill_count() -> int:
    return _spill.size()

func spill_nodes() -> Array:
    var out: Array = []
    for s in _spill:
        out.append(s["node"])
    return out

## Advance the spill by `delta` (called from _process; tests call it directly).
func step_spill(delta: float) -> void:
    var rest_y := _spill_floor + 0.03
    for s in _spill:
        var n: Node3D = s["node"]
        if s["wait"] > 0.0:
            s["wait"] = float(s["wait"]) - delta
            continue
        n.visible = true
        match String(s["state"]):
            "fall":
                var v: Vector3 = s["vel"]
                v.y -= SPILL_GRAVITY * delta
                n.position += v * delta
                n.rotation += (s["spin"] as Vector3) * delta
                if n.position.y <= rest_y and v.y < 0.0:
                    n.position.y = rest_y
                    if not s["bounced"] and -v.y > 1.0:
                        s["bounced"] = true
                        v = Vector3(v.x * 0.5, -v.y * SPILL_BOUNCE, v.z * 0.5)
                        s["spin"] = (s["spin"] as Vector3) * 0.4
                    else:
                        # lies flat where it stopped, its own way round
                        s["state"] = "rest"
                        s["t"] = 0.0
                        n.rotation = Vector3(float(s["lie"]), n.rotation.y, 0.0)
                        s["from"] = n.position
                s["vel"] = v
            "rest":
                s["t"] = float(s["t"]) + delta
                if float(s["t"]) >= SPILL_REST:
                    s["state"] = "stow"
                    s["t"] = 0.0
                    s["from"] = n.position
            "stow":
                s["t"] = float(s["t"]) + delta
                var u := clampf(float(s["t"]) / SPILL_STOW, 0.0, 1.0)
                var waist := _eye() - Vector3(0, SPILL_WAIST, 0)
                var e := u * u
                n.position = (s["from"] as Vector3).lerp(waist, e) + Vector3(0, sin(u * PI) * 0.25, 0)
                n.scale = Vector3.ONE * lerpf(1.0, 0.35, e)
                if u >= 1.0:
                    s["state"] = "done"
    for i in range(_spill.size() - 1, -1, -1):
        if String(_spill[i]["state"]) == "done":
            var gone: Node3D = _spill[i]["node"]
            _spill.remove_at(i)
            gone.queue_free()

func capture_setup() -> Dictionary:
    set_open(1.0)
    set_offer_extend(1.0)
    # capture only: the restroom ceiling tiles around the opening
    var st := K.begin()
    for i in range(4):
        var t := K.T(Vector3.ZERO, Vector3(0, 90 * i, 0))
        K.quad(st, t, Vector3(-1.2, 0, -1.2), Vector3(1.2, 0, -1.2), Vector3(SIZE + 0.06, 0, -SIZE - 0.06), Vector3(-SIZE - 0.06, 0, -SIZE - 0.06), Vector3.DOWN, Color(0.9, 0.9, 0.9))
    K.add_mesh(self, "CaptureCeiling", K.finish(st, 2.0), K.mat("tex_tile_wall_64.png", 0.1, false))
    return {"cam_pos": Vector3(0.42, -0.95, 0.68), "look_at": Vector3(0, 0.05, 0), "env": "restroom", "fov": 60.0}
