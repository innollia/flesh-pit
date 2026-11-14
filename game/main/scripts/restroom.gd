class_name FPRestroom
extends Node3D
const FPProfile := preload("res://main/scripts/fp_profile.gd")
const K := preload("res://main/art/fp_art_kit.gd")

## The clean white restroom (docs/spec/03-restroom.md): low-poly tiled walls/floor,
## ceiling light panel, toilet with an openable tank lid, sink with mirror,
## and a hinged door in the +Z wall. Beyond the doorway the flesh wall
## begins right away. Built entirely in code, flat-shaded vertex colours.

## Original 4.5 m room width; retain the requested photo furniture layout.
const HALF := Vector3(2.25, 1.3, 1.5)
const CEILING_SHADER := preload("res://main/scripts/fp_room_ceiling.gdshader")
const TILE := 0.3
const DOOR_HALF_W := 0.45
const DOOR_H := 2.05
const BATH_LENGTH := 1.7
## Where the vent sits: on the ceiling, on the line from the door to the
## toilet, a little toward the door from the middle of the room. Walking in,
## the grille hangs at the top of the view over the toilet; from the seat it
## is straight ahead and up, and a hand reaching down with an offer comes
## into a level gaze. main.gd places FPVent here and the duct in the terrain
## follows this point.
const VENT_X := 0.0
const VENT_Z := -0.10
## Half of the grate's 0.52 m square opening.
const VENT_HALF := 0.26
const VENT_CENTER := Vector3(VENT_X, 2.0 * 1.3, VENT_Z)
## Ceiling opening for the art vent, made from its centre: [x0, z0, x1, z1].
const VENT_HOLE := [VENT_X - VENT_HALF, VENT_Z - VENT_HALF, VENT_X + VENT_HALF, VENT_Z + VENT_HALF]
## The room lamp and the two ceiling light disks stand on the same line as
## the vent: disk, grille, disk. The lamp hangs under the back disk, clear of
## the open grille (which drops 0.52 m) and of the hand reaching out of it.
const LIGHT_Z := -0.80
const LIGHT_DISKS := [Vector2(0.0, LIGHT_Z), Vector2(0.0, 0.85)]
## The toilet stands against the back (-Z) wall, centred on the door in the
## +Z wall and facing it (user 2026-11-14: walking in through the door the
## bowl is straight ahead, so where to vomit is plain). Its origin is the
## back of the tank on the floor; local +Z is the way the seat faces.
const TOILET_X := 0.0
const TOILET_Z := -HALF.z + 0.06
const TOILET_YAW := 0.0
## Footprint of the toilet's collision box in its own frame: width (x),
## height, depth (z), centred 0.2 m out from the wall.
const TOILET_BOX := Vector3(0.45, 0.8, 0.5)
const SINK_Z := -0.3
## The canary hole (spec 03 §2, §9): low on the -X wall, in the corner under
## the sink. The sink's half-pedestal apron hides it from standing height;
## it shows only when crouching or lying down.
const CANARY_HOLE := Vector3(-HALF.x, 0.09, SINK_Z - 0.21)
const CANARY_HOLE_HALF := Vector2(0.065, 0.07) # half width (z), half height
## Bottom edge of the ceramic apron under the basin.
const APRON_BOTTOM := 0.34
## Collision of the visible basin bowl: from the wall out to its rim, and
## down to where its rounded underside is still most of the bowl's width.
const SINK_BOWL_OUT := 0.45
const SINK_BOWL_WIDTH := 0.62
const SINK_BOWL_BOTTOM := 0.62
## Render layer of every restroom mesh (layer 11 only, not the default 1).
## Lights that must stay out of the room (the rest containers' green lamps,
## which sit in the flesh just past the thin -X / +X walls and have no
## shadows) leave this bit out of their light_cull_mask.
const ROOM_VISUAL_LAYER := 1 << 10

var door_pivot: Node3D
var toilet: Node3D
var tank_lid: Node3D
var tank_items: Node3D
## main/art models: the tooth tank on the toilet and the mirror over the sink.
var tank_art: Node3D
var mirror_art: Node3D
var bowl_center: Vector3
var _door_target: float = 0.0
var _lid_target: float = 0.0
## No light is thrown out of the door (2026-11-03 user: the cone stuck on
## the doorway shone into the flesh for no reason; the lamp's purpose is the
## glare on coming back in, main.gd _update_atmosphere / FPGlareController).
## The open door still shows the lit room from the passage.

## Shower riser along the -X wall, in the back corner beside the mirror
## cabinet (the cabinet over the basin reaches world z -1.17; the riser at
## -1.05 stood inside it).
const SHOWER_Z := -1.38
## How far to the side of the toilet's centre the paper holder hangs.
const PAPER_HOLDER_SIDE := 0.55

func _ready() -> void:
    build()
    # meshes that parts build later (their own _ready, tank items) join too
    get_tree().node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
    if n is VisualInstance3D and not (n is Light3D) and is_ancestor_of(n):
        (n as VisualInstance3D).layers = ROOM_VISUAL_LAYER

func build() -> void:
    var tile_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_tile_wall_128.png", 2.5, false, 0.0, 0.95, 1.0, false)
    var fixture_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_chrome_128.png", 1.5, false, 0.55, 0.2, 1.0, false)
    var floor_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_tile_floor_128.png", 2.5, false, 0.0, 0.9, 1.0, false)
    _build_tiles(tile_mat, floor_mat)
    _build_outer_walls()
    # 형님 결정: 변기·세면대는 얼룩 없는 순백 도자기(약한 광택).
    var ceramic_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_ceramic_128.png", 1.0, false, 0.45, 0.25, 1.0, false)
    _build_toilet(ceramic_mat)
    _build_sink(ceramic_mat)
    _build_canary_hole()
    # the door and the tub carry baked face shades (rails against panels,
    # the tub's slopes), so their materials read the vertex colour
    var door_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_door_paint_128.png", 1.0, true, 0.0, 0.9, 1.0, false)
    _build_door(door_mat, fixture_mat)
    _build_korean(fixture_mat)
    var tub_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_ceramic_128.png", 1.0, true, 0.45, 0.25, 1.0, false)
    _build_bath(tub_mat, fixture_mat)
    _build_light()
    _build_collision()
    _set_room_layer(self)

func _set_room_layer(n: Node) -> void:
    tag_room_layer(n)

## Static: recursively push every mesh under `n` onto ROOM_VISUAL_LAYER so it
## catches only in-room lights, not lamps outside (e.g. rest-container green
## lamps) whose light_cull_mask excludes this layer. Exposed static so nodes
## that are not children of FPRestroom (e.g. FPVent, parented to main) can
## still opt their own art into the room-only render layer.
static func tag_room_layer(n: Node) -> void:
    if n is VisualInstance3D and not (n is Light3D):
        (n as VisualInstance3D).layers = ROOM_VISUAL_LAYER
    for c in n.get_children():
        tag_room_layer(c)

## Static: recursively restore every mesh under `n` to the default render
## layer (1), undoing tag_room_layer. Used for nodes that move in and out of
## the restroom at runtime (the player's hands) rather than living inside it
## permanently.
static func tag_default_layer(n: Node) -> void:
    if n is VisualInstance3D and not (n is Light3D):
        (n as VisualInstance3D).layers = 1
    for c in n.get_children():
        tag_default_layer(c)

# --- tiles ------------------------------------------------------------------

