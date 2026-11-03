extends Node3D

const K := preload("res://main/art/fp_art_kit.gd")

## Ceiling vent (the shop). Local frame: the vent face lies on y=0 and the
## duct goes UP (+Y), so it is seen from below. Grate hinges down on its -X
## edge. Nothing of the being shows in the dark duct (no eyes, user
## 2026-11-03); when it offers, one slender arm per offered item comes down
## out of the black and holds its item out close in front of the player's
## eye, cradled in the hook of the fingers.
## Public: set_open(0..1), play_open(), play_offer(), play_withdraw(),
## set_offer_items(kinds), take_item(i), item_node(i), hand_count(),
## set_pile(n). set_eyes(), blink() and set_eye_mood() stay callable for the
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
const HAND_LIFT := 0.13
const HAND_LIFT_UNDER := 0.4
const REACH_MAX := 1.4
## Lip height of the opening (the elbow rests here) and the lowest the
## hand cluster's middle may hang above it.
const LIP_Y := -0.03
const BELOW_LIP := 0.32
## Hands side by side (metres between wrists) and rows of at most ROW_MAX.
const SPACING := 0.16
const ROW_GAP := 0.21
const ROW_MAX := 5
## Each hand past the third pushes the fan this much further out, so a wide
## offer still fits the view without the hands crowding each other.
const AHEAD_PER_HAND := 0.035
## The wrist never bends further than this from the forearm line.
const WRIST_MAX := 0.32
## Share of the offer tween spent coming straight down out of the duct
## before the forearm swings out toward the player.
const DROP_PHASE := 0.42
## Where the offered item lies in the hand (hand frame: fingers point down
## -Y, the palm faces +Z, the thumb is on +X), in the hook of the fingers.
const HOLD := Vector3(0.003, -0.097, 0.034)
## Offered items at this share of their real size (they are what the hand
## then carries to the belt), so the fingers still show round them.
const ITEM_SCALE := 0.72
## Soft, bright porcelain skin with a little warmth at the knuckles and
## tips, and clean pale-pink almond nails with white tips: a hand that makes
## you expect a very beautiful person (user 2026-11-03).
const SKIN := Color(1.0, 0.88, 0.82)
const SKIN_SHADE := Color(0.95, 0.8, 0.75)
const SKIN_BLUSH := Color(1.0, 0.81, 0.78)
## Nails carry alpha 0.75 / 0.8: the being's shader gives them a sheen.
const NAIL := Color(1.0, 0.78, 0.82, 0.75)
const NAIL_TIP := Color(1.0, 0.99, 0.97, 0.8)
## Hand proportions measured on photo references of slim, well-kept women's
## hands (orchestra/vent/ref/proportions.md, kept outside the repo): middle
## finger 0.075 m; index 0.92, ring 0.95, little 0.77, thumb 0.68 of it;
## palm length 1.16 and breadth 0.99 of it; wrist 0.74 of the breadth;
## finger base width 0.20 of the middle finger, tips 0.8 of the base;
## phalanges 0.38 : 0.25 : 0.37 from the finger root; nails 0.57 of the
## tip bone long and 0.82 of the fingertip wide. Hand frame: wrist at 0,
## fingers down -Y, palm +Z, thumb +X.
const PALM_LEN := 0.087
const PALM_HALF := 0.037
const WRIST_HALF := 0.0275
## The knuckle (MCP) sits this far inside the finger root line.
const MCP_IN := 0.012
## Fingers index to little: x, finger root height (share of the palm
## length: the root line arches down toward the little finger), length,
## base radius, sideways splay (degrees), curl share (the photos' cascade:
## each finger toward the little one curls a little more).
const FINGERS := [
    [0.0265, 0.955, 0.069, 0.0074, -3.0, 0.92],
    [0.009, 1.0, 0.075, 0.0077, 0.0, 1.0],
    [-0.0085, 0.97, 0.071, 0.0073, 2.0, 1.05],
    [-0.0255, 0.865, 0.058, 0.0064, 4.0, 1.12],
]
const PHALANX := [0.38, 0.25, 0.37]
const THUMB_LEN := 0.051
## The thumb in the holding pose: forward and across the front of the item.
const THUMB_HOLD := Vector3(-62, 0, -38)
## Curl at rest (holding) and when gripping on the take; per joint the
## middle (PIP) bends most and the tip (DIP) least, as in the photos.
const CURL_REST := 1.15
const CURL_GRIP := 1.4
const JOINT_SHARE := [0.5, 0.95, 0.55]

