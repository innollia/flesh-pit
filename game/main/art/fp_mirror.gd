extends Node3D

## Photo A: broad two-door mirror cabinet above a wall-mounted basin.
const K := preload("res://main/art/fp_art_kit.gd")
const LEAF_W := 0.40
const HH := 0.60
const CY := 1.78
## Cabinet centre along the wall (local x; the sink is at 0, the toilet at
## about -1.0). It hangs over the sink only: reaching over the toilet it put
## the leaning head inside it and hid the tank (2026-10-31 play).
const CABINET_X := 0.05
var door_pivot: Node3D
var door_pivot_right: Node3D
var door_surface: Node3D
var door_surface_right: Node3D
var cabinet_open := false
var _glow: MeshInstance3D

func _ready() -> void:
	var chrome := K.mat("tex_chrome_128.png", 0.45, false)
	var ceramic := K.mat("tex_ceramic_128.png", 0.3, false)
	var st := K.begin()
	var white := Color(0.94, 0.94, 0.91)
	# Two mirror doors over the basin.
	var cabinet_center := CABINET_X
	for xx in [-0.81, 0.81]:
		K.rbox(st, K.T(Vector3(xx + cabinet_center, CY, 0.11)), Vector3(0.012, HH, 0.11), 0.004, white)
	for yy in [CY - HH, CY, CY + HH]:
		K.rbox(st, K.T(Vector3(cabinet_center, yy, 0.11)), Vector3(0.80, 0.012, 0.10), 0.004, white)
	K.rbox(st, K.T(Vector3(cabinet_center, CY, 0.025)), Vector3(0.80, HH, 0.012), 0.004, white)
	for xx in [-0.32, 0.40]:
		K.lathe(st, K.T(Vector3(xx, CY - HH + 0.014, 0.10)), [Vector2(0, 0), Vector2(0.025, 0), Vector2(0.025, 0.14), Vector2(0.01, 0.15), Vector2(0, 0.15)], 6, [Color(0.8, 0.85, 0.78)])
	K.add_mesh(self, "StorageCabinet", K.finish(st), ceramic)
	door_pivot = K.pivot(self, "MirrorDoorHinge", Vector3(cabinet_center - 0.80, 0, 0.235))
	door_surface = K.pivot(door_pivot, "MirrorDoor", Vector3(LEAF_W, 0, 0))
	door_pivot_right = K.pivot(self, "MirrorDoorHingeRight", Vector3(cabinet_center + 0.80, 0, 0.235))
	door_surface_right = K.pivot(door_pivot_right, "MirrorDoorRight", Vector3(-LEAF_W, 0, 0))
	for leaf in [door_surface, door_surface_right]:
		st = K.begin()
		for xx in [-LEAF_W, LEAF_W]:
			K.rbox(st, K.T(Vector3(xx, CY, 0)), Vector3(0.007, HH, 0.009), 0.002, Color(0.76, 0.78, 0.78))
		for yy in [CY - HH, CY + HH]:
			K.rbox(st, K.T(Vector3(0, yy, 0)), Vector3(LEAF_W, 0.007, 0.009), 0.002, Color(0.76, 0.78, 0.78))
		K.add_mesh(leaf, "MirrorFrame", K.finish(st), chrome)
		st = K.begin()
		K.quad(st, Transform3D.IDENTITY, Vector3(-LEAF_W, CY-HH, 0.01), Vector3(LEAF_W, CY-HH, 0.01), Vector3(LEAF_W, CY+HH, 0.01), Vector3(-LEAF_W, CY+HH, 0.01), Vector3.BACK, Color(0.7, 0.76, 0.8))
		K.add_mesh(leaf, "Glass", K.finish(st), chrome)
		# Solid painted back board behind the glass: opened, the door shows
		# its back to the room, and the glass quad alone was see-through
		# from behind (2026-11-03 user).
		st = K.begin()
		K.rbox(st, K.T(Vector3(0, CY, -0.002)), Vector3(LEAF_W - 0.003, HH - 0.003, 0.006), 0.002, Color(0.9, 0.9, 0.87), Color(0.8, 0.8, 0.78))
		K.add_mesh(leaf, "MirrorBack", K.finish(st), ceramic)
	# Ledge under the cabinet, over the basin only (it used to run on over
	# the toilet tank and hide its lid).
	st = K.begin()
	K.rbox(st, K.T(Vector3(0.0, 0.92, 0.07)), Vector3(0.42, 0.016, 0.075), 0.008, white)
	K.add_mesh(self, "WallLedge", K.finish(st), ceramic)
	# Tall single-lever faucet on the basin's back deck.
	st = K.begin()
	var c := Color(0.84, 0.85, 0.85)
	K.lathe(st, K.T(Vector3(0, BASIN_TOP - 0.005, 0.08)), [Vector2(0.025, 0), Vector2(0.023, 0.20), Vector2(0.02, 0.24), Vector2(0, 0.245)], 6, [c])
	K.tube(st, Transform3D.IDENTITY, [Vector3(0, BASIN_TOP + 0.175, 0.08), Vector3(0, BASIN_TOP + 0.185, 0.19), Vector3(0, BASIN_TOP + 0.16, 0.235)], [0.014, 0.013, 0.01], 4, [c])
	K.rbox(st, K.T(Vector3(0, BASIN_TOP + 0.245, 0.10)), Vector3(0.018, 0.006, 0.045), 0.004, c)
	K.add_mesh(self, "Chrome", K.finish(st), chrome)
	_build_basin()