func _build_tiles(mat: Material, floor_mat: Material) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var grout := Color(0.52, 0.55, 0.58)
    var h := HALF
    # The shell: six planes cut at one shared set of lines (SHELL_X/Y/Z).
    # Every vertex is snapped to the screen grid on its own, so a plane
    # whose edge has a vertex the neighbouring plane's edge lacks (the
    # ceiling pieces round the vent hole against one long wall top, the door
    # pieces against each other) parts from it and the outside shows through
    # as dots. With the same cuts on both sides of every edge the planes
    # share all their edge vertices and stay closed.
    var xs := shell_cuts(0)
    var ys := shell_cuts(1)
    var zs := shell_cuts(2)
    for i in range(xs.size() - 1):
        for k in range(zs.size() - 1):
            _rect(st, Vector3(xs[i], 0, zs[k]), Vector3(xs[i + 1], 0, zs[k]), Vector3(xs[i + 1], 0, zs[k + 1]), Vector3(xs[i], 0, zs[k + 1]), Vector3.UP, grout)
            var cx := (xs[i] + xs[i + 1]) * 0.5
            var cz := (zs[k] + zs[k + 1]) * 0.5
            if not (cx > VENT_HOLE[0] and cx < VENT_HOLE[2] and cz > VENT_HOLE[1] and cz < VENT_HOLE[3]):
                _rect(st, Vector3(xs[i], 2 * h.y, zs[k]), Vector3(xs[i + 1], 2 * h.y, zs[k]), Vector3(xs[i + 1], 2 * h.y, zs[k + 1]), Vector3(xs[i], 2 * h.y, zs[k + 1]), Vector3.DOWN, grout)
        for j in range(ys.size() - 1):
            _rect(st, Vector3(xs[i], ys[j], -h.z), Vector3(xs[i + 1], ys[j], -h.z), Vector3(xs[i + 1], ys[j + 1], -h.z), Vector3(xs[i], ys[j + 1], -h.z), Vector3.BACK, grout)
            # the front wall, less the doorway
            if not (absf((xs[i] + xs[i + 1]) * 0.5) < DOOR_HALF_W and (ys[j] + ys[j + 1]) * 0.5 < DOOR_H):
                _rect(st, Vector3(xs[i], ys[j], h.z), Vector3(xs[i + 1], ys[j], h.z), Vector3(xs[i + 1], ys[j + 1], h.z), Vector3(xs[i], ys[j + 1], h.z), Vector3.FORWARD, grout)
    for k in range(zs.size() - 1):
        for j in range(ys.size() - 1):
            _rect(st, Vector3(-h.x, ys[j], zs[k]), Vector3(-h.x, ys[j], zs[k + 1]), Vector3(-h.x, ys[j + 1], zs[k + 1]), Vector3(-h.x, ys[j + 1], zs[k]), Vector3.RIGHT, grout)
            _rect(st, Vector3(h.x, ys[j], zs[k]), Vector3(h.x, ys[j], zs[k + 1]), Vector3(h.x, ys[j + 1], zs[k + 1]), Vector3(h.x, ys[j + 1], zs[k]), Vector3.LEFT, grout)

    # (tiles themselves: flat planes above + the baked tile_tex normal map,
    # 2026-09-30 optimisation -- was ~7400 bevelled-tile triangles)
    # door frame
    var frame := Color(0.9, 0.9, 0.88)
    FDKLowPoly.add_quad(st, Vector3(-DOOR_HALF_W, 0, h.z), Vector3(-DOOR_HALF_W, DOOR_H, h.z), Vector3(-DOOR_HALF_W, DOOR_H, h.z + 0.2), Vector3(-DOOR_HALF_W, 0, h.z + 0.2), Vector3.RIGHT, frame)
    FDKLowPoly.add_quad(st, Vector3(DOOR_HALF_W, 0, h.z), Vector3(DOOR_HALF_W, DOOR_H, h.z), Vector3(DOOR_HALF_W, DOOR_H, h.z + 0.2), Vector3(DOOR_HALF_W, 0, h.z + 0.2), Vector3.LEFT, frame)
    FDKLowPoly.add_quad(st, Vector3(-DOOR_HALF_W, DOOR_H, h.z), Vector3(DOOR_HALF_W, DOOR_H, h.z), Vector3(DOOR_HALF_W, DOOR_H, h.z + 0.2), Vector3(-DOOR_HALF_W, DOOR_H, h.z + 0.2), Vector3.DOWN, frame)
    # skirting strip
    for w in [[Vector3(-h.x, 0, -h.z + 0.005), Vector3(2 * h.x, 0, 0), Vector3.BACK], [Vector3(-h.x + 0.005, 0, -h.z), Vector3(0, 0, 2 * h.z), Vector3.RIGHT], [Vector3(h.x - 0.005, 0, -h.z), Vector3(0, 0, 2 * h.z), Vector3.LEFT]]:
        _tile(st, w[0], w[1], Vector3(0, 0.08, 0), w[2], Color(0.82, 0.84, 0.86))
    var tiles := MeshInstance3D.new()
    tiles.name = "Tiles"
    tiles.mesh = _split_floor(st.commit() as ArrayMesh, _tiled(mat), _tiled(floor_mat, true))
    add_child(tiles)

func _build_outer_walls() -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var h := HALF
    var outer_color := Color(0.24, 0.23, 0.22)
    # 6 directions facing outward: floor DOWN, ceiling UP, back FORWARD, left LEFT, right RIGHT, front BACK
    _plane(st, Vector3(-h.x, 0, -h.z), Vector3(2 * h.x, 0, 0), Vector3(0, 0, 2 * h.z), Vector3.DOWN, outer_color)
    _plane(st, Vector3(-h.x, 2 * h.y, -h.z), Vector3(2 * h.x, 0, 0), Vector3(0, 0, 2 * h.z), Vector3.UP, outer_color)
    _plane(st, Vector3(-h.x, 0, -h.z), Vector3(2 * h.x, 0, 0), Vector3(0, 2 * h.y, 0), Vector3.FORWARD, outer_color)
    _plane(st, Vector3(-h.x, 0, -h.z), Vector3(0, 0, 2 * h.z), Vector3(0, 2 * h.y, 0), Vector3.LEFT, outer_color)
    _plane(st, Vector3(h.x, 0, -h.z), Vector3(0, 0, 2 * h.z), Vector3(0, 2 * h.y, 0), Vector3.RIGHT, outer_color)
    # front wall minus doorway: three pieces
    _plane(st, Vector3(-h.x, 0, h.z), Vector3(h.x - DOOR_HALF_W, 0, 0), Vector3(0, 2 * h.y, 0), Vector3.BACK, outer_color)
    _plane(st, Vector3(DOOR_HALF_W, 0, h.z), Vector3(h.x - DOOR_HALF_W, 0, 0), Vector3(0, 2 * h.y, 0), Vector3.BACK, outer_color)
    _plane(st, Vector3(-DOOR_HALF_W, DOOR_H, h.z), Vector3(2 * DOOR_HALF_W, 0, 0), Vector3(0, 2 * h.y - DOOR_H, 0), Vector3.BACK, outer_color)

    var mat := StandardMaterial3D.new()
    mat.albedo_color = outer_color
    mat.roughness = 0.9
    mat.cull_mode = BaseMaterial3D.CULL_BACK

    var mi := MeshInstance3D.new()
    mi.name = "OuterWalls"
    mi.mesh = st.commit()
    mi.material_override = mat
    add_child(mi)

## Copy of a shared PS1 material switched to flat tile mode: the grid, grout
## and bevels come from the baked normal texture, not geometry.
func _tiled(base: Material, floor_surface: bool = false) -> Material:
    var m := (base as ShaderMaterial).duplicate() as ShaderMaterial
    m.set_shader_parameter("tile_mode", true)
    m.set_shader_parameter("tile_tex", tile_texture())
    m.set_shader_parameter("tile_size", TILE)
    m.set_shader_parameter("tile_dimensions", Vector2(0.3, 0.3))
    m.set_shader_parameter("tint", Color(0.52, 0.51, 0.47) if floor_surface else Color(0.86, 0.88, 0.90))
    # the grid starts at the -X / -Z walls and the floor
    m.set_shader_parameter("tile_offset", Vector3(HALF.x, 0.0, HALF.z))
    m.set_shader_parameter("grout_color", Color(1.15, 1.15, 1.13) if floor_surface else Color(0.98, 0.97, 0.94))
    return m

