extends Node3D

## Ending set, seen ONLY from above (owner 2026-11: the ending is a bird's-eye
## view of the meat ball, the ball larger than the buildings; a street-level
## boulevard with buildings on both sides must never be on screen). A city
## grid on a bright day: streets every PITCH m with lane marks and zebra
## crossings, blocks of 4-10 storey buildings (roofs, parapets, rooftop
## boxes, window bands), a few parks. The streets are EMPTY (no people, per
## the owner's call). The rolling human sphere (radius 42 m, ~84 m across;
## tallest building 32 m, footprints ~15 m) rolls along -Z down the central
## avenue and flattens every building in its 84 m wide path: a rubble swath
## behind it, the blocks ahead still standing until it reaches them.
## Origin = where the ball starts (avenue centre, ground level).
## Public: set_roll(t 0..1) (sphere position along its path),
## play_roll_away(seconds=12), sphere() -> Node3D, landing_point(),
## build_over_frames (set before adding), is_built(), finish_build().

const K := preload("res://main/art/fp_art_kit.gd")
const Sphere := preload("res://main/art/fp_rolling_sphere.gd")
## Street-to-street spacing and street width (blocks are PITCH - ROAD).
const PITCH := 48.0
const ROAD := 12.0
const FLOOR_H := 3.2
## Block index ranges: x in [-GRID_X, GRID_X), z in [-GRID_Z_FAR, GRID_Z_NEAR).
const GRID_X := 9
const GRID_Z_NEAR := 6
const GRID_Z_FAR := 13
## Ball path along the central avenue (x = 0).
const ROLL_START_Z := 0.0
const ROLL_END_Z := -240.0
## Buildings whose footprint reaches inside |x| < this lie in the ball's path.
const PATH_HALF_W := 40.0
const FACADES := [Color(0.82, 0.74, 0.62), Color(0.7, 0.72, 0.74), Color(0.62, 0.44, 0.36), Color(0.88, 0.86, 0.8), Color(0.55, 0.6, 0.66), Color(0.76, 0.66, 0.58)]
const ROOFS := [Color(0.42, 0.42, 0.44), Color(0.55, 0.53, 0.5), Color(0.36, 0.34, 0.33), Color(0.62, 0.6, 0.58)]

var _sphere: Node3D
## Path buildings: [{"z": centre z, "up": standing node, "down": rubble node}]
var _path: Array = []
## Set before adding to the tree to build the city one grid column per
## frame (the ending does this so the ~0.4 s of geometry is spread over the
## white flash instead of freezing its first frame). finish_build() completes
## whatever is left at once. (A WorkerThreadPool task was tried: GDScript ran
## 5-10x slower there and finished after the reveal.)
var build_over_frames := false
## Next build step (-GRID_X - 1 = ground, then grid columns, GRID_X =
## attach; see _build_step); > GRID_X once the city is in the tree.
var _next_gx := GRID_X + 1
var _built: Array = []
var _path_wip: Array = []
var _bi := 0
var _city_mat: Material
var _street_mat: Material
var _roll_t := 0.35

