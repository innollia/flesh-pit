extends Node3D

## Ending set: a city street on a bright day (no awnings/flags: kept sober). Asphalt road with lane marks,
## kerbs and pavements, low-poly 5-8 storey blocks with window grids and
## shop awnings, street lamps. The street is EMPTY (no people at all, per
## the owner's call), and the rolling human sphere - larger than the tallest
## building - rolls away down it (instanced from fp_rolling_sphere). No flesh fog: clean daylight PS1.
## Origin = where the player lands (road centre); the street runs along -Z.
## Public: set_roll(t 0..1) (sphere position down the street),
## play_roll_away(seconds=12), sphere() -> Node3D, landing_point().

const K := preload("res://main/art/fp_art_kit.gd")
const Sphere := preload("res://main/art/fp_rolling_sphere.gd")
const LEN := 260.0
## Blocks and lamps beyond this z are rubble: the ball (radius 34 m) is far
## wider than the 20 m street, so standing buildings would hide its sides
## and leave only a vertical strip between them (read as a pillar).
const CRUSH_Z := -18.0
## Where the ball starts: far enough that the intact blocks near the landing
## point never overlap its silhouette from the landing camera.
## Close enough that the 84 m ball visibly towers over the 26 m blocks
## (from -115 m perspective made it read smaller than the near buildings).
const ROLL_START_Z := -62.0
var _sphere: Node3D
var _time := 0.0