static var _tile_tex: ImageTexture
## One tile, procedurally baked (RG = tangent normal xy, B = grout mask):
## 4% grout gap each side, then a 4% bevel up to the flat raised face --
## the same proportions as the old geometry (gap 0.012, bevel 0.012 of 0.3).
static func tile_texture() -> ImageTexture:
    if _tile_tex != null:
        return _tile_tex
    const N := 128
    const GAP := 0.008
    const BEV := 0.018
    var hgt := PackedFloat32Array()
    hgt.resize(N * N)
    for y in N:
        for x in N:
            var u := (x + 0.5) / N
            var v := (y + 0.5) / N
            var d := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
            hgt[x + y * N] = clampf((d - GAP) / BEV, 0.0, 1.0)
    var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
    var strength := 0.035 # raised height in tile units -> normal tilt
    for y in N:
        for x in N:
            var hl := hgt[(x - 1 + N) % N + y * N]
            var hr := hgt[(x + 1) % N + y * N]
            var hd := hgt[x + ((y - 1 + N) % N) * N]
            var hu := hgt[x + ((y + 1) % N) * N]
            var n := Vector3(-(hr - hl) * strength * N * 0.5, -(hu - hd) * strength * N * 0.5, 1.0).normalized()
            var grout := 1.0 if hgt[x + y * N] <= 0.0 else 0.0
            img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, grout, 1.0))
    _tile_tex = ImageTexture.create_from_image(img)
    return _tile_tex

## The lines every shell plane is cut at, along `axis` (0 x, 1 y, 2 z): the
## room's own faces, the vent hole's sides and the doorway's sides and top.
static func shell_cuts(axis: int) -> PackedFloat32Array:
    var at: Array = []
    match axis:
        0: at = [-HALF.x, VENT_HOLE[0], VENT_HOLE[2], -DOOR_HALF_W, DOOR_HALF_W, HALF.x]
        1: at = [0.0, DOOR_H, 2.0 * HALF.y]
        _: at = [-HALF.z, VENT_HOLE[1], VENT_HOLE[3], HALF.z]
    at.sort()
    var out := PackedFloat32Array()
    for v in at:
        if out.is_empty() or float(v) - out[out.size() - 1] > 0.002:
            out.append(float(v))
    return out

func _rect(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
    FDKLowPoly.add_quad(st, a, b, c, d, n, col)

func _tile_color(a: int, b: int, c: int, floor_tile: bool) -> Color:
    var hsh := FDKLowPoly.hash3(a, b, c)
    if floor_tile:
        return Color(0.9, 0.92, 0.93) if (a + b + c) % 2 == 0 else Color(0.82, 0.86, 0.9)
    return Color(0.9, 0.91, 0.92).darkened(hsh * 0.05)

func _plane(st: SurfaceTool, o: Vector3, u: Vector3, v: Vector3, n: Vector3, c: Color) -> void:
    FDKLowPoly.add_quad(st, o, o + u, o + u + v, o + v, n, c)

## A tile with a small bevel so it reads as a raised low-poly tile.
func _tile(st: SurfaceTool, o: Vector3, u: Vector3, v: Vector3, n: Vector3, c: Color) -> void:
    var b := 0.012
    var up := n * 0.006
    var ui := u.normalized() * b
    var vi := v.normalized() * b
    var a0 := o
    var a1 := o + u
    var a2 := o + u + v
    var a3 := o + v
    var t0 := a0 + ui + vi + up
    var t1 := a1 - ui + vi + up
    var t2 := a2 - ui - vi + up
    var t3 := a3 + ui - vi + up
    FDKLowPoly.add_quad(st, t0, t1, t2, t3, n, c)
    var side := c.darkened(0.06)
    FDKLowPoly.add_quad(st, a0, a1, t1, t0, n - v.normalized(), side)
    FDKLowPoly.add_quad(st, a1, a2, t2, t1, n + u.normalized(), side)
    FDKLowPoly.add_quad(st, a2, a3, t3, t2, n + v.normalized(), side)
    FDKLowPoly.add_quad(st, a3, a0, t0, t3, n - u.normalized(), side)

func _add(st: SurfaceTool, mat: Material, node_name: String, parent: Node3D = null) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.name = node_name
    mi.mesh = FDKLowPoly.planar_uv_mesh(st.commit() as ArrayMesh, 2.2)
    mi.material_override = mat
    (parent if parent != null else self).add_child(mi)
    return mi


## Splits a committed tile mesh into two surfaces by facing: up-facing
## triangles (the floor) wear the floor texture, everything else the wall
## texture. Planar UVs are generated per surface.
func _split_floor(mesh: ArrayMesh, wall_mat: Material, floor_mat: Material) -> ArrayMesh:
    var arr := mesh.surface_get_arrays(0)
    var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
    var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
    var parts := [[PackedVector3Array(), PackedVector3Array(), PackedColorArray()], [PackedVector3Array(), PackedVector3Array(), PackedColorArray()], [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]]
    for i in range(0, v.size(), 3):
        var is_floor := n[i].y > 0.9 and v[i].y < 0.1
        var p: Array = parts[2 if n[i].y < -0.9 else (1 if is_floor else 0)]
        for k in range(3):
            p[0].append(v[i + k])
            p[1].append(n[i + k])
            p[2].append(c[i + k] if c.size() > i + k else Color.WHITE)
    var tmp := ArrayMesh.new()
    for p in parts:
        var a := []
        a.resize(Mesh.ARRAY_MAX)
        a[Mesh.ARRAY_VERTEX] = p[0]
        a[Mesh.ARRAY_NORMAL] = p[1]
        a[Mesh.ARRAY_COLOR] = p[2]
        tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
    var out := FDKLowPoly.planar_uv_mesh(tmp, 2.2)
    out.surface_set_material(0, wall_mat)
    out.surface_set_material(1, floor_mat)
    # the ceiling is plain (no tile grid), but snaps its vertices with the
    # walls so the two stay closed along their shared edge
    var ceiling := ShaderMaterial.new()
    ceiling.shader = CEILING_SHADER
    ceiling.set_shader_parameter("albedo", Color(0.92, 0.92, 0.90))
    ceiling.set_shader_parameter("snap_precision", (wall_mat as ShaderMaterial).get_shader_parameter("snap_precision"))
    out.surface_set_material(2, ceiling)
    return out

# --- toilet -----------------------------------------------------------------

func _build_toilet(mat: Material) -> void:
    toilet = Node3D.new()
    toilet.name = "Toilet"
    toilet.position = Vector3(TOILET_X, 0, TOILET_Z)
    toilet.rotation.y = TOILET_YAW
    add_child(toilet)
    var white := Color(0.97, 0.97, 0.98)
    var shade := Color(0.88, 0.89, 0.91)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    # Eight-sided egg rings (flat face in front and behind, longer toward
    # the front): the same facet count as the room's other fixtures. The old
    # 12-sided round pedestal with a 4 cm waist read as a goblet.
    # pedestal: [y, centre z, half width, front, back]
    var ped := []
    for r in [[0.0, 0.27, 0.15, 0.24, 0.21], [0.05, 0.27, 0.15, 0.24, 0.21], [0.20, 0.28, 0.125, 0.21, 0.20], [0.36, 0.30, 0.19, 0.25, 0.22]]:
        ped.append(_egg_ring(Vector3(0, r[0], r[1]), r[2], r[3], r[4]))
    FDKLowPoly.loft(st, ped, [shade, white, white], true, false)
    # bowl: rim ring and inner funnel
    var rim_o := _egg_ring(Vector3(0, 0.42, 0.3), 0.21, 0.27, 0.24)
    var rim_i := _egg_ring(Vector3(0, 0.42, 0.3), 0.15, 0.21, 0.18)
    var in_mid := _egg_ring(Vector3(0, 0.3, 0.29), 0.11, 0.14, 0.14)
    var in_low := _egg_ring(Vector3(0, 0.22, 0.27), 0.06, 0.07, 0.07)
    FDKLowPoly.loft(st, [ped[3], rim_o], [white], false, false)
    _ring_band(st, rim_o, rim_i, Vector3.UP, white)
    _ring_band_inner(st, rim_i, in_mid, Vector3(0, 0.3, 0.29), shade)
    _ring_band_inner(st, in_mid, in_low, Vector3(0, 0.22, 0.27), shade.darkened(0.05))
    # water
    var water := Color(0.62, 0.8, 0.9)
    var wring := _egg_ring(Vector3(0, 0.28, 0.285), 0.1, 0.125, 0.125)
    for i in range(wring.size()):
        FDKLowPoly.add_tri(st, Vector3(0, 0.28, 0.285), wring[i], wring[(i + 1) % wring.size()], Vector3.UP, water.lightened(0.05 * (i % 2)))
    bowl_center = toilet.transform * Vector3(0, 0.3, 0.3)
    # seat (a flat ring slightly above the rim)
    var seat_o := _egg_ring(Vector3(0, 0.45, 0.3), 0.22, 0.28, 0.25)
    var seat_i := _egg_ring(Vector3(0, 0.45, 0.3), 0.14, 0.20, 0.17)
    _ring_band(st, seat_o, seat_i, Vector3.UP, Color(0.99, 0.99, 1.0))
    FDKLowPoly.loft(st, [_egg_ring(Vector3(0, 0.42, 0.3), 0.22, 0.28, 0.25), seat_o], [shade], false, false)
    _ring_band_inner(st, seat_i, _egg_ring(Vector3(0, 0.42, 0.3), 0.14, 0.20, 0.17), Vector3(0, 0.42, 0.3), shade)
    # the shelf the tank stands on, and the seat's two hinges against it
    _box(st, Vector3(-0.21, 0.37, 0.0), Vector3(0.21, 0.42, 0.19), white, shade)
    for hx in [-0.075, 0.075]:
        _box(st, Vector3(hx - 0.02, 0.45, 0.19), Vector3(hx + 0.02, 0.47, 0.225), white, shade)
    # tank and flush lever: the main/art tooth tank model (added below)
    _add(st, mat, "Body", toilet)
    # tank lid on a hinge at the back so it can open to show purchased items
    tank_lid = Node3D.new()
    tank_lid.name = "TankLid"
    tank_lid.position = Vector3(0, 0.8, 0.0)
    toilet.add_child(tank_lid)
    # the lid pivot stays as the logic handle; the art tank draws its own lid
    tank_art = (load("res://main/art/fp_tooth_tank.tscn") as PackedScene).instantiate()
    tank_art.name = "ToothTank"
    tank_art.position = Vector3(0, 0.42, 0.085)
    tank_art.scale = Vector3(1.0, 1.1, 1.0)
    toilet.add_child(tank_art)
    tank_art.call("set_amount", 0.0)
    tank_items = Node3D.new()
    tank_items.name = "TankItems"
    tank_items.position = Vector3(0, 0.72, 0.085)
    toilet.add_child(tank_items)

## Eight-sided ring in the XZ plane round `c`, turned so one flat face looks
## forward (+Z) and one back. `rx` is the half width; the front and back
## reaches are given apart, so the ring can be longer toward the front.
func _egg_ring(c: Vector3, rx: float, front: float, back: float) -> PackedVector3Array:
    var out := PackedVector3Array()
    var k := 1.0 / cos(PI / 8.0)
    for i in range(8):
        var a := (float(i) + 0.5) * TAU / 8.0
        var z := cos(a) * k
        out.append(c + Vector3(sin(a) * k * rx, 0, z * (front if z > 0.0 else back)))
    return out

func _yring(prof: PackedVector2Array, c: Vector3, rx: float, rz: float) -> PackedVector3Array:
    var out := PackedVector3Array()
    for p in prof:
        out.append(c + Vector3(p.x * rx, 0, -p.y * rz))
    return out

func _ring_band(st: SurfaceTool, outer: PackedVector3Array, inner: PackedVector3Array, n: Vector3, c: Color) -> void:
    for i in range(outer.size()):
        var k := (i + 1) % outer.size()
        FDKLowPoly.add_quad(st, outer[i], outer[k], inner[k], inner[i], n, c)

func _ring_band_inner(st: SurfaceTool, top: PackedVector3Array, low: PackedVector3Array, axis: Vector3, c: Color) -> void:
    for i in range(top.size()):
        var k := (i + 1) % top.size()
        var mid := (top[i] + top[k] + low[i] + low[k]) * 0.25
        var inward := Vector3(axis.x, mid.y, axis.z) - mid
        FDKLowPoly.add_quad(st, top[i], top[k], low[k], low[i], inward, c.darkened(0.04 * (i % 2)))

func _box(st: SurfaceTool, a: Vector3, b: Vector3, c: Color, side: Color) -> void:
    var p := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z),
        Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
    FDKLowPoly.add_quad(st, p[3], p[2], p[6], p[7], Vector3.UP, c)
    FDKLowPoly.add_quad(st, p[4], p[5], p[6], p[7], Vector3.BACK, c)
    FDKLowPoly.add_quad(st, p[0], p[1], p[2], p[3], Vector3.FORWARD, side)
    FDKLowPoly.add_quad(st, p[0], p[4], p[7], p[3], Vector3.LEFT, side)
    FDKLowPoly.add_quad(st, p[1], p[5], p[6], p[2], Vector3.RIGHT, side)
    FDKLowPoly.add_quad(st, p[0], p[1], p[5], p[4], Vector3.DOWN, side)