## Flat-shaded triangle soup written straight into packed arrays: the city
## is ~100k quads, too many for SurfaceTool's per-vertex calls (that took
## over a second). Same winding rule and planar UVs as FDKLowPoly.
class Geo:
    var v := PackedVector3Array()
    var n := PackedVector3Array()
    var c := PackedColorArray()

    func tri(a: Vector3, b: Vector3, d: Vector3, outward: Vector3, col: Color) -> void:
        var nn := (b - a).cross(d - a)
        if nn.length_squared() < 1e-14:
            return
        if nn.dot(outward) > 0.0:
            var tmp := b
            b = d
            d = tmp
            nn = -nn
        var normal := -nn.normalized()
        v.append(a)
        v.append(b)
        v.append(d)
        n.append(normal)
        n.append(normal)
        n.append(normal)
        c.append(col)
        c.append(col)
        c.append(col)

    func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, outward: Vector3, col: Color) -> void:
        tri(a, b, cc, outward, col)
        tri(a, cc, d, outward, col)

    ## Box through transform `t` (half extents `h`), top face in `top`.
    ## `bottom` = also the underside (only rubble chunks tumble enough).
    func box(t: Transform3D, h: Vector3, col: Color, top: Color, bottom: bool = false) -> void:
        var p := [
            t * Vector3(-h.x, -h.y, -h.z), t * Vector3(h.x, -h.y, -h.z), t * Vector3(h.x, -h.y, h.z), t * Vector3(-h.x, -h.y, h.z),
            t * Vector3(-h.x, h.y, -h.z), t * Vector3(h.x, h.y, -h.z), t * Vector3(h.x, h.y, h.z), t * Vector3(-h.x, h.y, h.z)]
        var b := t.basis
        quad(p[4], p[5], p[6], p[7], b.y, top)
        quad(p[3], p[2], p[6], p[7], b.z, col)
        quad(p[1], p[0], p[4], p[5], -b.z, col.darkened(0.1))
        quad(p[2], p[1], p[5], p[6], b.x, col.darkened(0.05))
        quad(p[0], p[3], p[7], p[4], -b.x, col.darkened(0.15))
        if bottom:
            quad(p[0], p[1], p[2], p[3], -b.y, col.darkened(0.2))

    func blob(center: Vector3, radius: Vector3, seed: int, ca: Color, cb: Color) -> void:
        var tmp := SurfaceTool.new()
        tmp.begin(Mesh.PRIMITIVE_TRIANGLES)
        FDKLowPoly.add_blob(tmp, center, radius, 0.3, seed, ca, cb)
        var arr := tmp.commit().surface_get_arrays(0)
        var bv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
        var bc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
        var i := 0
        while i + 2 < bv.size():
            tri(bv[i], bv[i + 1], bv[i + 2], (bv[i] + bv[i + 1] + bv[i + 2]) / 3.0 - center, bc[i])
            i += 3

    func mesh(uv_scale: float) -> ArrayMesh:
        var uv := PackedVector2Array()
        uv.resize(v.size())
        for i in range(v.size()):
            var nm := n[i]
            var p := v[i]
            var ax := absf(nm.x)
            var ay := absf(nm.y)
            var az := absf(nm.z)
            if ax >= ay and ax >= az:
                uv[i] = Vector2(p.z, p.y) * uv_scale
            elif ay >= az:
                uv[i] = Vector2(p.x, p.z) * uv_scale
            else:
                uv[i] = Vector2(p.x, p.y) * uv_scale
        var arrays := []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = v
        arrays[Mesh.ARRAY_NORMAL] = n
        arrays[Mesh.ARRAY_COLOR] = c
        arrays[Mesh.ARRAY_TEX_UV] = uv
        var m := ArrayMesh.new()
        m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        return m

func _ready() -> void:
    # materials come from a shared cache: resolve them on the main thread
    _city_mat = K.mat("tex_tile_wall_64.png", 0.05, false)
    _street_mat = K.mat("tex_tile_floor_64.png", 0.05, false)
    _sphere = Sphere.new()
    _sphere.name = "RollingSphere"
    add_child(_sphere)
    _begin_build()
    if not build_over_frames:
        finish_build()
    set_roll(_roll_t)

func _process(_delta: float) -> void:
    if _next_gx <= GRID_X:
        _build_step()

## True once every city mesh is in the tree.
func is_built() -> bool:
    return _next_gx > GRID_X

## Builds whatever is left of the city now.
func finish_build() -> void:
    while _next_gx <= GRID_X:
        _build_step()

func _begin_build() -> void:
    _built = []
    _path_wip = []
    _bi = 0
    _next_gx = -GRID_X - 1

