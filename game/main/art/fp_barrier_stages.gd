extends Node3D

## Industrial tension barrier that auto-expands across a tunnel cross-section
## (docs/spec/06-tools.md). Four telescoping struts in a star from a central hub to
## foot pads pressed into the flesh, with a yellow/black hazard web between.
## Four visual damage states (stress 0-33-66-99%) then a break:
##   0 taut and straight   1 struts bowed, web sagging
##   2 one strut kinked, pads sinking, cracks   3 strut snapped, web torn
## Origin = hub centre; the barrier plane is XY, facing +Z.
## Public: set_stage(0..3), stage(), play_break(), play_deploy(),
## set_expand(0..1).

const K := preload("res://main/art/fp_art_kit.gd")
const REACH := 0.85
var _stage := 0
var _expand := 1.0
var _broken := false
var _root: Node3D
var _time := 0.0

func _ready() -> void:
    _root = K.pivot(self, "Built")
    _rebuild()

func _rebuild() -> void:
    for c in _root.get_children():
        c.queue_free()
    var st := K.begin()
    var yellow := Color(0.92, 0.72, 0.1)
    var black := Color(0.1, 0.1, 0.1)
    var steel := Color(0.6, 0.62, 0.64)
    var dirty := Color(0.5, 0.35, 0.2)
    var bow: float = [0.0, 0.07, 0.12, 0.16][_stage]
    var angles := [45.0, 135.0, 225.0, 315.0]
    var tips: Array = []
    for i in range(4):
        var a: float = deg_to_rad(angles[i])
        var d := Vector3(cos(a), sin(a), 0)
        var perp := Vector3(-d.y, d.x, 0)
        var reach := REACH * lerpf(0.35, 1.0, _expand)
        var snapped := _stage == 3 and i == 1
        var kink := _stage >= 2 and i == 1
        var pts: Array = []
        var n := 6
        for k in range(n + 1):
            var t := float(k) / n
            var off: Vector3 = perp * sin(t * PI) * bow * reach * (1.0 if i % 2 == 0 else -1.0)
            if kink and t > 0.5:
                off += perp * (t - 0.5) * 0.35 * reach
            pts.append(d * reach * t + off + Vector3(0, 0, -sin(t * PI) * bow * 0.3))
        if snapped:
            var p1: Array = pts.slice(0, 4)
            var p2: Array = pts.slice(4, 7)
            K.tube(st, Transform3D.IDENTITY, p1, [0.035, 0.03, 0.026, 0.024], 6, [steel, yellow])
            p2[0] = (p2[0] as Vector3) + Vector3(0.06, -0.08, 0.1)
            K.tube(st, Transform3D.IDENTITY, p2, [0.022, 0.024, 0.026], 6, [yellow, steel])
            # jagged broken ends
            K.lathe(st, Transform3D(Basis(Quaternion(Vector3.UP, ((p1[3] as Vector3) - (p1[2] as Vector3)).normalized())), p1[3]), [Vector2(0.024, 0.0), Vector2(0.012, 0.03), Vector2(0.0, 0.015)], 5, [Color(0.85, 0.85, 0.8)])
        else:
            K.tube(st, Transform3D.IDENTITY, pts, [0.035, 0.032, 0.028, 0.026, 0.026, 0.024, 0.024], 6, [steel, steel, yellow, black, yellow, black])
        # telescoping collar + foot pad
        var tip: Vector3 = pts[n]
        tips.append(tip)
        K.lathe(st, Transform3D(Basis(Quaternion(Vector3.UP, d)), d * reach * 0.5), [Vector2(0.0, -0.04), Vector2(0.042, -0.04), Vector2(0.044, 0.04), Vector2(0.0, 0.04)], 6, [black])
        var sink: float = [0.0, 0.0, 0.05, 0.09][_stage]
        K.lathe(st, Transform3D(Basis(Quaternion(Vector3.DOWN, d)), tip + d * sink), [Vector2(0.0, -0.02), Vector2(0.11, -0.02), Vector2(0.1, 0.02), Vector2(0.04, 0.05), Vector2(0.0, 0.05)], 8, [dirty, steel, steel])
    # hub
    K.lathe(st, K.T(Vector3.ZERO, Vector3(90, 0, 0)), [Vector2(0.0, -0.06), Vector2(0.08, -0.06), Vector2(0.09, 0.0), Vector2(0.08, 0.06), Vector2(0.0, 0.07)], 8, [yellow, black, yellow])
    # stress gauge on the hub face: needle angle shows the stage
    K.rbox(st, K.T(Vector3(0, 0.0, 0.075), Vector3(0, 0, -60 + _stage * 40)), Vector3(0.005, 0.045, 0.004), 0.002, Color(0.9, 0.1, 0.05))
    K.add_mesh(_root, "Frame", K.finish(st, 5.0), K.mat("tex_chrome_128.png", 0.3, true))
    # hazard web between adjacent struts (triangles), torn at stage 3
    st = K.begin()
    var sag: float = [0.0, 0.06, 0.12, 0.2][_stage]
    for i in range(4):
        if _stage == 3 and (i == 0 or i == 1):
            continue
        var a: Vector3 = tips[i] * 0.72
        var b: Vector3 = tips[(i + 1) % 4] * 0.72
        var mid: Vector3 = (a + b) * 0.5 * (1.0 - sag) + Vector3(0, 0, -sag * 0.3)
        var stripes := 5
        for k in range(stripes):
            var t0 := float(k) / stripes
            var t1 := float(k + 1) / stripes
            var e0: Vector3 = a.lerp(mid, t0 * 2.0) if t0 < 0.5 else mid.lerp(b, t0 * 2.0 - 1.0)
            var e1: Vector3 = a.lerp(mid, t1 * 2.0) if t1 < 0.5 else mid.lerp(b, t1 * 2.0 - 1.0)
            var col := yellow if k % 2 == 0 else black
            if _stage >= 2 and k == 2:
                col = col.darkened(0.5)
            K.tri(st, Transform3D.IDENTITY, Vector3.ZERO, e0, e1, Vector3(0, 0, 1), col)
            K.tri(st, Transform3D.IDENTITY, Vector3.ZERO, e0, e1, Vector3(0, 0, -1), col)
    if _stage == 3:
        # torn flaps hanging from the broken side
        for k in range(3):
            var base := Vector3(-0.1 - k * 0.1, 0.12 + k * 0.08, 0.0)
            K.tri(st, Transform3D.IDENTITY, base, base + Vector3(0.08, 0.02, 0), base + Vector3(0.03, -0.18 - k * 0.04, 0.05), Vector3(0, 0, 1), yellow if k % 2 == 0 else black)
            K.tri(st, Transform3D.IDENTITY, base, base + Vector3(0.08, 0.02, 0), base + Vector3(0.03, -0.18 - k * 0.04, 0.05), Vector3(0, 0, -1), yellow if k % 2 == 0 else black)
    K.add_mesh(_root, "Web", K.finish(st, 4.0), K.mat("tex_fixture_64.png", 0.1, true))