# --- modern Korean restroom fixtures (wet-room style: shower on the wall,
# floor drain, paper holder, ceiling vent) ---------------------------------

func _build_korean(mat: Material) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var chrome := Color(0.8, 0.82, 0.86)
    var chrome_d := Color(0.6, 0.62, 0.67)
    var x := -HALF.x
    var sz := SHOWER_Z
    # shower mixer on the left wall, riser bar, head, hose
    _box(st, Vector3(x, 0.95, sz - 0.08), Vector3(x + 0.06, 1.05, sz + 0.08), chrome, chrome_d)
    _box(st, Vector3(x + 0.06, 0.98, sz - 0.02), Vector3(x + 0.12, 1.02, sz + 0.02), chrome, chrome_d)
    _box(st, Vector3(x + 0.02, 1.05, sz - 0.015), Vector3(x + 0.05, 1.95, sz + 0.015), chrome, chrome_d)
    var prof := FDKLowPoly.round_profile(8)
    # head on its arm, bowed 35 degrees down toward the floor
    var hc := Vector3(x + 0.115, 1.885, sz)
    var tilt := deg_to_rad(35.0)
    var axis := Vector3(cos(tilt), -sin(tilt), 0)
    var across := Vector3(sin(tilt), cos(tilt), 0)
    var head_a := PackedVector3Array()
    var head_b := PackedVector3Array()
    for p in prof:
        head_a.append(hc - axis * 0.02 + (across * p.x + Vector3(0, 0, p.y)) * 0.06)
        head_b.append(hc + axis * 0.02 + (across * p.x + Vector3(0, 0, p.y)) * 0.07)
    FDKLowPoly.loft(st, [head_a, head_b], [chrome], true, true)
    _box(st, Vector3(x + 0.05, 1.88, sz - 0.012), Vector3(x + 0.1, 1.9, sz + 0.012), chrome, chrome_d)
    # hose: one sagging line from the mixer up to the head's arm (it used to
    # be eight separate upright boxes, a dotted line)
    var hose: Array = []
    for i in range(9):
        var t := float(i) / 8.0
        hose.append(Vector3(x + 0.08 + sin(t * PI) * 0.06, 0.95 - sin(t * PI) * 0.45 + t * 0.9, sz + t * 0.05))
    K.tube(st, Transform3D.IDENTITY, hose, [0.008], 4, [chrome_d, chrome_d.darkened(0.1)], false)
    _add(st, mat, "Shower")
    st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    # floor drain: square stainless grate slightly sunk into the floor tiles
    var dc := Vector3(-0.48, 0.012, -0.06)
    _box(st, dc - Vector3(0.1, 0.004, 0.1), dc + Vector3(0.1, 0.0, 0.1), chrome_d, chrome_d)
    for i in range(5):
        var gx := dc.x - 0.08 + i * 0.04
        _box(st, Vector3(gx - 0.006, dc.y, dc.z - 0.08), Vector3(gx + 0.006, dc.y + 0.003, dc.z + 0.08), Color(0.35, 0.36, 0.38), Color(0.3, 0.3, 0.32))
    _add(st, mat, "FloorDrain")
    # (the ceiling vent is the main/art model in VENT_HOLE, placed by main.gd)
    # Paper holder: goes with the toilet, on the wall behind it at the side
    # away from the bath. Built with the wall at local x=0 and the room
    # toward -X, then turned with the toilet.
    st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _box(st, Vector3(-0.03, 0.7, -0.1), Vector3(0.0, 0.78, 0.1), chrome, chrome_d)
    var roll_a := PackedVector3Array()
    var roll_b := PackedVector3Array()
    for p in prof:
        roll_a.append(Vector3(-0.1 + p.x * 0.055, 0.66 + p.y * 0.055, -0.08))
        roll_b.append(Vector3(-0.1 + p.x * 0.055, 0.66 + p.y * 0.055, 0.05))
    FDKLowPoly.loft(st, [roll_a, roll_b], [Color(0.98, 0.98, 0.97)], true, true)
    # the bar through the roll and the arm that carries it from the wall
    # plate (the roll used to float under the plate), and one hanging sheet
    _box(st, Vector3(-0.108, 0.652, -0.1), Vector3(-0.092, 0.668, 0.06), chrome, chrome_d)
    _box(st, Vector3(-0.108, 0.652, -0.1), Vector3(0.0, 0.70, -0.085), chrome, chrome_d)
    var paper := Color(0.98, 0.98, 0.97)
    for face in [Vector3.LEFT, Vector3.RIGHT]:
        FDKLowPoly.add_quad(st, Vector3(-0.155, 0.57, -0.07), Vector3(-0.155, 0.57, 0.04), Vector3(-0.155, 0.66, 0.04), Vector3(-0.155, 0.66, -0.07), face, paper)
    var holder := _add(st, mat, "PaperHolder")
    holder.rotation.y = TOILET_YAW + PI * 0.5
    holder.position = toilet.transform * Vector3(-PAPER_HOLDER_SIDE, 0, -0.06)