## Wall-hung basin in the room's PS1 style (2026-11-03 user: the smooth
## 12-sided lathe bowl read as a high-quality model next to the boxy
## room). A six-sided tapered block with flat baked face shades and the
## ceramic texture at 64 px; the bowl is a shallow six-sided recess whose
## shading and drain are painted into a 32 px image, not modelled.
const BASIN_TOP := 0.885
const BASIN_BOTTOM := 0.40
const BASIN_FLOOR := 0.79
## Plan outlines (local x along the wall, z out of it), wall side last.
const BASIN_OUTER := [Vector2(-0.30, -0.02), Vector2(-0.30, 0.32), Vector2(-0.20, 0.44), Vector2(0.20, 0.44), Vector2(0.30, 0.32), Vector2(0.30, -0.02)]
const BASIN_UNDER := [Vector2(-0.11, -0.02), Vector2(-0.11, 0.14), Vector2(-0.07, 0.19), Vector2(0.07, 0.19), Vector2(0.11, 0.14), Vector2(0.11, -0.02)]
const BASIN_OPEN := [Vector2(-0.24, 0.14), Vector2(-0.24, 0.30), Vector2(-0.17, 0.38), Vector2(0.17, 0.38), Vector2(0.24, 0.30), Vector2(0.24, 0.14)]
const BASIN_DRAIN_FLOOR := [Vector2(-0.09, 0.19), Vector2(-0.09, 0.25), Vector2(-0.06, 0.29), Vector2(0.06, 0.29), Vector2(0.09, 0.25), Vector2(0.09, 0.19)]
const BOWL_TEX := 32

static func _ring(plan: Array, y: float) -> Array:
	var out := []
	for p in plan:
		out.append(Vector3(p.x, y, p.y))
	return out

## Quads between two rings of the same count. `closed` adds the last->first
## side (the wall side is left open where it sits in the wall).
static func _band(st: SurfaceTool, a: Array, b: Array, centre: Vector3, cols: Array, closed: bool, inward: bool = false) -> void:
	var n := a.size()
	for i in range(n if closed else n - 1):
		var j := (i + 1) % n
		var mid: Vector3 = (a[i] + a[j] + b[i] + b[j]) * 0.25
		var out := mid - centre
		out.y = 0.0
		if inward:
			out = -out
		K.quad(st, Transform3D.IDENTITY, a[i], a[j], b[j], b[i], out.normalized() if out.length() > 0.001 else Vector3.UP, cols[i % cols.size()])