## Steps: the ground, then one grid column of blocks (its own mesh) per
## step; the step after the last column attaches the whole city at once.
func _build_step() -> void:
    if _next_gx < -GRID_X:
        _built.append(_named_mesh("Street", _build_ground().mesh(0.5), _street_mat))
        _next_gx += 1
        return
    if _next_gx < GRID_X:
        var g := Geo.new()
        for gz in range(-GRID_Z_FAR, GRID_Z_NEAR):
            _bi = _build_block(g, _next_gx, gz, _bi, _built, _path_wip)
        _built.append(_named_mesh("Buildings%d" % (_next_gx + GRID_X), g.mesh(0.4), _city_mat))
        _next_gx += 1
        return
    for node in _built:
        add_child(node)
    _built = []
    _path = _path_wip
    _next_gx = GRID_X + 1
    set_roll(_roll_t)

func _named_mesh(node_name: String, mesh: Mesh, m: Material) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.name = node_name
    mi.mesh = mesh
    mi.material_override = m
    return mi

func _build_ground() -> Geo:
    var g := Geo.new()
    var asphalt := Color(0.36, 0.36, 0.38)
    var x0 := -GRID_X * PITCH - 40.0
    var x1 := GRID_X * PITCH + 40.0
    var z0 := GRID_Z_NEAR * PITCH + 40.0
    var z1 := -GRID_Z_FAR * PITCH - 40.0
    # tiled, not one huge quad: the PS1 material's affine texturing smears
    # a single 1000 m triangle into shifting colour bands from above
    _tiles(g, x0, x1, z1, z0, 0.0, PITCH * 0.5, asphalt)
    # outskirts beyond the grid, lost in the haze
    var o := 2400.0
    _tiles(g, -o, o, -o, o, -0.3, 200.0, Color(0.5, 0.52, 0.46))
    var mark := Color(0.95, 0.92, 0.8)
    var zebra := Color(0.94, 0.94, 0.9)
    # dashed centre lines on both street directions (wide enough to read from 200 m)
    for k in range(-GRID_X, GRID_X + 1):
        var x := k * PITCH
        var z := z0
        while z > z1:
            g.quad(Vector3(x - 0.3, 0.02, z), Vector3(x + 0.3, 0.02, z), Vector3(x + 0.3, 0.02, z - 4.0), Vector3(x - 0.3, 0.02, z - 4.0), Vector3.UP, mark)
            z -= 9.0
    for k in range(-GRID_Z_FAR, GRID_Z_NEAR + 1):
        var z := k * PITCH
        var x := x0
        while x < x1:
            g.quad(Vector3(x, 0.02, z - 0.3), Vector3(x + 4.0, 0.02, z - 0.3), Vector3(x + 4.0, 0.02, z + 0.3), Vector3(x, 0.02, z + 0.3), Vector3.UP, mark)
            x += 9.0
    # zebra crossings on the four arms of every intersection
    var half := ROAD * 0.5
    var arm := half + 2.0
    for gx in range(-GRID_X, GRID_X + 1):
        for gz in range(-GRID_Z_FAR, GRID_Z_NEAR + 1):
            var cx := gx * PITCH
            var cz := gz * PITCH
            for i in range(5):
                var u := -half + 0.8 + i * 2.3
                for s in [-1.0, 1.0]:
                    var zc: float = cz + s * arm
                    g.quad(Vector3(cx + u, 0.03, zc - 1.3), Vector3(cx + u + 1.2, 0.03, zc - 1.3), Vector3(cx + u + 1.2, 0.03, zc + 1.3), Vector3(cx + u, 0.03, zc + 1.3), Vector3.UP, zebra)
                    var xc: float = cx + s * arm
                    g.quad(Vector3(xc - 1.3, 0.03, cz + u), Vector3(xc + 1.3, 0.03, cz + u), Vector3(xc + 1.3, 0.03, cz + u + 1.2), Vector3(xc - 1.3, 0.03, cz + u + 1.2), Vector3.UP, zebra)
    return g