func _ready() -> void:
    var st := K.begin()
    var asphalt := Color(0.34, 0.34, 0.36)
    var pave := Color(0.66, 0.64, 0.6)
    var kerb := Color(0.78, 0.77, 0.74)
    K.quad(st, Transform3D.IDENTITY, Vector3(-6, 0, 90), Vector3(6, 0, 90), Vector3(6, 0, -LEN), Vector3(-6, 0, -LEN), Vector3.UP, asphalt)
    for sx in [-1, 1]:
        K.rbox(st, K.T(Vector3(sx * 6.1, 0.08, -LEN * 0.5 + 10)), Vector3(0.12, 0.08, LEN * 0.5 + 10), 0.04, kerb)
        K.quad(st, Transform3D.IDENTITY, Vector3(sx * 6.2, 0.15, 90), Vector3(sx * 10, 0.15, 90), Vector3(sx * 10, 0.15, -LEN), Vector3(sx * 6.2, 0.15, -LEN), Vector3.UP, pave)
    var z := 88.0
    while z > -LEN:
        K.quad(st, Transform3D.IDENTITY, Vector3(-0.08, 0.01, z), Vector3(0.08, 0.01, z), Vector3(0.08, 0.01, z - 3.0), Vector3(-0.08, 0.01, z - 3.0), Vector3.UP, Color(0.95, 0.92, 0.8))
        z -= 7.0
    # zebra crossing near the landing point
    for i in range(8):
        var x := -5.0 + i * 1.4
        K.quad(st, Transform3D.IDENTITY, Vector3(x, 0.012, -6), Vector3(x + 0.7, 0.012, -6), Vector3(x + 0.7, 0.012, -9), Vector3(x, 0.012, -9), Vector3.UP, Color(0.95, 0.95, 0.92))
    K.add_mesh(self, "Street", K.finish(st, 0.5), K.mat("tex_tile_floor_64.png", 0.05, false))
    # buildings
    st = K.begin()
    var facades := [Color(0.82, 0.74, 0.62), Color(0.7, 0.72, 0.74), Color(0.62, 0.44, 0.36), Color(0.88, 0.86, 0.8), Color(0.55, 0.6, 0.66)]
    for sx in [-1, 1]:
        var bz := 60.0
        var i := 0
        while bz > -LEN:
            var w := 9.0 + K.h(i, sx + 5) * 8.0
            var floors := 5 + int(K.h(i, sx + 9) * 4.0)
            var hgt := floors * 3.2
            var depth := 10.0
            var col: Color = facades[(i + (1 if sx > 0 else 3)) % 5]
            var cx: float = sx * (10.0 + depth * 0.5)
            if bz - w * 0.5 < CRUSH_Z:
                # the sphere already rolled over this block: a flattened
                # slab of rubble low enough that it never hides the ball
                K.rbox(st, K.T(Vector3(cx, 0.45, bz - w * 0.5), Vector3(0, 0, sx * 2.0)), Vector3(depth * 0.5, 0.45, w * 0.5 - 0.2), 0.2, col.darkened(0.1), col.darkened(0.3))
                for k in range(3):
                    K.rbox(st, K.T(Vector3(cx + (K.h(i, k, 3) - 0.5) * 6.0, 1.0, bz - w * (0.25 + 0.25 * k)), Vector3(0, K.h(i, k) * 90.0, 8.0)), Vector3(1.2, 0.35, 0.9), 0.1, col.darkened(0.2))
                bz -= w
                i += 1
                continue
            K.rbox(st, K.T(Vector3(cx, hgt * 0.5, bz - w * 0.5)), Vector3(depth * 0.5, hgt * 0.5, w * 0.5 - 0.2), 0.25, col, col.darkened(0.15))
            # cornice
            K.rbox(st, K.T(Vector3(cx, hgt + 0.2, bz - w * 0.5)), Vector3(depth * 0.5 + 0.3, 0.2, w * 0.5 - 0.05), 0.08, col.lightened(0.2))
            # window grid on the street face
            var fx: float = sx * 10.0 - sx * 0.02
            var cols := int(w / 2.2)
            for f in range(1, floors):
                for c in range(cols):
                    var wz := bz - 0.9 - c * (w - 1.2) / maxf(cols, 1)
                    var wy := f * 3.2 + 0.9
                    var glass := Color(0.35, 0.45, 0.55).lerp(Color(0.8, 0.88, 0.95), K.h(i, f, c))
                    K.quad(st, Transform3D.IDENTITY, Vector3(fx, wy, wz), Vector3(fx, wy, wz - 1.1), Vector3(fx, wy + 1.5, wz - 1.1), Vector3(fx, wy + 1.5, wz), Vector3(-sx, 0, 0), glass)
            # ground floor shop window + awning
            K.quad(st, Transform3D.IDENTITY, Vector3(fx, 0.5, bz - 1.0), Vector3(fx, 0.5, bz - w + 1.4), Vector3(fx, 2.6, bz - w + 1.4), Vector3(fx, 2.6, bz - 1.0), Vector3(-sx, 0, 0), Color(0.3, 0.38, 0.45))
            bz -= w
            i += 1
    K.add_mesh(self, "Buildings", K.finish(st, 0.4), K.mat("tex_tile_wall_64.png", 0.05, false))
    # street lamps + a tree every so often
    st = K.begin()
    for k in range(12):
        var lz := 10.0 - k * 22.0
        if lz < CRUSH_Z:
            break  # lamps and trees on the sphere's path were flattened with the blocks
        for sx in [-1, 1]:
            K.tube(st, Transform3D.IDENTITY, [Vector3(sx * 6.6, 0.15, lz), Vector3(sx * 6.6, 5.5, lz), Vector3(sx * 5.8, 6.0, lz)], [0.09, 0.07, 0.06], 6, [Color(0.3, 0.33, 0.32)])
            K.lathe(st, K.T(Vector3(sx * 5.6, 5.9, lz)), [Vector2(0.0, -0.1), Vector2(0.3, -0.05), Vector2(0.2, 0.1), Vector2(0.0, 0.12)], 6, [Color(0.25, 0.28, 0.27)])
            if k % 2 == 1:
                var tz := lz - 11.0
                K.tube(st, Transform3D.IDENTITY, [Vector3(sx * 8.2, 0.15, tz), Vector3(sx * 8.2, 2.6, tz)], [0.18, 0.13], 5, [Color(0.38, 0.28, 0.2)])
                K.blob(st, Transform3D.IDENTITY, Vector3(sx * 8.2, 3.8, tz), Vector3(1.6, 1.5, 1.6), 0.3, k * 3 + sx, Color(0.32, 0.55, 0.22), Color(0.45, 0.66, 0.28))
    K.add_mesh(self, "Props", K.finish(st, 1.0), K.mat("tex_fixture_64.png", 0.1, false))
    _sphere = Sphere.new()
    _sphere.name = "RollingSphere"
    add_child(_sphere)
    set_roll(0.35)

func set_roll(t: float) -> void:
    var tt := clampf(t, 0.0, 1.0)
    var z := lerpf(ROLL_START_Z, -LEN + 40.0, tt)
    _sphere.position = Vector3(0, _sphere.get("radius"), z)
    _sphere.call("set_roll", -z / float(_sphere.get("radius")))
    _sphere.rotation.y = PI * 0.5

func play_roll_away(seconds: float = 12.0) -> void:
    create_tween().tween_method(set_roll, 0.0, 1.0, seconds)

func sphere() -> Node3D:
    return _sphere

func landing_point() -> Vector3:
    return Vector3(0, 0, 0)

func capture_setup() -> Dictionary:
    set_roll(0.0)
    return {"cam_pos": Vector3(3.0, 40.0, 95.0), "look_at": Vector3(0, 26.0, -50.0), "env": "day", "fov": 60.0}