var _arms: Node3D
## One rig per hand: {root, upper, fore, elbow, hand, slot, fingers, thumb, mirror}.
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

## The being's own soft skin (user 2026-11-03: the low-poly facets should
## not show): smooth normals from _smooth(), a wrapped (half-Lambert) key
## light so the shade side never goes hard, a warm subsurface-like tint
## where the light wraps and at grazing edges, a faint rim, and a gentle
## sheen only on the nails (vertex alpha below 1 marks them). Unshaded like
## the body's skin pipeline, so the bright ceiling lamp cannot blow it out;
## the player's skin material (FDKSkinMaterial) is not touched.
const SKIN_SHADER := """shader_type spatial;
render_mode unshaded, cull_back;
uniform vec3 key_dir = vec3(0.35, 0.85, 0.4);
uniform vec3 warm : source_color = vec3(1.0, 0.56, 0.5);
uniform float wrap_lo = 0.74;
uniform float wrap_hi = 1.05;
uniform float sss = 0.16;
uniform float rim = 0.14;
uniform float nail_sheen = 0.45;
varying vec3 wn;
void vertex() {
    wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
    vec3 n = normalize(wn);
    if (!FRONT_FACING) { n = -n; }
    vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
    vec3 l = normalize(key_dir);
    float ndl = dot(n, l);
    float wrap = pow(clamp(ndl * 0.5 + 0.5, 0.0, 1.0), 1.4);
    float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.2);
    vec3 base = COLOR.rgb;
    vec3 col = base * mix(wrap_lo, wrap_hi, wrap);
    // light passing through thin skin: warm where it wraps into shade and at the silhouette
    col += base * warm * sss * (1.0 - wrap) * 0.9;
    col = mix(col, col * mix(vec3(1.0), warm * 1.35, 0.5), fres * 0.35);
    col += vec3(1.0, 0.96, 0.94) * rim * fres * wrap;
    float gloss = clamp((1.0 - COLOR.a) * 4.0, 0.0, 1.0);
    vec3 h = normalize(l + v);
    float spec = pow(max(dot(n, h), 0.0), mix(18.0, 60.0, gloss));
    col += vec3(1.0) * spec * mix(0.035, nail_sheen, gloss);
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

## Smooth shading for a flat-faceted kit mesh: every corner at the same
## place gets the average normal of the faces meeting there, so the facets
## of the hand and fingers read as soft, round skin instead of planes.
static func _smooth(mesh: ArrayMesh) -> ArrayMesh:
    var arr := mesh.surface_get_arrays(0)
    var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
    var sums := {}
    for i in range(verts.size()):
        var key := Vector3i((verts[i] * 20000.0).round())
        sums[key] = (sums.get(key, Vector3.ZERO) as Vector3) + norms[i]
    var out := PackedVector3Array()
    out.resize(verts.size())
    for i in range(verts.size()):
        var nsum: Vector3 = sums[Vector3i((verts[i] * 20000.0).round())]
        out[i] = nsum.normalized() if nsum.length() > 0.0001 else norms[i]
    arr[Mesh.ARRAY_NORMAL] = out
    # the planar UVs' tangents no longer match; nothing here samples them
    arr[Mesh.ARRAY_TANGENT] = null
    var m := ArrayMesh.new()
    m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
    return m

## Elliptical tube along `pts` (mostly along -Y or +Y): rx across the palm
## (X), rz through it (Z), one colour per segment.
## `arch` (optional, per ring) lifts each ring point by arch * |x| on the
## little-finger side (-X) and a third of that on the index side, so the
## palm's knuckle line arches like the photos instead of ending square.
static func _oval(st: SurfaceTool, t: Transform3D, pts: Array, rx: Array, rz: Array, sides: int, cols: Array, caps: bool = true, arch: Array = []) -> void:
    var rings: Array = []
    for i in range(pts.size()):
        var p: Vector3 = pts[i]
        var ring := PackedVector3Array()
        var lift: float = float(arch[i]) if i < arch.size() else 0.0
        for j in range(sides):
            var a := TAU * float(j) / float(sides)
            var x := cos(a) * float(rx[i])
            var y := lift * (-x if x < 0.0 else x * 0.33)
            ring.append(t * (p + Vector3(x, y, sin(a) * float(rz[i]))))
        rings.append(ring)
    FDKLowPoly.loft(st, rings, cols, caps, caps)

func _build_meshes() -> void:
    if not _meshes.is_empty():
        return
    # Silhouettes stay round (user 2026-11-03: the angles should not show):
    # 12-20 sided rings, more rings where the outline curves, smooth normals.
    var st := K.begin()
    # forearm, built one unit long from the wrist (0) up to the elbow (1);
    # the rig stretches it along Y to the real length. It swells only a
    # little above the wrist so a fan of eight arms stays light.
    _oval(st, Transform3D.IDENTITY, [Vector3(0, -0.012, 0), Vector3(0, 0.05, 0), Vector3(0, 0.16, 0), Vector3(0, 0.45, 0), Vector3(0, 0.75, 0), Vector3(0, 1.0, 0)], [WRIST_HALF * 0.97, WRIST_HALF, WRIST_HALF * 1.05, WRIST_HALF * 1.12, WRIST_HALF * 1.12, WRIST_HALF * 1.08], [WRIST_HALF * 0.66, WRIST_HALF * 0.7, WRIST_HALF * 0.8, WRIST_HALF * 0.95, WRIST_HALF * 1.0, WRIST_HALF * 0.98], 12, [SKIN, SKIN, SKIN, SKIN, SKIN_SHADE], false)
    _meshes["fore"] = K.finish(st, 8.0)
    # upper arm, straight up from the elbow into the black (true length)
    st = K.begin()
    _oval(st, Transform3D.IDENTITY, [Vector3(0, -0.01, 0), Vector3(0, 0.3, 0), Vector3(0, 0.62, 0), Vector3(0, 0.9, 0), Vector3(0, 1.4, 0)], [0.03, 0.032, 0.033, 0.034, 0.035], [0.028, 0.03, 0.031, 0.032, 0.033], 12, [SKIN_SHADE, Color(0.6, 0.53, 0.51), Color(0.12, 0.1, 0.1), Color(0.01, 0.01, 0.01)], false)
    _meshes["upper"] = K.finish(st, 8.0)
    # the elbow, a soft round joint where the two meet
    st = K.begin()
    K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, -0.03), Vector2(0.015, -0.026), Vector2(0.026, -0.015), Vector2(0.03, 0.0), Vector2(0.026, 0.015), Vector2(0.015, 0.026), Vector2(0.0, 0.03)], 12, [SKIN_SHADE, SKIN, SKIN, SKIN, SKIN, SKIN_SHADE])
    _meshes["elbow"] = K.finish(st, 8.0)
    # wrist and palm to the measured ratios: the wrist 0.74 of the palm's
    # breadth flowing into it, the palm's outline rounded (many rings, 20
    # sides), widest just below the knuckles, its end arched like the
    # photos; a thenar mound where the thumb leaves (0.3 of the palm down)
    # and a soft web from it to the index root
    st = K.begin()
    var wz := WRIST_HALF * 0.68
    var ys := [0.02, 0.006, -0.006, -0.018, -0.032, -0.046, -0.058, -0.066, -0.071, -PALM_LEN + MCP_IN - 0.001, -PALM_LEN + MCP_IN - 0.005, -PALM_LEN + MCP_IN - 0.008]
    var rx := [WRIST_HALF, WRIST_HALF * 1.0, WRIST_HALF * 1.04, PALM_HALF * 0.86, PALM_HALF * 0.93, PALM_HALF * 0.975, PALM_HALF, PALM_HALF * 0.995, PALM_HALF * 0.97, PALM_HALF * 0.9, PALM_HALF * 0.76, PALM_HALF * 0.5]
    var rz := [wz, wz * 0.97, wz * 0.95, 0.0142, 0.0141, 0.0136, 0.013, 0.0124, 0.0118, 0.0108, 0.0096, 0.0075]
    var arch := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.03, 0.1, 0.22, 0.34, 0.36, 0.36]
    var pts: Array = []
    for k in range(ys.size()):
        pts.append(Vector3(0, float(ys[k]), 0.001))
    var cols: Array = []
    for k in range(ys.size() - 1):
        cols.append(SKIN)
    _oval(st, Transform3D.IDENTITY, pts, rx, rz, 20, cols, true, arch)
    _oval(st, Transform3D.IDENTITY, [Vector3(0.012, -0.004, 0.004), Vector3(0.018, -0.014, 0.0065), Vector3(0.023, -0.025, 0.0078), Vector3(0.027, -0.036, 0.008), Vector3(0.029, -0.044, 0.0075)], [0.01, 0.0128, 0.013, 0.0112, 0.0085], [0.0075, 0.0094, 0.0098, 0.0092, 0.0078], 12, [SKIN, SKIN, SKIN, SKIN], true)
    # the web between thumb and index, thin, on the thumb side
    _oval(st, Transform3D.IDENTITY, [Vector3(0.026, -0.04, 0.006), Vector3(0.028, -0.052, 0.005), Vector3(0.027, -0.064, 0.004)], [0.009, 0.0085, 0.006], [0.0062, 0.0055, 0.0045], 12, [SKIN, SKIN], true)
    _meshes["palm"] = K.finish(st, 8.0)
    for i in range(FINGERS.size()):
        var f: Array = FINGERS[i]
        var length: float = f[2]
        var r: float = f[3]
        _meshes["f%d_0" % i] = _bone_mesh(length * PHALANX[0] + MCP_IN, r, r * 0.93, false)
        _meshes["f%d_1" % i] = _bone_mesh(length * PHALANX[1], r * 0.93, r * 0.86, false)
        _meshes["f%d_2" % i] = _bone_mesh(length * PHALANX[2], r * 0.86, r * 0.8, true)
    _meshes["thumb_p"] = _bone_mesh(THUMB_LEN * 0.55, 0.0086, 0.0079, false)
    _meshes["thumb_d"] = _bone_mesh(THUMB_LEN * 0.45, 0.0079, 0.0069, true)
    for k in _meshes.keys():
        _meshes[k] = _smooth(_meshes[k])

## One finger bone hanging down -Y from its joint: a 12-sided tapering tube
## with a slight knuckle swell at its joint (the next bone starts inside
## it, so the joint reads as one soft bulge). The tip bone ends in a round
## capsule and carries the nail on its back (-Z): 0.57 of the bone long,
## 0.82 of the fingertip wide, a 2 mm free edge.
func _bone_mesh(length: float, r0: float, r1: float, tip: bool) -> ArrayMesh:
    var st := K.begin()
    var d0 := r0 * 0.88
    if tip:
        var py := [0.004, 0.0, -length * 0.35, -length * 0.7, -length * 0.86, -length * 0.95, -length - 0.0005, -length - 0.0025]
        var px := [r0 * 0.98, r0 * 1.03, (r0 + r1) * 0.5, r1, r1 * 0.96, r1 * 0.84, r1 * 0.6, r1 * 0.22]
        var pz := [d0 * 0.98, d0 * 1.03, (d0 + r1 * 0.88) * 0.5, r1 * 0.88, r1 * 0.85, r1 * 0.75, r1 * 0.55, r1 * 0.2]
        var pts: Array = []
        for k in range(py.size()):
            pts.append(Vector3(0, float(py[k]), 0.0006 * float(k) / float(py.size())))
        _oval(st, Transform3D.IDENTITY, pts, px, pz, 12, [SKIN, SKIN, SKIN, SKIN, SKIN_BLUSH, SKIN_BLUSH, SKIN_BLUSH], true)
        var nz := -r1 * 0.8
        var nl := length * 0.57
        var nw := r1 * 0.82
        _oval(st, Transform3D.IDENTITY, [Vector3(0, -length + nl, nz + 0.0002), Vector3(0, -length + nl * 0.75, nz - 0.0005), Vector3(0, -length + nl * 0.4, nz - 0.0007), Vector3(0, -length + nl * 0.1, nz - 0.0004), Vector3(0, -length - 0.002, nz + 0.0012)], [nw * 0.75, nw * 0.95, nw, nw * 0.88, nw * 0.45], [0.0008, 0.0011, 0.0012, 0.0011, 0.0007], 10, [NAIL, NAIL, NAIL, NAIL_TIP], true)
    else:
        _oval(st, Transform3D.IDENTITY, [Vector3(0, 0.004, 0), Vector3(0, 0.0, 0), Vector3(0, -length * 0.35, 0.0), Vector3(0, -length * 0.75, 0.0), Vector3(0, -length - 0.004, 0.0)], [r0 * 0.98, r0 * 1.04, r0 * 0.98, (r0 + r1) * 0.5, r1], [d0 * 0.98, d0 * 1.04, d0 * 0.96, (d0 + r1 * 0.86) * 0.5, r1 * 0.86], 12, [SKIN, SKIN, SKIN, SKIN], false)
    return K.finish(st, 10.0)

func _new_rig(index: int) -> Dictionary:
    _build_meshes()
    var skin := _skin()
    var root := K.pivot(_arms, "Hand%d" % index)
    var upper := K.add_mesh(root, "UpperArm", _meshes["upper"], skin)
    var fore := K.add_mesh(root, "Forearm", _meshes["fore"], skin)
    var elbow := K.add_mesh(root, "Elbow", _meshes["elbow"], skin)
    var hand := K.pivot(root, "Palm")
    K.add_mesh(hand, "Hand", _meshes["palm"], skin)
    var fingers: Array = []
    for i in range(FINGERS.size()):
        var f: Array = FINGERS[i]
        var length: float = f[2]
        var root_y := -PALM_LEN * float(f[1])
        var prox := K.pivot(hand, "Finger%d" % i, Vector3(float(f[0]), root_y + MCP_IN, 0.0))
        prox.rotation_degrees.z = float(f[4])
        K.add_mesh(prox, "Bone", _meshes["f%d_0" % i], skin)
        var mid := K.pivot(prox, "Mid", Vector3(0, -(length * PHALANX[0] + MCP_IN), 0))
        K.add_mesh(mid, "Bone", _meshes["f%d_1" % i], skin)
        var tip := K.pivot(mid, "Tip", Vector3(0, -length * PHALANX[1], 0))
        K.add_mesh(tip, "Bone", _meshes["f%d_2" % i], skin)
        fingers.append([prox, mid, tip, float(f[5])])
    # the thumb leaves the palm 0.3 of its length down on the +X side and
    # lies across the front of the item, closing the grip
    var tp := K.pivot(hand, "Thumb", Vector3(0.03, -PALM_LEN * 0.36, 0.012))
    tp.rotation_degrees = THUMB_HOLD
    K.add_mesh(tp, "Bone", _meshes["thumb_p"], skin)
    var td := K.pivot(tp, "Tip", Vector3(0, -THUMB_LEN * 0.55, 0))
    td.rotation_degrees = Vector3(-14, 0, 12)
    K.add_mesh(td, "Bone", _meshes["thumb_d"], skin)
    var slot := K.pivot(hand, "Offer%d" % index, HOLD)
    var lit := _black_cover.layers
    for n in root.find_children("*", "VisualInstance3D", true, false):
        (n as VisualInstance3D).layers = lit
    return {"root": root, "upper": upper, "fore": fore, "elbow": elbow, "hand": hand, "slot": slot, "fingers": fingers, "thumb": [tp, td], "rot": Quaternion.IDENTITY, "mirror": 1.0, "roll": sin(float(index) * 2.3 + 0.4) * 0.16}

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
            slot.rotation_degrees = Vector3(0, 0, -6.0 + 4.0 * float(i % 3))
            slot.scale = Vector3.ONE * ITEM_SCALE
            _offers.append(slot)
    _set_curl(0.0)
    var lit := _black_cover.layers
    for n in _arms.find_children("*", "VisualInstance3D", true, false):
        (n as VisualInstance3D).layers = lit
    _snap = true
    _place_hands(0.0)

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

func _pose_fingers() -> void:
    if flat_pose:
        for rig in _rigs:
            for f in rig["fingers"]:
                for j in range(3):
                    (f[j] as Node3D).rotation.x = 0.0
            (rig["thumb"][0] as Node3D).rotation_degrees = Vector3(-8, 0, 22)
            (rig["thumb"][1] as Node3D).rotation_degrees = Vector3(0, 0, 4)
        return
    for ri in range(mini(_count, _rigs.size())):
        var rig: Dictionary = _rigs[ri]
        for i in range(4):
            var f: Array = rig["fingers"][i]
            var k: float = f[3]
            # a slow breath through the fingers, quicker when the being is impatient
            var fidget := sin(_time * lerpf(1.6, 5.0, _mood) + i * 0.9 + ri * 1.7) * lerpf(0.02, 0.05, _mood)
            var c := lerpf(CURL_REST, CURL_GRIP, _curl) + fidget
            # the fingers close round the item: the tips come back over its front
            for j in range(3):
                (f[j] as Node3D).rotation.x = -c * k * float(JOINT_SHARE[j])
        var th: Array = rig["thumb"]
        (th[0] as Node3D).rotation_degrees = THUMB_HOLD
        (th[1] as Node3D).rotation_degrees.x = -14.0 - 30.0 * _curl

func _hand_to(target: float, secs: float, ease_type: Tween.EaseType) -> void:
    if _hand_tw != null:
        _hand_tw.kill()
    _hand_tw = create_tween()
    _hand_tw.tween_method(set_offer_extend, _extend, target, secs).set_trans(Tween.TRANS_SINE).set_ease(ease_type)

func _process(delta: float) -> void:
    _time += delta
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

## The hands follow the player slowly; every hand keeps a neutral wrist on
## the way down and only turns its palm to the eye as the forearm swings out.
func _place_hands(delta: float) -> void:
    if _count <= 0 or _rigs.is_empty():
        return
    var eye := _eye()
    var target := _cluster_target(eye)
    var k := 1.0 if _snap else 1.0 - exp(-2.5 * delta)
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
        var w_end := _center + _side * a + view_up * b - fwd.normalized() * (a * a * 1.1 - 0.12 * float(row)) + sway
        # where the arm leaves the opening: under its hand, kept inside the frame
        var lip := Vector3(_center.x * 0.3, LIP_Y, _center.z * 0.3) + _side * a * 0.9 + Vector3(view_up.x, 0, view_up.z) * b * 0.6
        lip.x = clampf(lip.x, -SIZE + 0.045, SIZE - 0.045)
        lip.z = clampf(lip.z, -SIZE + 0.045, SIZE - 0.045)
        var elbow := lip - Vector3(0, _grate_drop(lip, w_end), 0)
        rig["mirror"] = -1.0 if a < -0.001 else 1.0
        _pose_arm(rig, lip, elbow, w_end, e, eye, delta)

## How far the elbow must hang below the lip so the forearm passes under
## the open grate (it hangs down from the -X edge) instead of through it.
func _grate_drop(lip: Vector3, w: Vector3) -> float:
    var xg := -SIZE - 0.12
    var yb := LIP_Y - 0.6
    if w.x >= xg or lip.x <= w.x:
        return 0.0
    var f := (lip.x - xg) / (lip.x - w.x)
    if f >= 0.98:
        return 0.0
    var drop := lip.y - (yb - w.y * f) / (1.0 - f)
    return clampf(drop, 0.0, maxf(lip.y - w.y - 0.12, 0.0))

## Arm and hand for offer progress `e`: first straight down out of the duct
## (fingers hanging, wrist straight), then the forearm swings out about the
## elbow toward the player while the hand turns its palm to the eye.
func _pose_arm(rig: Dictionary, lip: Vector3, elbow: Vector3, w_end: Vector3, e: float, eye: Vector3, delta: float) -> void:
    var w: Vector3
    var el: Vector3
    var swing := 0.0
    if e < DROP_PHASE:
        var u := smoothstep(0.0, 1.0, e / DROP_PHASE)
        w = (lip + Vector3(0, 0.5, 0)).lerp(elbow - Vector3(0, 0.1, 0), u)
        el = elbow if w.y < elbow.y else w + Vector3(0, 0.02, 0)
    else:
        swing = smoothstep(0.0, 1.0, (e - DROP_PHASE) / (1.0 - DROP_PHASE))
        var full := w_end - elbow
        var dir := Vector3.DOWN.slerp(full.normalized(), swing)
        w = elbow + dir * lerpf(0.1, full.length(), swing)
        el = elbow
    var upper: MeshInstance3D = rig["upper"]
    upper.position = el
    var fore: MeshInstance3D = rig["fore"]
    var arm := el - w
    var along := arm.normalized() if arm.length() > 0.001 else Vector3.UP
    fore.transform = Transform3D(_frame(along, arm.length()), w)
    var el_mesh: MeshInstance3D = rig["elbow"]
    el_mesh.position = el
    el_mesh.visible = e >= DROP_PHASE or w.y < elbow.y
    # the hand: the fingers carry on along the forearm and only let the
    # wrist drop softly toward hanging (at most WRIST_MAX, and only once the
    # forearm swings out); the palm turns to the eye with the item held in
    # front of it, the fingers closed round it so their nails show
    var a_dir := -along
    var to_eye := (eye - w).normalized()
    var g := a_dir
    var bend := a_dir.angle_to(Vector3.DOWN)
    if bend > 0.001:
        g = a_dir.slerp(Vector3.DOWN, minf(1.0, WRIST_MAX * swing / bend))
    var n := to_eye - g * to_eye.dot(g)
    if n.length() < 0.05:
        n = Vector3(-_side.z, 0, _side.x)
    n = n.normalized()
    var y_ax := -g.normalized()
    var x_ax := y_ax.cross(n).normalized()
    var z_ax := x_ax.cross(y_ax).normalized()
    # each hand turned a little its own way, so they are not clones
    var q := (Basis(y_ax, float(rig["roll"])) * Basis(x_ax, y_ax, z_ax)).get_rotation_quaternion()
    var prev: Quaternion = rig["rot"]
    var kq := 1.0 if delta <= 0.0 else 1.0 - exp(-10.0 * delta)
    q = prev.slerp(q, kq) if prev != Quaternion.IDENTITY else q
    rig["rot"] = q
    var hand: Node3D = rig["hand"]
    hand.transform = Transform3D(Basis(q) * Basis.from_scale(Vector3(float(rig["mirror"]), 1, 1)), w)

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