func _tiles(g: Geo, x0: float, x1: float, z0: float, z1: float, y: float, step: float, col: Color) -> void:
    var x := x0
    while x < x1:
        var xe := minf(x + step, x1)
        var z := z0
        while z < z1:
            var ze := minf(z + step, z1)
            g.quad(Vector3(x, y, ze), Vector3(xe, y, ze), Vector3(xe, y, z), Vector3(x, y, z), Vector3.UP, col)
            z = ze
        x = xe

## One city block (pavement pad + 4 buildings, or a park). Buildings in the
## ball's path get their own standing and rubble meshes so set_roll can
## flatten them as the ball passes; the rest go into the shared Geo `g`.
func _build_block(g: Geo, gx: int, gz: int, bi: int, out: Array, path: Array) -> int:
    var cx := (gx + 0.5) * PITCH
    var cz := (gz + 0.5) * PITCH
    var bh := (PITCH - ROAD) * 0.5
    var pave := Color(0.68, 0.66, 0.62)
    g.box(Transform3D(Basis.IDENTITY, Vector3(cx, 0.1, cz)), Vector3(bh, 0.1, bh), Color(0.8, 0.79, 0.76), pave)
    var in_path := absf(cx) - bh < PATH_HALF_W
    if K.h(gx, gz, 3) < 0.09 and not in_path:
        _park(g, cx, cz, bh, gx, gz)
        return bi
    for qx in [-1, 1]:
        for qz in [-1, 1]:
            var pc := Vector3(cx + qx * bh * 0.5, 0.2, cz + qz * bh * 0.5)
            var hw := bh * 0.5 - 1.2 - K.h(bi, 4) * 1.2
            var hd := bh * 0.5 - 1.2 - K.h(bi, 5) * 1.2
            var floors := 4 + int(K.h(bi, 9) * 7.0)
            if in_path:
                var gb := Geo.new()
                _building(gb, Vector3.ZERO, hw, hd, floors, bi)
                var up := _named_mesh("PathBuilding%d" % bi, gb.mesh(0.4), _city_mat)
                up.position = pc
                var gr := Geo.new()
                _rubble(gr, hw, hd, bi)
                var down := _named_mesh("PathRubble%d" % bi, gr.mesh(0.4), _city_mat)
                down.position = pc
                down.visible = false
                out.append(up)
                out.append(down)
                path.append({"z": pc.z, "up": up, "down": down})
            else:
                _building(g, pc, hw, hd, floors, bi)
            bi += 1
    return bi

