extends Node3D

## Basketball bag for carrying ONE intact tumor (one bag = one tumor). A
## drawstring net sack on a shoulder strap. Empty it hangs limp; with a
## tumor it bulges round and the lump shows through the net.
## Origin = drawstring knot at the top; the bag hangs down (-Y).
## Public: set_tumor(present: bool, kind: int = 0), has_tumor().

const K := preload("res://main/art/fp_art_kit.gd")
const Tumor := preload("res://main/art/fp_tumor.gd")
const R := 0.13
var _net_full: MeshInstance3D
var _net_empty: MeshInstance3D
var _lump: MeshInstance3D
var _has := false

func _ready() -> void:
    var cord := Color(0.12, 0.12, 0.14)
    var cord_hi := Color(0.72, 0.18, 0.12)
    var mat := K.mat("tex_fixture_64.png", 0.1, true)
    # strap + drawstring knot (shared)
    var st := K.begin()
    K.tube(st, Transform3D.IDENTITY, [Vector3(0, 0, 0), Vector3(0.02, 0.12, 0.0), Vector3(0.1, 0.28, -0.02), Vector3(0.18, 0.4, -0.05)], [0.012, 0.011, 0.011, 0.011], 4, [cord_hi], true, 0.4)
    K.blob(st, Transform3D.IDENTITY, Vector3(0, -0.005, 0), Vector3(0.02, 0.016, 0.02), 0.3, 9, cord, cord_hi)
    K.add_mesh(self, "Strap", K.finish(st, 6.0), mat)
    # full: net meridians + rings around a sphere of radius R below the knot
    st = K.begin()
    var c := Vector3(0, -R - 0.02, 0)
    for m in range(10):
        var az := m * TAU / 10.0
        var pts: Array = [Vector3(0, -0.01, 0)]
        for k in range(1, 9):
            var el := PI * 0.5 - PI * k / 8.0
            var rr := R * (1.02 if k < 8 else 0.95)
            pts.append(c + Vector3(cos(az) * cos(el) * rr, sin(el) * rr, sin(az) * cos(el) * rr))
        K.tube(st, Transform3D.IDENTITY, pts, [0.003], 3, [cord if m % 2 == 0 else cord_hi], false)
    for k in range(1, 7):
        var el := PI * 0.5 - PI * k / 7.0
        var ring: Array = []
        for m in range(13):
            var az := m * TAU / 12.0 + (k % 2) * 0.26
            ring.append(c + Vector3(cos(az) * cos(el) * R * 1.03, sin(el) * R * 1.03, sin(az) * cos(el) * R * 1.03))
        K.tube(st, Transform3D.IDENTITY, ring, [0.0028], 3, [cord], false)
    _net_full = K.add_mesh(self, "NetFull", K.finish(st, 8.0), mat)
    # empty: the same net collapsed into a hanging, twisted tube
    st = K.begin()
    var pts2: Array = []
    var radii: Array = []
    for k in range(8):
        var t := float(k) / 7.0
        pts2.append(Vector3(sin(t * 3.0) * 0.015, -0.01 - t * 0.28, cos(t * 2.0) * 0.01))
        radii.append(0.012 + sin(t * PI) * 0.03)
    K.tube(st, Transform3D.IDENTITY, pts2, radii, 7, [cord, cord_hi, cord], true, 0.55)
    _net_empty = K.add_mesh(self, "NetEmpty", K.finish(st, 8.0), mat)
    # the lump inside
    _lump = K.add_mesh(self, "Lump", Tumor.build_mesh(0), K.mat("tex_flesh_128.png", 0.75, true))
    _lump.position = c
    _lump.scale = Vector3.ONE * (R * 0.98 / 0.11)
    set_tumor(false)

func set_tumor(present: bool, kind: int = 0) -> void:
    _has = present
    _net_full.visible = present
    _lump.visible = present
    _net_empty.visible = not present
    if present:
        _lump.mesh = Tumor.build_mesh(clampi(kind, 0, 2))

func has_tumor() -> bool:
    return _has

func capture_setup() -> Dictionary:
    set_tumor(true, 1)
    # capture only: the empty bag hanging beside the full one
    var e := K.add_mesh(self, "CaptureEmpty", _net_empty.mesh, _net_empty.material_override)
    e.position = Vector3(-0.32, 0.0, 0)
    return {"cam_pos": Vector3(-0.1, -0.02, 0.8), "look_at": Vector3(-0.12, -0.12, 0), "env": "dark", "fov": 55.0}