func set_stage(s: int) -> void:
    _stage = clampi(s, 0, 3)
    _broken = false
    _root.visible = true
    _root.transform = Transform3D.IDENTITY
    _rebuild()

func stage() -> int:
    return _stage

func set_expand(t: float) -> void:
    _expand = clampf(t, 0.0, 1.0)
    _rebuild()

func play_deploy() -> void:
    create_tween().tween_method(set_expand, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The elastic "boing": overshoot-collapse toward the hub, then gone.
func play_break() -> void:
    _broken = true
    var tw := create_tween()
    tw.tween_property(_root, "scale", Vector3(1.15, 1.15, 1.0), 0.06)
    tw.tween_property(_root, "scale", Vector3(0.25, 0.25, 0.6), 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
    tw.tween_callback(func(): _root.visible = false)

func _process(delta: float) -> void:
    _time += delta
    if not _broken and _stage > 0:
        # strain tremble grows with damage
        _root.position = Vector3(sin(_time * 53.0), cos(_time * 47.0), 0) * 0.0015 * _stage

func capture_setup() -> Dictionary:
    # capture only: all four states in a row, 0 at left
    set_stage(0)
    for s in [1, 2, 3]:
        var b := (load("res://main/art/fp_barrier_stages.gd") as GDScript).new() as Node3D
        add_child(b)
        b.position = Vector3((s % 2) * 1.9, -(s / 2) * 1.9, 0)
        b.call("set_stage", s)
    return {"cam_pos": Vector3(0.95, -0.7, 3.3), "look_at": Vector3(0.95, -0.95, 0), "env": "lit", "fov": 70.0}