## Box building with base at `p`: walls in a facade colour with a dark window
## band per floor, a roof in a roof colour inside a parapet, and a rooftop
## stair/plant box (what reads from above). The -Z faces (wall windows,
## parapet) are left plain: the ending camera always looks from +Z.
func _building(g: Geo, p: Vector3, hw: float, hd: float, floors: int, bi: int) -> void:
    var hgt := floors * FLOOR_H
    var col: Color = FACADES[bi % FACADES.size()]
    var roof: Color = ROOFS[int(K.h(bi, 11) * ROOFS.size()) % ROOFS.size()]
    var rim := col.lightened(0.15)
    var x0 := p.x - hw
    var x1 := p.x + hw
    var z0 := p.z - hd
    var z1 := p.z + hd
    var y0 := p.y
    var y1 := p.y + hgt
    var yr := y1 + 0.7  # parapet top
    g.quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, yr, z1), Vector3(x0, yr, z1), Vector3(0, 0, 1), col)
    g.quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, yr, z0), Vector3(x1, yr, z0), Vector3(0, 0, -1), col.darkened(0.1))
    g.quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, yr, z0), Vector3(x1, yr, z1), Vector3(1, 0, 0), col.darkened(0.05))
    g.quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, yr, z1), Vector3(x0, yr, z0), Vector3(-1, 0, 0), col.darkened(0.15))
    # parapet: rim on top of the walls, its inner faces, the roof sunk inside
    var w := 0.5
    var ix0 := x0 + w
    var ix1 := x1 - w
    var iz0 := z0 + w
    var iz1 := z1 - w
    g.quad(Vector3(x0, yr, z1), Vector3(x1, yr, z1), Vector3(ix1, yr, iz1), Vector3(ix0, yr, iz1), Vector3.UP, rim)
    g.quad(Vector3(x1, yr, z1), Vector3(x1, yr, z0), Vector3(ix1, yr, iz0), Vector3(ix1, yr, iz1), Vector3.UP, rim)
    g.quad(Vector3(x1, yr, z0), Vector3(x0, yr, z0), Vector3(ix0, yr, iz0), Vector3(ix1, yr, iz0), Vector3.UP, rim)
    g.quad(Vector3(x0, yr, z0), Vector3(x0, yr, z1), Vector3(ix0, yr, iz1), Vector3(ix0, yr, iz0), Vector3.UP, rim)
    g.quad(Vector3(ix0, y1, iz0), Vector3(ix1, y1, iz0), Vector3(ix1, yr, iz0), Vector3(ix0, yr, iz0), Vector3(0, 0, 1), rim.darkened(0.2))
    g.quad(Vector3(ix1, y1, iz1), Vector3(ix1, y1, iz0), Vector3(ix1, yr, iz0), Vector3(ix1, yr, iz1), Vector3(-1, 0, 0), rim.darkened(0.25))
    g.quad(Vector3(ix0, y1, iz0), Vector3(ix0, y1, iz1), Vector3(ix0, yr, iz1), Vector3(ix0, yr, iz0), Vector3(1, 0, 0), rim.darkened(0.15))
    g.quad(Vector3(ix0, y1, iz1), Vector3(ix1, y1, iz1), Vector3(ix1, y1, iz0), Vector3(ix0, y1, iz0), Vector3.UP, roof)
    # window bands, a hair off the wall
    var e := 0.04
    var glass := Color(0.32, 0.42, 0.52).lerp(Color(0.62, 0.72, 0.82), K.h(bi, 13))
    for f in range(1, floors):
        var wy0 := y0 + f * FLOOR_H + 0.9
        var wy1 := wy0 + 1.4
        g.quad(Vector3(x0 + 0.8, wy0, z1 + e), Vector3(x1 - 0.8, wy0, z1 + e), Vector3(x1 - 0.8, wy1, z1 + e), Vector3(x0 + 0.8, wy1, z1 + e), Vector3(0, 0, 1), glass)
        g.quad(Vector3(x1 + e, wy0, z1 - 0.8), Vector3(x1 + e, wy0, z0 + 0.8), Vector3(x1 + e, wy1, z0 + 0.8), Vector3(x1 + e, wy1, z1 - 0.8), Vector3(1, 0, 0), glass)
        g.quad(Vector3(x0 - e, wy0, z0 + 0.8), Vector3(x0 - e, wy0, z1 - 0.8), Vector3(x0 - e, wy1, z1 - 0.8), Vector3(x0 - e, wy1, z0 + 0.8), Vector3(-1, 0, 0), glass.darkened(0.15))
    # rooftop stair house and a plant box
    var ox := (K.h(bi, 15) - 0.5) * (hw - 2.5)
    var oz := (K.h(bi, 16) - 0.5) * (hd - 3.0)
    g.box(Transform3D(Basis.IDENTITY, Vector3(p.x + ox, y1 + 1.4, p.z + oz)), Vector3(1.8, 1.4, 2.4), Color(0.72, 0.72, 0.7), Color(0.8, 0.8, 0.78))
    if K.h(bi, 17) > 0.5:
        g.box(Transform3D(Basis.IDENTITY, Vector3(p.x - ox * 0.6, y1 + 0.7, p.z - oz * 0.8)), Vector3(1.2, 0.7, 1.2), Color(0.58, 0.6, 0.62), Color(0.66, 0.68, 0.7))