## The tub: a rim that stands a little proud of the apron, sloped inner
## walls down to a flat floor (the +X end is the long backrest slope), a
## drain and an overflow, a recessed toe-kick, and a wall tap over the foot
## end. Its outline and collision box are unchanged; no water, no stains.
func _build_bath(mat: Material, chrome_mat: Material) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var white := Color(1.0, 1.0, 1.0)
    var edge := Color(0.94, 0.95, 0.95)
    var right := HALF.x - 0.025
    var left := right - BATH_LENGTH
    var back := -HALF.z + 0.025
    var front := -HALF.z + 0.86
    var rim_y := 0.53
    var top := 0.56
    # rim: four boxes on the outer outline
    _box(st, Vector3(left, rim_y, front - 0.10), Vector3(right, top, front), white, edge)
    _box(st, Vector3(left, rim_y, back), Vector3(right, top, back + 0.09), white, edge)
    _box(st, Vector3(left, rim_y, back + 0.09), Vector3(left + 0.09, top, front - 0.10), white, edge)
    _box(st, Vector3(right - 0.09, rim_y, back + 0.09), Vector3(right, top, front - 0.10), white, edge)
    # apron under the rim, set 15 mm in on the two sides the room sees
    var ax := left + 0.015
    var az := front - 0.015
    var kick := 0.05
    FDKLowPoly.add_quad(st, Vector3(ax, kick, az), Vector3(right, kick, az), Vector3(right, rim_y, az), Vector3(ax, rim_y, az), Vector3.BACK, Color(0.95, 0.96, 0.96))
    FDKLowPoly.add_quad(st, Vector3(ax, kick, back), Vector3(ax, kick, az), Vector3(ax, rim_y, az), Vector3(ax, rim_y, back), Vector3.LEFT, Color(0.90, 0.91, 0.92))
    # toe-kick: the bottom 5 cm set a further 2 cm in, and dark
    var kx := ax + 0.02
    var kz := az - 0.02
    var dark := Color(0.42, 0.43, 0.45)
    FDKLowPoly.add_quad(st, Vector3(kx, 0, kz), Vector3(right, 0, kz), Vector3(right, kick, kz), Vector3(kx, kick, kz), Vector3.BACK, dark)
    FDKLowPoly.add_quad(st, Vector3(kx, 0, back), Vector3(kx, 0, kz), Vector3(kx, kick, kz), Vector3(kx, kick, back), Vector3.LEFT, dark)
    FDKLowPoly.add_quad(st, Vector3(ax, kick, kz), Vector3(right, kick, kz), Vector3(right, kick, az), Vector3(ax, kick, az), Vector3.DOWN, dark)
    FDKLowPoly.add_quad(st, Vector3(ax, kick, back), Vector3(kx, kick, back), Vector3(kx, kick, kz), Vector3(ax, kick, kz), Vector3.DOWN, dark)
    # inside: four slopes from the rim's inner edge down to the floor
    var o0 := Vector3(left + 0.09, top, back + 0.09)
    var o1 := Vector3(right - 0.09, top, back + 0.09)
    var o2 := Vector3(right - 0.09, top, front - 0.10)
    var o3 := Vector3(left + 0.09, top, front - 0.10)
    var fy := 0.17
    var f0 := Vector3(left + 0.15, fy, back + 0.14)
    var f1 := Vector3(right - 0.34, fy, back + 0.14)
    var f2 := Vector3(right - 0.34, fy, front - 0.15)
    var f3 := Vector3(left + 0.15, fy, front - 0.15)
    FDKLowPoly.add_quad(st, o0, o1, f1, f0, Vector3.BACK, Color(0.86, 0.88, 0.89))
    FDKLowPoly.add_quad(st, o1, o2, f2, f1, Vector3.LEFT, Color(0.90, 0.92, 0.93))
    FDKLowPoly.add_quad(st, o2, o3, f3, f2, Vector3.FORWARD, Color(0.80, 0.82, 0.83))
    FDKLowPoly.add_quad(st, o3, o0, f0, f3, Vector3.RIGHT, Color(0.83, 0.85, 0.86))
    FDKLowPoly.add_quad(st, f0, f1, f2, f3, Vector3.UP, Color(0.93, 0.95, 0.96))
    _add(st, mat, "Bathtub")
    # chrome: drain, overflow and the wall tap
    st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var chrome := Color(0.8, 0.82, 0.86)
    var chrome_d := Color(0.6, 0.62, 0.67)
    var hole := Color(0.2, 0.2, 0.22)
    var drain := Vector3(left + 0.30, fy + 0.004, (back + front) * 0.5)
    _disk(st, drain, Vector3.RIGHT, Vector3.BACK, Vector3.UP, 0.035, chrome_d)
    _disk(st, drain + Vector3(0, 0.002, 0), Vector3.RIGHT, Vector3.BACK, Vector3.UP, 0.016, hole)
    # overflow on the foot-end slope, 0.42 m up
    var slope := (f0 - o0)
    slope.z = 0.0
    var along := slope.normalized()
    var out := Vector3(-along.y, along.x, 0.0)
    if out.x < 0.0:
        out = -out
    var over := Vector3(left + 0.09 + 0.06 * (top - 0.42) / (top - fy), 0.42, (back + front) * 0.5) + out * 0.004
    _disk(st, over, Vector3.BACK, along, out, 0.03, chrome)
    _disk(st, over + out * 0.002, Vector3.BACK, along, out, 0.012, hole)
    # wall tap over the drain: body, spout, two handles
    var tx := left + 0.30
    var wall := -HALF.z
    _box(st, Vector3(tx - 0.05, 0.72, wall), Vector3(tx + 0.05, 0.78, wall + 0.06), chrome, chrome_d)
    _box(st, Vector3(tx - 0.015, 0.715, wall + 0.06), Vector3(tx + 0.015, 0.745, wall + 0.17), chrome, chrome_d)
    for side in [-1.0, 1.0]:
        _box(st, Vector3(tx + side * 0.07 - 0.02, 0.73, wall + 0.01), Vector3(tx + side * 0.07 + 0.02, 0.77, wall + 0.05), chrome, chrome_d)
    _add(st, chrome_mat, "BathFittings")