func _build_basin() -> void:
	var ceramic_lo := K.mat("tex_ceramic_64.png", 0.12, false)
	var st := K.begin()
	var top := _ring(BASIN_OUTER, BASIN_TOP)
	var lip := _ring(BASIN_OUTER, BASIN_TOP - 0.035)
	var under := _ring(BASIN_UNDER, BASIN_BOTTOM)
	var centre := Vector3(0.0, 0.6, 0.12)
	# flat baked shades per face, like the room's other vertex-coloured props
	var side := [Color(0.86, 0.86, 0.84), Color(0.9, 0.9, 0.88), Color(0.95, 0.95, 0.93), Color(0.9, 0.9, 0.88), Color(0.86, 0.86, 0.84)]
	var low := [Color(0.72, 0.72, 0.71), Color(0.76, 0.76, 0.75), Color(0.8, 0.8, 0.79), Color(0.76, 0.76, 0.75), Color(0.72, 0.72, 0.71)]
	_band(st, top, lip, centre + Vector3(0, 0.3, 0), side, false)
	_band(st, lip, under, centre, low, false)
	# underside cap
	for i in range(1, under.size() - 1):
		K.tri(st, Transform3D.IDENTITY, under[0], under[i], under[i + 1], Vector3.DOWN, Color(0.62, 0.62, 0.61))
	# flat rim deck between the outer edge and the bowl opening
	var open := _ring(BASIN_OPEN, BASIN_TOP)
	for i in range(top.size()):
		var j := (i + 1) % top.size()
		K.quad(st, Transform3D.IDENTITY, top[i], top[j], open[j], open[i], Vector3.UP, Color(0.97, 0.97, 0.95))
	K.add_mesh(self, "Basin", K.finish(st), ceramic_lo)
	# the bowl: painted image, mapped straight down over the opening
	var bowl_mat: ShaderMaterial = K.mat("tex_ceramic_64.png", 0.12, false).duplicate()
	bowl_mat.set_shader_parameter("albedo_tex", bowl_texture())
	bowl_mat.set_shader_parameter("uv_scale", 1.0)
	var floor_ring := _ring(BASIN_DRAIN_FLOOR, BASIN_FLOOR)
	var bst := K.begin()
	var bowl_centre := Vector3(0.0, BASIN_FLOOR, 0.26)
	var shade := [Color(0.9, 0.9, 0.9), Color(0.95, 0.95, 0.95), Color(1, 1, 1), Color(0.95, 0.95, 0.95), Color(0.9, 0.9, 0.9), Color(0.82, 0.82, 0.82)]
	_band(bst, open, floor_ring, bowl_centre, shade, true, true)
	for i in range(1, floor_ring.size() - 1):
		K.tri(bst, Transform3D.IDENTITY, floor_ring[0], floor_ring[i], floor_ring[i + 1], Vector3.UP, Color(1, 1, 1))
	var mesh := bst.commit()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs := PackedVector2Array()
	for v in verts:
		uvs.append(bowl_uv(v))
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var bowl := ArrayMesh.new()
	bowl.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	K.add_mesh(self, "BasinBowl", bowl, bowl_mat)

## Top-down UV over the bowl opening (0..1 across BASIN_OPEN's box).
static func bowl_uv(v: Vector3) -> Vector2:
	return Vector2((v.x + 0.24) / 0.48, (v.z - 0.14) / 0.24)

static var _bowl_tex: ImageTexture
## 32 px painted bowl: white glaze stepping darker toward the drain in
## dithered bands, a chrome drain ring with a dark hole and slots.
static func bowl_texture() -> ImageTexture:
	if _bowl_tex != null:
		return _bowl_tex
	var n := BOWL_TEX
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var drain := bowl_uv(Vector3(0.0, 0.0, 0.245)) * n
	var bayer := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	for y in range(n):
		for x in range(n):
			var p := Vector2(x + 0.5, y + 0.5)
			# elliptical distance from the drain, 0 at the drain .. ~1 at the rim
			var d := Vector2((p.x - drain.x) / (n * 0.5), (p.y - drain.y) / (n * 0.55)).length()
			var t := clampf(d, 0.0, 1.0)
			# four bands, ordered dither between them
			var level := t * 3.0 + (float(bayer[(y % 4) * 4 + x % 4]) / 16.0 - 0.5) * 0.9
			var band := clampf(roundf(level), 0.0, 3.0)
			var g: float = [0.74, 0.8, 0.87, 0.93][int(band)]
			var col := Color(g, g, g * 0.985)
			# the back edge under the faucet is a touch shaded
			if p.y < 2.0:
				col = col.darkened(0.06)
			var r := (p - drain).length()
			if r < 3.6:
				col = Color(0.66, 0.68, 0.7) # chrome ring
			if r < 2.4:
				col = Color(0.16, 0.15, 0.15) # hole
				if absi(int(floor(p.y)) - int(drain.y)) == 0 and r > 0.9:
					col = Color(0.5, 0.52, 0.54) # slot bar
			img.set_pixel(x, y, col)
	_bowl_tex = ImageTexture.create_from_image(img)
	return _bowl_tex

func set_focus(_on: bool) -> void:
	pass

func mirror_center() -> Vector3:
	return Vector3(CABINET_X, CY, 0.25)

func reflection_surface() -> Node3D:
	return door_surface

func toggle_cabinet() -> void:
	cabinet_open = not cabinet_open

func _process(delta: float) -> void:
	if door_pivot != null:
		door_pivot.rotation.y = move_toward(door_pivot.rotation.y, -1.25 if cabinet_open else 0.0, delta * 2.2)
		door_pivot_right.rotation.y = move_toward(door_pivot_right.rotation.y, 1.25 if cabinet_open else 0.0, delta * 2.2)

func capture_setup() -> Dictionary:
	return {"cam_pos": Vector3(1.3, 1.5, 2.5), "look_at": Vector3(0, 1.2, 0.2), "env": "restroom", "fov": 55.0}
