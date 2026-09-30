extends Node3D

## Rest point: a construction-site container office swallowed by the flesh
## (one identical model placed several times per shell). Corrugated steel
## box, faded site-yellow paint, a door with a wired window, a barred side
## window, a dim fluorescent tube inside, a floor drain + bucket (the only
## thing to do here is vomit/settle). Flesh blobs have grown over its
## corners and roof. Origin = floor centre; door on the +Z long side.
## Public: set_door_open(0..1), play_door(), set_light(on), set_flicker(bool),
## drain_point() -> Vector3.

const K := preload("res://main/art/fp_art_kit.gd")
const L := 1.5
const Wd := 1.2
const H := 1.3
var _door: Node3D
var _tube: MeshInstance3D
var _lamp: OmniLight3D
var _flicker := true
var _time := 0.0

func _ready() -> void:
    var steel := K.mat("tex_door_paint_128.png", 0.25, true)
    var st := K.begin()
    var paint := Color(0.78, 0.62, 0.2)
    var rust := Color(0.45, 0.25, 0.12)
    var inside := Color(0.45, 0.43, 0.38)
    # corrugated walls: vertical ribs as alternating in/out facets, both
    # outer (paint) and inner (grey) sides
    _ribbed_wall(st, Vector3(0, 0, -Wd), Vector3(1, 0, 0), L, paint, rust, inside, false)
    _ribbed_wall(st, Vector3(L, 0, 0), Vector3(0, 0, 1), Wd, paint, rust, inside, false)
    _ribbed_wall(st, Vector3(-L, 0, 0), Vector3(0, 0, -1), Wd, paint, rust, inside, false)
    _ribbed_wall(st, Vector3(0, 0, Wd), Vector3(-1, 0, 0), L, paint, rust, inside, true)
    # corner posts, roof and floor frame
    for sx in [-1, 1]:
        for sz in [-1, 1]:
            K.rbox(st, K.T(Vector3(sx * L, H * 0.5, sz * Wd)), Vector3(0.05, H * 0.5 + 0.04, 0.05), 0.012, Color(0.35, 0.33, 0.3))
    K.rbox(st, K.T(Vector3(0, H + 0.03, 0)), Vector3(L + 0.05, 0.03, Wd + 0.05), 0.015, paint.darkened(0.2), rust)
    K.quad(st, Transform3D.IDENTITY, Vector3(-L, H - 0.001, -Wd), Vector3(L, H - 0.001, -Wd), Vector3(L, H - 0.001, Wd), Vector3(-L, H - 0.001, Wd), Vector3.DOWN, inside.darkened(0.3))
    K.rbox(st, K.T(Vector3(0, -0.04, 0)), Vector3(L + 0.05, 0.04, Wd + 0.05), 0.015, Color(0.3, 0.28, 0.26))
    K.quad(st, Transform3D.IDENTITY, Vector3(-L, 0.002, -Wd), Vector3(L, 0.002, -Wd), Vector3(L, 0.002, Wd), Vector3(-L, 0.002, Wd), Vector3.UP, Color(0.36, 0.34, 0.3))
    # barred side window frame on the -X wall
    K.rbox(st, K.T(Vector3(-L - 0.03, 0.85, 0)), Vector3(0.02, 0.2, 0.3), 0.01, Color(0.3, 0.3, 0.32))
    for i in range(5):
        K.tube(st, Transform3D.IDENTITY, [Vector3(-L - 0.06, 0.66, -0.24 + i * 0.12), Vector3(-L - 0.06, 1.04, -0.24 + i * 0.12)], [0.012], 5, [Color(0.25, 0.25, 0.26)])
    # interior: drain, bucket, a folding chair
    K.lathe(st, K.T(Vector3(0.7, 0.003, -0.5)), [Vector2(0.12, 0.0), Vector2(0.1, 0.008), Vector2(0.0, 0.004)], 8, [Color(0.2, 0.2, 0.2)])
    K.lathe(st, K.T(Vector3(0.95, 0.0, -0.75)), [Vector2(0.0, 0.0), Vector2(0.12, 0.0), Vector2(0.15, 0.3), Vector2(0.14, 0.3), Vector2(0.11, 0.02)], 10, [Color(0.25, 0.4, 0.62)])
    K.rbox(st, K.T(Vector3(-0.8, 0.42, -0.6), Vector3(0, 20, 0)), Vector3(0.2, 0.02, 0.2), 0.01, Color(0.4, 0.4, 0.42))
    K.rbox(st, K.T(Vector3(-0.8, 0.7, -0.78), Vector3(-10, 20, 0)), Vector3(0.2, 0.15, 0.015), 0.01, Color(0.4, 0.4, 0.42))
    for sx in [-1, 1]:
        for sz in [-1, 1]:
            K.tube(st, K.T(Vector3(-0.8, 0, -0.6), Vector3(0, 20, 0)), [Vector3(sx * 0.18, 0.0, sz * 0.18), Vector3(sx * 0.17, 0.41, sz * 0.17)], [0.012], 4, [Color(0.3, 0.3, 0.32)])
    K.add_mesh(self, "Shell", K.finish(st, 3.0), steel)
    # flesh overgrowth on corners/roof edges
    st = K.begin()
    var fa := Color(0.55, 0.1, 0.12)
    var fb := Color(0.72, 0.28, 0.25)
    var growth := [Vector3(L, H, Wd), Vector3(L, H, -Wd), Vector3(-L, H, -Wd), Vector3(-L, 0.2, Wd), Vector3(0.3, H + 0.05, -Wd), Vector3(-0.9, H + 0.05, 0.2), Vector3(L, 0.4, -0.6)]
    for i in range(growth.size()):
        var r := 0.25 + K.h(i, 2) * 0.25
        K.blob(st, Transform3D.IDENTITY, growth[i], Vector3(r, r * 0.7, r), 0.4, 90 + i, fa, fb)
    K.add_mesh(self, "Overgrowth", K.finish(st, 3.0), K.mat("tex_flesh_128.png", 0.7, true))
    # door (on the +Z wall, hinge at x=0.1)
    _door = K.pivot(self, "DoorHinge", Vector3(0.62, 0, Wd + 0.02))
    st = K.begin()
    K.rbox(st, K.T(Vector3(-0.23, 0.55, 0)), Vector3(0.23, 0.55, 0.025), 0.012, Color(0.62, 0.64, 0.6), Color(0.45, 0.46, 0.44))
    K.rbox(st, K.T(Vector3(-0.23, 0.85, 0.026)), Vector3(0.12, 0.13, 0.004), 0.004, Color(0.18, 0.22, 0.24))
    for i in range(4):
        K.tube(st, Transform3D.IDENTITY, [Vector3(-0.35, 0.72 + i * 0.087, 0.032), Vector3(-0.11, 0.72 + i * 0.087, 0.032)], [0.003], 3, [Color(0.6, 0.6, 0.6)])
    K.lathe(st, K.T(Vector3(-0.4, 0.55, 0.04), Vector3(90, 0, 0)), [Vector2(0.0, -0.01), Vector2(0.018, -0.01), Vector2(0.015, 0.02), Vector2(0.0, 0.025)], 6, [Color(0.75, 0.75, 0.72)])
    K.add_mesh(_door, "Door", K.finish(st, 4.0), steel)
    # fluorescent tube
    st = K.begin()
    K.tube(st, Transform3D.IDENTITY, [Vector3(-0.5, H - 0.05, 0), Vector3(0.5, H - 0.05, 0)], [0.018], 6, [Color(0.85, 0.95, 0.9)])
    _tube = K.add_mesh(self, "Tube", K.finish(st), K.glow(Color(1, 1, 1)))
    _lamp = OmniLight3D.new()
    _lamp.position = Vector3(0, H - 0.15, 0)
    _lamp.omni_range = 3.0
    _lamp.light_color = Color(0.85, 1.0, 0.9)
    _lamp.light_energy = 0.9
    # no shadows, so without this it shone through the restroom's thin wall
    # (green seam at the mirror wall's corner, 형님 2026-09-30)
    _lamp.light_cull_mask = 0xFFFFF & ~FPRestroom.ROOM_VISUAL_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
    add_child(_lamp)