## Flat six-sided disk at `c` in the plane of `u` and `v`, facing `n`.
func _disk(st: SurfaceTool, c: Vector3, u: Vector3, v: Vector3, n: Vector3, r: float, col: Color) -> void:
    for i in range(6):
        var a0 := TAU * float(i) / 6.0
        var a1 := TAU * float(i + 1) / 6.0
        FDKLowPoly.add_tri(st, c, c + (u * cos(a0) + v * sin(a0)) * r, c + (u * cos(a1) + v * sin(a1)) * r, n, col)

## Box whose two Z faces wear `face` and whose four thin sides wear `edge`
## (door rails and casing: both broad faces are seen).
func _slab(st: SurfaceTool, a: Vector3, b: Vector3, face: Color, edge: Color) -> void:
    var p := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z),
        Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
    FDKLowPoly.add_quad(st, p[4], p[5], p[6], p[7], Vector3.BACK, face)
    FDKLowPoly.add_quad(st, p[0], p[1], p[2], p[3], Vector3.FORWARD, face)
    FDKLowPoly.add_quad(st, p[3], p[2], p[6], p[7], Vector3.UP, edge)
    FDKLowPoly.add_quad(st, p[0], p[4], p[7], p[3], Vector3.LEFT, edge)
    FDKLowPoly.add_quad(st, p[1], p[5], p[6], p[2], Vector3.RIGHT, edge)
    FDKLowPoly.add_quad(st, p[0], p[1], p[5], p[4], Vector3.DOWN, edge)

# --- sink, door, light, collision ---------------------------------------------

func _build_sink(mat: Material) -> void:
    # sink + mirror: the main/art model on the -X wall, facing into the room
    mirror_art = (load("res://main/art/fp_mirror.tscn") as PackedScene).instantiate()
    mirror_art.name = "MirrorSink"
    mirror_art.position = Vector3(-HALF.x, 0.0, SINK_Z)
    mirror_art.rotation.y = PI * 0.5
    add_child(mirror_art)

## Half-pedestal apron (a common Korean sink shroud): a curved ceramic skirt
## hanging from the basin to APRON_BOTTOM. It hides the pipes and, with
## them, the canary hole in the corner behind it from standing height.
func _build_sink_apron(mat: Material) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var x0 := -HALF.x
    var cz := SINK_Z
    var white := Color(0.97, 0.97, 0.98)
    var shade := Color(0.88, 0.89, 0.91)
    var top := 0.62
    var seg := 10
    # half-ellipse in the XZ plane: out 0.34 from the wall, 0.25 each side
    var pts := PackedVector3Array()
    for i in range(seg + 1):
        var a := PI * float(i) / seg
        pts.append(Vector3(x0 + sin(a) * 0.34, 0, cz - cos(a) * 0.25))
    for i in range(seg):
        var a := pts[i]
        var b := pts[i + 1]
        var mid := (a + b) * 0.5
        var n := Vector3(mid.x - x0, 0, mid.z - cz).normalized()
        var c := white if i % 2 == 0 else white.darkened(0.02)
        FDKLowPoly.add_quad(st, Vector3(a.x, APRON_BOTTOM, a.z), Vector3(b.x, APRON_BOTTOM, b.z), Vector3(b.x, top, b.z), Vector3(a.x, top, a.z), n, c)
        # inside face so the back of the skirt is not see-through
        FDKLowPoly.add_quad(st, Vector3(b.x, APRON_BOTTOM, b.z), Vector3(a.x, APRON_BOTTOM, a.z), Vector3(a.x, top, a.z), Vector3(b.x, top, b.z), -n, shade.darkened(0.25))
        # rolled bottom lip
        var lip_o := n * 0.012
        FDKLowPoly.add_quad(st, Vector3(a.x, APRON_BOTTOM, a.z), Vector3(a.x, APRON_BOTTOM, a.z) + lip_o + Vector3(0, 0.012, 0), Vector3(b.x, APRON_BOTTOM, b.z) + lip_o + Vector3(0, 0.012, 0), Vector3(b.x, APRON_BOTTOM, b.z), Vector3.DOWN, shade)
    _add(st, mat, "SinkApron")

## The canary hole: a small arched gap at the foot of the wall, dark inside,
## with a few chipped tile edges round it. Only visible from low down.
func _build_canary_hole() -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var hw := CANARY_HOLE_HALF.x
    var hh := CANARY_HOLE_HALF.y
    var cx := CANARY_HOLE.x + 0.013 # just proud of the raised tiles
    var cz := CANARY_HOLE.z
    var y0 := CANARY_HOLE.y - hh
    # outline: flat bottom, straight sides, round arch top
    var outline := PackedVector2Array() # (z, y)
    outline.append(Vector2(cz - hw, y0))
    var arch_y := y0 + hh * 2.0 - hw
    for i in range(9):
        var a := PI * float(i) / 8.0
        outline.append(Vector2(cz - cos(a) * hw, arch_y + sin(a) * hw))
    outline.append(Vector2(cz + hw, y0))
    var black := Color(0.015, 0.012, 0.012)
    var inner := Color(0.07, 0.06, 0.06)
    # the wall tiles are solid, so the hole is a flat dark arch laid just in front of them (reads as depth from its dark inner band)
    var depth := -0.002
    var center := Vector3(cx, y0 + hh * 0.9, cz)
    # tunnel walls going into the wall (-X), dark grey fading to black
    for i in range(outline.size()):
        var p := outline[i]
        var q := outline[(i + 1) % outline.size()]
        var a := Vector3(cx, p.y, p.x)
        var b := Vector3(cx, q.y, q.x)
        var n := Vector3(0, center.y - (p.y + q.y) * 0.5, center.z - (p.x + q.x) * 0.5).normalized()
        FDKLowPoly.add_quad(st, a, b, b + Vector3(-depth, 0, 0), a + Vector3(-depth, 0, 0), n, inner)
    # back: pure black
    for i in range(1, outline.size() - 1):
        var p0 := outline[0]
        var p1 := outline[i]
        var p2 := outline[i + 1]
        FDKLowPoly.add_tri(st, Vector3(cx - depth, p0.y, p0.x), Vector3(cx - depth, p2.y, p2.x), Vector3(cx - depth, p1.y, p1.x), Vector3.RIGHT, black)
    # chipped rim: a thin broken-tile frame just outside the opening
    var rim := Color(0.74, 0.76, 0.78)
    for i in range(outline.size() - 1):
        var p := outline[i]
        var q := outline[i + 1]
        var mid := (p + q) * 0.5
        var out := (mid - Vector2(cz, center.y)).normalized()
        var w := 0.008 + 0.01 * FDKLowPoly.hash3(i, 7, 3)
        var a := Vector3(cx + 0.004, p.y, p.x)
        var b := Vector3(cx + 0.004, q.y, q.x)
        FDKLowPoly.add_quad(st, a, b, b + Vector3(0, out.y * w, out.x * w), a + Vector3(0, out.y * w, out.x * w), Vector3.RIGHT, rim.darkened(0.1 * FDKLowPoly.hash3(i, 2, 9)))
    var m := StandardMaterial3D.new()
    m.vertex_color_use_as_albedo = true
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.roughness = 1.0
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    var mi := MeshInstance3D.new()
    mi.name = "CanaryHole"
    mi.mesh = st.commit()
    mi.material_override = m
    add_child(mi)

## Wall drawer unit (형님 2026-09-29): a white two-drawer cabinet hung on the
## +X wall, chrome bar pulls. Decorative for now; the drawers are nodes
## (DrawerTop / DrawerBottom) so they can be opened later.
const DRAWER_CENTER := Vector3(2.25, 0.95, 0.45) # on the +X wall, centre of the back face
const DRAWER_SIZE := Vector3(0.36, 0.5, 0.62)   # depth (x), height, width (z)
var drawers: Array[Node3D] = []