## What a building looks like after the ball has rolled over it: a broken
## concrete slab spilling past its plot and a heap of chunks in grey concrete
## and its own facade colour, no higher than ~2.5 m (reads as wreckage from
## above, not as a tidy plaza).
func _rubble(g: Geo, hw: float, hd: float, bi: int) -> void:
    var col: Color = FACADES[bi % FACADES.size()]
    var concrete := Color(0.5, 0.49, 0.47)
    var slab_rot := Vector3((K.h(bi, 20) - 0.5) * 6.0, (K.h(bi, 19) - 0.5) * 30.0, (K.h(bi, 21) - 0.5) * 6.0)
    g.box(K.T(Vector3(0, 0.3, 0), slab_rot), Vector3(hw + 1.5, 0.3, hd + 1.5), concrete.darkened(0.35), concrete.darkened(0.15))
    for k in range(10):
        var px := (K.h(bi, k, 22) - 0.5) * hw * 2.2
        var pz := (K.h(bi, k, 23) - 0.5) * hd * 2.2
        var sz := Vector3(0.8 + K.h(bi, k, 26) * 2.6, 0.3 + K.h(bi, k, 27) * 0.9, 0.6 + K.h(bi, k, 28) * 2.0)
        var c: Color = col.darkened(0.1 + 0.15 * (k % 3)) if k % 2 == 0 else concrete.darkened(0.05 * (k % 4))
        var rot := Vector3(K.h(bi, k, 24) * 40.0 - 20.0, K.h(bi, k, 25) * 180.0, K.h(bi, k, 29) * 40.0 - 20.0)
        g.box(K.T(Vector3(px, 0.6 + sz.y * 0.6, pz), rot), sz, c, c.lightened(0.08), true)

func _park(g: Geo, cx: float, cz: float, bh: float, gx: int, gz: int) -> void:
    var r := bh - 1.0
    g.quad(Vector3(cx - r, 0.45, cz + r), Vector3(cx + r, 0.45, cz + r), Vector3(cx + r, 0.45, cz - r), Vector3(cx - r, 0.45, cz - r), Vector3.UP, Color(0.36, 0.56, 0.26))
    for t in range(9):
        var tx := cx + (K.h(gx, gz, t) - 0.5) * (bh * 2.0 - 8.0)
        var tz := cz + (K.h(gz, gx, t + 30) - 0.5) * (bh * 2.0 - 8.0)
        g.blob(Vector3(tx, 3.6, tz), Vector3(2.6, 2.0, 2.6), gx * 31 + gz * 7 + t, Color(0.3, 0.52, 0.22), Color(0.42, 0.64, 0.28))

func set_roll(t: float) -> void:
    var tt := clampf(t, 0.0, 1.0)
    _roll_t = tt
    var z := lerpf(ROLL_START_Z, ROLL_END_Z, tt)
    var r := float(_sphere.get("radius"))
    _sphere.position = Vector3(0, r, z)
    _sphere.call("set_roll", -z / r)
    _sphere.rotation.y = PI * 0.5
    # flattened once the ball covers its centre (the ball came from +Z, so
    # everything behind its start is already rubble)
    for b in _path:
        var down: bool = float(b["z"]) > z - r * 0.55
        (b["up"] as Node3D).visible = not down
        (b["down"] as Node3D).visible = down

func play_roll_away(seconds: float = 12.0) -> void:
    create_tween().tween_method(set_roll, 0.0, 1.0, seconds)

func sphere() -> Node3D:
    return _sphere

func landing_point() -> Vector3:
    return Vector3(0, 0, 0)

func capture_setup() -> Dictionary:
    set_roll(0.0)
    return {"cam_pos": Vector3(80.0, 170.0, 90.0), "look_at": Vector3(0, 20.0, -20.0), "env": "day", "fov": 60.0}