## One corrugated wall: centred at `c`, running along `dir` (half length
## `half`), facing outward = dir x UP rotated; door side leaves a gap.
func _ribbed_wall(st: SurfaceTool, c: Vector3, dir: Vector3, half: float, col: Color, col2: Color, inner: Color, door_gap: bool) -> void:
    var outward := Vector3.UP.cross(dir).normalized() * -1.0
    var ribs := int(half * 2.0 / 0.12)
    for i in range(ribs):
        var s0 := -half + i * (half * 2.0 / ribs)
        var s1 := s0 + half * 2.0 / ribs
        var sm := (s0 + s1) * 0.5
        if door_gap and sm < -0.16 and sm > -0.64:
            # door opening: only a lintel above
            var a := c + dir * s0 + Vector3(0, 1.12, 0)
            var b := c + dir * s1 + Vector3(0, 1.12, 0)
            K.quad(st, Transform3D.IDENTITY, a, b, b + Vector3(0, H - 1.12, 0), a + Vector3(0, H - 1.12, 0), outward, col)
            K.quad(st, Transform3D.IDENTITY, a, b, b + Vector3(0, H - 1.12, 0), a + Vector3(0, H - 1.12, 0), -outward, inner)
            continue
        var dep := 0.025 if i % 2 == 0 else 0.0
        var dep2 := 0.0 if i % 2 == 0 else 0.025
        var p0 := c + dir * s0 + outward * dep
        var pm := c + dir * sm + outward * (dep + dep2) * 0.5
        var p1 := c + dir * s1 + outward * dep2
        var dirt := col.lerp(col2, clampf(K.h(i, int(c.x * 10), int(c.z * 10)) * 0.9 - 0.2, 0.0, 1.0))
        for seg in [[p0, pm], [pm, p1]]:
            var a: Vector3 = seg[0]
            var b: Vector3 = seg[1]
            var n := (b - a).cross(Vector3.UP).normalized()
            if n.dot(outward) < 0.0:
                n = -n
            K.quad(st, Transform3D.IDENTITY, a, b, b + Vector3(0, H, 0), a + Vector3(0, H, 0), n, dirt)
            K.quad(st, Transform3D.IDENTITY, a, b, b + Vector3(0, H, 0), a + Vector3(0, H, 0), -n, inner)

func set_door_open(t: float) -> void:
    _door.rotation_degrees.y = 95.0 * clampf(t, 0.0, 1.0)

func play_door() -> void:
    create_tween().tween_method(set_door_open, 0.0, 1.0, 0.8).set_trans(Tween.TRANS_SINE)

func set_light(on: bool) -> void:
    _tube.visible = on
    _lamp.visible = on

func set_flicker(on: bool) -> void:
    _flicker = on

func drain_point() -> Vector3:
    return Vector3(0.7, 0.0, -0.5)

func _process(delta: float) -> void:
    _time += delta
    if _flicker and _lamp.visible:
        var f := 1.0 if fmod(_time * 1.7, 5.0) > 0.25 else 0.2 + 0.3 * sin(_time * 90.0)
        _lamp.light_energy = 0.9 * f

func capture_setup() -> Dictionary:
    set_door_open(0.75)
    return {"cam_pos": Vector3(2.2, 1.8, 3.6), "look_at": Vector3(0, 0.6, 0), "env": "dark", "fov": 55.0}