func _build_drawer(mat: Material, chrome_mat: Material) -> void:
    var root := Node3D.new()
    root.name = "WallDrawer"
    root.position = DRAWER_CENTER
    add_child(root)
    var d := DRAWER_SIZE
    var white := Color(0.96, 0.96, 0.95)
    var side := Color(0.86, 0.87, 0.88)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    # carcass: back at x=0, front open toward -X (into the room)
    var t := 0.018
    _box(st, Vector3(-d.x, -d.y * 0.5, -d.z * 0.5), Vector3(0, -d.y * 0.5 + t, d.z * 0.5), white, side)
    _box(st, Vector3(-d.x, d.y * 0.5 - t, -d.z * 0.5), Vector3(0, d.y * 0.5, d.z * 0.5), white, side)
    _box(st, Vector3(-d.x, -d.y * 0.5, -d.z * 0.5), Vector3(0, d.y * 0.5, -d.z * 0.5 + t), white, side)
    _box(st, Vector3(-d.x, -d.y * 0.5, d.z * 0.5 - t), Vector3(0, d.y * 0.5, d.z * 0.5), white, side)
    _box(st, Vector3(-d.x + 0.02, -0.006, -d.z * 0.5), Vector3(0, 0.006, d.z * 0.5), side, side)
    _add(st, mat, "Carcass", root)
    for i in range(2):
        var dr := Node3D.new()
        dr.name = "DrawerTop" if i == 0 else "DrawerBottom"
        var cy := d.y * 0.25 * (1 if i == 0 else -1)
        dr.position = Vector3(-d.x, cy, 0)
        root.add_child(dr)
        var fs := SurfaceTool.new()
        fs.begin(Mesh.PRIMITIVE_TRIANGLES)
        var hh := d.y * 0.25 - 0.012
        var hw := d.z * 0.5 - 0.012
        # front panel with a slight raised centre
        _box(fs, Vector3(-0.022, -hh, -hw), Vector3(0.0, hh, hw), white, side)
        _box(fs, Vector3(-0.028, -hh + 0.03, -hw + 0.03), Vector3(-0.022, hh - 0.03, hw - 0.03), Color(0.98, 0.98, 0.97), side)
        # drawer box behind the front
        _box(fs, Vector3(0.0, -hh + 0.01, -hw + 0.02), Vector3(d.x - 0.03, -hh + 0.022, hw - 0.02), side, side.darkened(0.1))
        _add(fs, mat, "Front", dr)
        var ps := SurfaceTool.new()
        ps.begin(Mesh.PRIMITIVE_TRIANGLES)
        _box(ps, Vector3(-0.06, -0.008, -0.1), Vector3(-0.05, 0.008, 0.1), Color(1, 1, 1), Color(0.88, 0.9, 0.92))
        _box(ps, Vector3(-0.05, -0.006, -0.09), Vector3(-0.028, 0.006, -0.075), Color(0.9, 0.9, 0.92), Color(0.8, 0.8, 0.84))
        _box(ps, Vector3(-0.05, -0.006, 0.075), Vector3(-0.028, 0.006, 0.09), Color(0.9, 0.9, 0.92), Color(0.8, 0.8, 0.84))
        _add(ps, chrome_mat, "Pull", dr)
        drawers.append(dr)

## Old code-built sink (kept for reference, no longer called).
func _build_sink_placeholder(mat: Material) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var x := -HALF.x
    var white := Color(0.97, 0.97, 0.98)
    var shade := Color(0.86, 0.87, 0.9)
    var prof := FDKLowPoly.round_profile(10)
    var c := Vector3(x + 0.27, 0.86, -0.35)
    var top_o := _yring(prof, c, 0.25, 0.2)
    var top_i := _yring(prof, c, 0.19, 0.15)
    var low := _yring(prof, c + Vector3(0, -0.1, 0), 0.09, 0.07)
    var under := _yring(prof, c + Vector3(0, -0.14, 0), 0.2, 0.16)
    _ring_band(st, top_o, top_i, Vector3.UP, white)
    _ring_band_inner(st, top_i, low, c + Vector3(0, -0.1, 0), shade)
    FDKLowPoly.loft(st, [under, top_o], [shade], true, false)
    # pedestal column
    var col := []
    for r in [[0.0, 0.1], [0.6, 0.07], [0.72, 0.12]]:
        col.append(_yring(prof, Vector3(x + 0.22, r[0], -0.35), r[1], r[1]))
    FDKLowPoly.loft(st, col, [white, shade], true, true)
    # tap
    _box(st, Vector3(x + 0.02, 0.9, -0.38), Vector3(x + 0.14, 0.94, -0.32), Color(0.78, 0.8, 0.84), Color(0.6, 0.62, 0.66))
    # mirror (pale blue-gray, framed)
    _box(st, Vector3(x + 0.005, 1.15, -0.72), Vector3(x + 0.03, 1.85, 0.02), Color(0.88, 0.9, 0.92), Color(0.8, 0.82, 0.85))
    FDKLowPoly.add_quad(st, Vector3(x + 0.032, 1.19, -0.68), Vector3(x + 0.032, 1.19, -0.02), Vector3(x + 0.032, 1.81, -0.02), Vector3(x + 0.032, 1.81, -0.68), Vector3.RIGHT, Color(0.72, 0.8, 0.86))
    _add(st, mat, "Sink")

func _build_door(mat: Material, handle_mat: Material) -> void:
    door_pivot = Node3D.new()
    door_pivot.name = "DoorPivot"
    door_pivot.position = Vector3(-DOOR_HALF_W, 0, HALF.z + 0.02)
    add_child(door_pivot)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var w := 2 * DOOR_HALF_W - 0.01
    var top := DOOR_H - 0.01
    # A framed door on both faces: stiles and three rails stand 4 mm proud
    # of the slab, so the two fields between them read as sunk panels.
    var rail := Color(1.0, 1.0, 0.99)
    var panel := Color(0.97, 0.97, 0.96)
    var edge := Color(0.80, 0.80, 0.79)
    _slab(st, Vector3(0.005, 0.005, -0.02), Vector3(w, top, 0.02), panel, Color(0.9, 0.9, 0.89))
    var gap := Color(0.55, 0.56, 0.57)
    for face in [-1.0, 1.0]:
        var z0: float = face * 0.02
        var z1: float = face * 0.024
        var za := minf(z0, z1)
        var zb := maxf(z0, z1)
        _slab(st, Vector3(0.005, 0.005, za), Vector3(0.12, top, zb), rail, edge)
        _slab(st, Vector3(w - 0.12, 0.005, za), Vector3(w, top, zb), rail, edge)
        for band in [[0.005, 0.25], [0.95, 1.10], [1.85, top]]:
            _slab(st, Vector3(0.12, band[0], za), Vector3(w - 0.12, band[1], zb), rail, edge)
        # painted-shut vent slats in the bottom rail (drawn, not cut through)
        var zs: float = face * 0.0245
        var zt: float = face * 0.0275
        FDKLowPoly.add_quad(st, Vector3(0.22, 0.08, zs), Vector3(w - 0.22, 0.08, zs), Vector3(w - 0.22, 0.20, zs), Vector3(0.22, 0.20, zs), Vector3(0, 0, face), gap)
        for i in range(4):
            var sy := 0.086 + i * 0.03
            _slab(st, Vector3(0.22, sy, minf(zs, zt)), Vector3(w - 0.22, sy + 0.018, maxf(zs, zt)), rail, edge)
    _add(st, mat, "Door", door_pivot)
    # chrome lever handle on each face, as its own mesh for the chrome
    # material: rose plate, neck, and a lever reaching toward the hinge
    var hs := SurfaceTool.new()
    hs.begin(Mesh.PRIMITIVE_TRIANGLES)
    var hx := w - 0.075
    var hy := 1.0
    var cr := Color(1, 1, 1)
    var cr_d := Color(0.9, 0.9, 0.92)
    for face in [-1.0, 1.0]:
        var parts := [
            [Vector3(hx - 0.025, hy - 0.025, 0.024), Vector3(hx + 0.025, hy + 0.025, 0.032)],
            [Vector3(hx - 0.008, hy - 0.008, 0.032), Vector3(hx + 0.008, hy + 0.008, 0.077)],
            [Vector3(hx - 0.101, hy - 0.009, 0.068), Vector3(hx + 0.009, hy + 0.009, 0.086)],
        ]
        for part in parts:
            var pa: Vector3 = part[0]
            var pb: Vector3 = part[1]
            _box(hs, Vector3(pa.x, pa.y, minf(pa.z * face, pb.z * face)), Vector3(pb.x, pb.y, maxf(pa.z * face, pb.z * face)), cr, cr_d)
    _add(hs, handle_mat, "Handle", door_pivot)
    # casing on the room side of the wall round the doorway
    var cs_st := SurfaceTool.new()
    cs_st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var casing := Color(0.98, 0.98, 0.96)
    var cz0 := HALF.z - 0.012
    var cw := 0.06
    _slab(cs_st, Vector3(-DOOR_HALF_W - cw, 0, cz0), Vector3(-DOOR_HALF_W, DOOR_H + cw, HALF.z), casing, edge)
    _slab(cs_st, Vector3(DOOR_HALF_W, 0, cz0), Vector3(DOOR_HALF_W + cw, DOOR_H + cw, HALF.z), casing, edge)
    _slab(cs_st, Vector3(-DOOR_HALF_W, DOOR_H, cz0), Vector3(DOOR_HALF_W, DOOR_H + cw, HALF.z), casing, edge)
    _add(cs_st, mat, "DoorCasing")
    var body := StaticBody3D.new()
    body.name = "DoorBody"
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = Vector3(w, DOOR_H, 0.04)
    cs.shape = bs
    cs.position = Vector3(w * 0.5, DOOR_H * 0.5, 0)
    body.add_child(cs)
    door_pivot.add_child(body)

func _build_light() -> void:
    var y := 2 * HALF.y - 0.015
    var fixture := StandardMaterial3D.new()
    fixture.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    fixture.albedo_color = Color(0.90, 0.95, 1.0)
    for i in range(LIGHT_DISKS.size()):
        var spot: Vector2 = LIGHT_DISKS[i]
        var disk := MeshInstance3D.new()
        disk.name = "CeilingDownlight" if i == 0 else "CeilingDownlight%d" % (i + 1)
        var mesh := CylinderMesh.new()
        mesh.top_radius = 0.11
        mesh.bottom_radius = 0.11
        mesh.height = 0.025
        mesh.radial_segments = 8
        disk.mesh = mesh
        disk.material_override = fixture
        disk.position = Vector3(spot.x, y, spot.y)
        add_child(disk)
    var l := OmniLight3D.new()
    l.name = "RoomLight"
    l.position = Vector3(0, 2 * HALF.y - 0.3, LIGHT_Z)
    l.omni_range = 4.0
    l.light_energy = 0.3
    l.light_cull_mask = ROOM_VISUAL_LAYER | (1 << 11) | (1 << 12) | (1 << 13)
    # Walls already separate render layers; six shadow faces were redundant.
    l.shadow_enabled = true
    # Cold fluorescent white (docs/tone-and-manner.md 3). The flesh is lit by the
    # warm eye lamp, so the two worlds part by colour temperature as well.
    l.light_color = Color(0.90, 0.96, 1.0)
    add_child(l)

func _build_collision() -> void:
    var body := StaticBody3D.new()
    body.name = "RoomBody"
    add_child(body)
    var h := HALF
    var t := 0.1
    var bath_right := h.x - 0.025
    var boxes := [
        [Vector3(0, -t * 0.5, 0), Vector3(2 * h.x, t, 2 * h.z)],
        [Vector3(0, 2 * h.y + t * 0.5, 0), Vector3(2 * h.x, t, 2 * h.z)],
        [Vector3(0, h.y, -h.z - t * 0.5), Vector3(2 * h.x, 2 * h.y, t)],
        [Vector3(-h.x - t * 0.5, h.y, 0), Vector3(t, 2 * h.y, 2 * h.z)],
        [Vector3(h.x + t * 0.5, h.y, 0), Vector3(t, 2 * h.y, 2 * h.z)],
        [Vector3(-(h.x + DOOR_HALF_W) * 0.5, h.y, h.z + t * 0.5), Vector3(h.x - DOOR_HALF_W, 2 * h.y, t)],
        [Vector3((h.x + DOOR_HALF_W) * 0.5, h.y, h.z + t * 0.5), Vector3(h.x - DOOR_HALF_W, 2 * h.y, t)],
        [Vector3(0, (DOOR_H + 2 * h.y) * 0.5, h.z + t * 0.5), Vector3(2 * DOOR_HALF_W, 2 * h.y - DOOR_H, t)],
        [toilet.transform * Vector3(0, 0.4, 0.2), TOILET_BOX],
        # the wall-hung basin's bowl (fp_mirror BASIN_*: rim 0.885 m, 0.44 m
        # out from the wall, 0.30 m each side, tapering to 0.19 m out at its
        # 0.40 m underside). The ceramic apron that once hung to APRON_BOTTOM
        # is no longer built; its full-height box stayed and, unseen, hid the
        # canary hole from every crouched aim in front of it.
        [Vector3(-h.x + SINK_BOWL_OUT * 0.5, (SINK_BOWL_BOTTOM + 0.9) * 0.5, SINK_Z), Vector3(SINK_BOWL_OUT, 0.9 - SINK_BOWL_BOTTOM, SINK_BOWL_WIDTH)],
        [Vector3(-h.x + 0.11, 1.78, SINK_Z - 0.05), Vector3(0.22, 1.20, 1.65)], # fp_mirror CABINET_X
        [Vector3(bath_right - BATH_LENGTH * 0.5, 0.28, -h.z + 0.43), Vector3(BATH_LENGTH, 0.56, 0.86)],
    ]
    for b in boxes:
        var cs := CollisionShape3D.new()
        var bs := BoxShape3D.new()
        bs.size = b[1]
        cs.shape = bs
        cs.position = b[0]
        body.add_child(cs)

# --- runtime --------------------------------------------------------------------

func set_door_open(open: bool, instant: bool = false) -> void:
    _door_target = deg_to_rad(100.0) if open else 0.0
    if instant:
        door_pivot.rotation.y = _door_target

func is_door_open() -> bool:
    return absf(_door_target) > 0.01

func set_tank_open(open: bool, instant: bool = false) -> void:
    _lid_target = deg_to_rad(-75.0) if open else 0.0
    if instant:
        tank_lid.rotation.x = _lid_target

func _process(delta: float) -> void:
    FPProfile.begin("restroom")
    _process_inner(delta)
    FPProfile.end("restroom")

func _process_inner(delta: float) -> void:
    var k := 1.0 - exp(-delta * 6.0)
    door_pivot.rotation.y = lerpf(door_pivot.rotation.y, _door_target, k)
    tank_lid.rotation.x = lerpf(tank_lid.rotation.x, _lid_target, k)
    if tank_art != null:
        tank_art.call("set_lid_open", tank_lid.rotation.x / deg_to_rad(-75.0))

## 0 (shut) .. 1 (fully open), from the door's actual swing.
func door_open_amount() -> float:
    return clampf(door_pivot.rotation.y / deg_to_rad(100.0), 0.0, 1.0)

## Would a body standing at this world point be inside the toilet? (A save
## made before the toilet moved can hold a spot where it now stands.)
func toilet_blocks(p: Vector3) -> bool:
    var l := toilet.to_local(p)
    return absf(l.x) < TOILET_BOX.x * 0.5 + 0.2 and l.z < 0.2 + TOILET_BOX.z * 0.5 + 0.1 and l.z > -0.3 and l.y < TOILET_BOX.y + 1.0 and l.y > -0.2

## Is this world point inside the room box?
func contains(p: Vector3) -> bool:
    var l := p - global_position
    return absf(l.x) <= HALF.x and l.y >= 0.0 and l.y <= 2 * HALF.y and absf(l.z) <= HALF.z
