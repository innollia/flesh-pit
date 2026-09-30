extends Node3D

## What the player sees looking down: the belly and waist. A work-shirt torso
## (belly pushed forward, chest drawn back under the eye so no lid covers it),
## trousers, and round it a leather belt with a
## buckle, up to 3 spray cans in clip holsters on the right hip (cheap can =
## white/yellow, expensive = black/red), and the canary riding in the left
## front trouser POCKET (docs/spec/07-danger-navigation.md: pocket, no cage), head peeking out.
## Origin = centre of the waist at belt height; the player faces -Z.
## Public: set_spray_count(cheap, expensive) (total capped at 3),
## set_canary(present), canary_look(yaw_deg), set_canary_scared(bool),
## set_hung(ids) (tool id per hook, "" = empty ring), hook_point(i).
## Tool hooks: 3 steel rings hanging off the front of the belt (knife,
## blender, big saw), where the player looks down to swap tools.

const K := preload("res://main/art/fp_art_kit.gd")
const RX := 0.21   ## waist half width
const RZ := 0.13   ## waist half depth at the back / hips
const RZF := 0.19  ## waist half depth at the front (belly side)
var _cans: Array = []
var _canary: Node3D
var _canary_head: Node3D
var _scared := false
var _time := 0.0
const HOOK_X := [-0.3, 0.0, 0.3] ## hooks side by side on the front rail
const ToolScenes := {"knife": "res://main/art/fp_knife.tscn", "blender": "res://main/art/fp_blender.tscn", "big_saw": "res://main/art/fp_big_saw.tscn"}
var _hooks: Array = []
var _hung: Array = ["", "", ""]

func _ready() -> void:
    var st := K.begin()
    var cloth := Color(0.28, 0.3, 0.36)    # worn work trousers
    var cloth_d := Color(0.2, 0.21, 0.26)
    # trousers: a lofted hip (open on top, the torso sits on it) + two leg
    # stubs down to the knees
    var hip: Array = []
    for k in range(4):
        hip.append(_waist_ring(-k * 0.07, RX * (1.0 + k * 0.03), RZF * (1.0 - k * 0.04), RZ * (1.0 + k * 0.05)))
    _loft_lit(st, hip, [cloth, cloth, cloth_d])
    for sx in [-1, 1]:
        K.tube(st, Transform3D.IDENTITY, [Vector3(sx * 0.1, -0.2, -0.03), Vector3(sx * 0.11, -0.38, -0.08), Vector3(sx * 0.11, -0.55, -0.12)], [0.095, 0.082, 0.072], 8, [cloth, cloth_d])
    # left front pocket opening (dark slit)
    K.quad(st, Transform3D.IDENTITY, Vector3(-0.17, -0.045, -RZF * 0.62), Vector3(-0.09, -0.04, -RZF * 0.93), Vector3(-0.1, -0.12, -RZF * 0.93), Vector3(-0.18, -0.12, -RZF * 0.6), Vector3(0, 0, -1), Color(0.07, 0.07, 0.09))
    var trousers_mi := K.add_mesh(self, "Trousers", K.finish(st, 5.0), K.mat("tex_door_paint_128.png", 0.1, true))
    trousers_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # torso: work shirt from the waist up. The belly swells forward a little
    # but never past the belt, the chest draws back under the eye, and the top
    # closes behind the camera, so looking down shows belly -> belt -> legs.
    st = K.begin()
    var shirt := Color(0.52, 0.49, 0.37)
    var shirt_d := Color(0.4, 0.37, 0.28)
    var torso: Array = []
    for r in [[0.0, 0.205, 0.18, 0.125], [0.1, 0.212, 0.172, 0.13], [0.22, 0.21, 0.15, 0.13], [0.36, 0.22, 0.12, 0.135], [0.5, 0.225, 0.05, 0.14], [0.6, 0.19, -0.01, 0.13]]:
        torso.append(_waist_ring(r[0], r[1], r[2], r[3]))
    # rings top-first (the kit loft convention); the shoulders close below
    torso.reverse()
    _loft_lit(st, torso, [shirt_d, shirt_d, shirt, shirt, shirt])
    # shirt buttons down the belly line
    for by in [0.08, 0.18, 0.28]:
        var bz: float = -lerpf(0.172, 0.15, (by - 0.1) / 0.12) - 0.004
        K.rbox(st, K.T(Vector3(0, by, bz)), Vector3(0.008, 0.008, 0.003), 0.002, Color(0.85, 0.82, 0.7))
    var torso_mi := K.add_mesh(self, "Torso", K.finish(st, 5.0), K.mat("tex_door_paint_128.png", 0.1, true))
    # the body must not shade itself dark under the ceiling tube
    torso_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # belt band: a thick leather loop right round the waist
    st = K.begin()
    var leather := Color(0.44, 0.26, 0.13)
    var loop: Array = []
    var ring0 := _waist_ring(0.0, RX + 0.012, RZF + 0.012, RZ + 0.012)
    for j in range(ring0.size() + 1):
        loop.append(ring0[j % ring0.size()])
    K.tube(st, Transform3D.IDENTITY, loop, [0.034], 4, [leather], false, 0.3)    # buckle
    K.rbox(st, K.T(Vector3(0, 0, -RZF - 0.03)), Vector3(0.04, 0.032, 0.007), 0.005, Color(0.7, 0.66, 0.5))
    K.rbox(st, K.T(Vector3(0, 0, -RZF - 0.037)), Vector3(0.026, 0.018, 0.003), 0.002, Color(0.2, 0.15, 0.1))
    K.add_mesh(self, "Belt", K.finish(st, 6.0), K.mat("tex_door_paint_64.png", 0.25, true))
    # 3 holster clips + cans on the right hip
    for i in range(3):
        var a := -0.55 + i * 0.42
        var p := Vector3(cos(a) * (RX + 0.04), -0.05, sin(a) * (RZ + 0.04))
        var holder := K.pivot(self, "Can%d" % i, p)
        holder.rotation.y = -a + PI * 0.5
        st = K.begin()
        K.rbox(st, K.T(Vector3(0, 0.05, -0.028)), Vector3(0.012, 0.012, 0.01), 0.003, Color(0.2, 0.2, 0.22))
        K.tube(st, Transform3D.IDENTITY, [Vector3(0, -0.02, 0), Vector3(0, 0.0, 0)], [0.036], 8, [Color(0.25, 0.25, 0.27)], false)
        K.add_mesh(holder, "Clip", K.finish(st, 6.0), K.mat("tex_chrome_64.png", 0.2, true))
        var can := K.pivot(holder, "Spray")
        _cans.append(can)
    _build_hooks()
    _canary = K.pivot(self, "Canary", Vector3(-0.15, -0.05, -RZF * 0.8 - 0.02))
    _build_canary()
    set_spray_count(2, 1)
    set_canary(true)

func _can_mesh(expensive: bool) -> ArrayMesh:
    var st := K.begin()
    var body := Color(0.12, 0.1, 0.1) if expensive else Color(0.9, 0.88, 0.8)
    var band := Color(0.75, 0.08, 0.06) if expensive else Color(0.9, 0.75, 0.1)
    var metal := Color(0.75, 0.76, 0.78)
    K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, -0.07), Vector2(0.028, -0.07), Vector2(0.031, -0.064), Vector2(0.031, -0.02), Vector2(0.031, 0.02), Vector2(0.031, 0.05), Vector2(0.024, 0.066), Vector2(0.012, 0.072), Vector2(0.012, 0.085), Vector2(0.0, 0.088)], 8, [metal, metal, body, band, body, metal, metal, Color(0.95, 0.95, 0.95)])
    return K.finish(st, 8.0)

func _build_canary() -> void:
    var st := K.begin()
    var yellow := Color(0.98, 0.84, 0.18)
    K.blob(st, Transform3D.IDENTITY, Vector3(0, -0.01, 0), Vector3(0.022, 0.02, 0.02), 0.1, 3, yellow, Color(0.9, 0.72, 0.1))
    K.add_mesh(_canary, "Body", K.finish(st), K.mat("tex_skin_64.png", 0.1, true))
    _canary_head = K.pivot(_canary, "Head", Vector3(0, 0.022, -0.004))
    st = K.begin()
    K.blob(st, Transform3D.IDENTITY, Vector3.ZERO, Vector3(0.016, 0.015, 0.016), 0.1, 5, yellow, Color(1.0, 0.9, 0.35))
    K.lathe(st, K.T(Vector3(0, -0.002, -0.016), Vector3(-90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.005, 0.0), Vector2(0.0, 0.012)], 4, [Color(0.95, 0.55, 0.2)])
    for sx in [-1, 1]:
        K.blob(st, Transform3D.IDENTITY, Vector3(sx * 0.011, 0.004, -0.009), Vector3(0.0035, 0.0035, 0.0035), 0.0, 1, Color(0.02, 0.02, 0.02), Color(0.02, 0.02, 0.02))
    K.add_mesh(_canary_head, "HeadMesh", K.finish(st), K.mat("tex_skin_64.png", 0.2, true))

## Like FDKLowPoly.loft but each band's normal follows the real surface
## slope (the kit loft points every face straight out sideways, so a belly
## seen from above caught no light and read as a black disc). Rings run
## top to bottom; the first ring gets a cap facing up.
func _loft_lit(st: SurfaceTool, rings: Array, cols: Array) -> void:
    var n := (rings[0] as PackedVector3Array).size()
    for i in range(rings.size() - 1):
        var r0: PackedVector3Array = rings[i]
        var r1: PackedVector3Array = rings[i + 1]
        var col: Color = cols[mini(i, cols.size() - 1)]
        for j in range(n):
            var k := (j + 1) % n
            var side := (r0[j] + r0[k] + r1[j] + r1[k]) * 0.25
            side.y = 0.0
            var nrm := (r0[k] - r0[j]).cross(r1[j] - r0[j]).normalized()
            if nrm.dot(side) < 0.0:
                nrm = -nrm
            FDKLowPoly.add_quad(st, r0[j], r0[k], r1[k], r1[j], nrm, col)
    var top: PackedVector3Array = rings[0]
    var c := Vector3.ZERO
    for p in top:
        c += p
    c /= top.size()
    for j in range(n):
        FDKLowPoly.add_tri(st, c, top[j], top[(j + 1) % n], Vector3.UP, cols[0])
func _waist_ring(y: float, rx: float, zf: float, zb: float) -> PackedVector3Array:
    var ring := PackedVector3Array()
    for j in range(16):
        var a := TAU * j / 16.0
        var s := sin(a)
        ring.append(Vector3(cos(a) * rx, y, s * (zb if s > 0.0 else zf)))
    return ring

func _build_hooks() -> void:
    # a straight leather tool rail buckled across the front of the belt,
    # with three steel rings hanging from it side by side
    var st := K.begin()
    var z := -RZF - 0.05
    K.rbox(st, K.T(Vector3(0, -0.03, z)), Vector3(0.38, 0.026, 0.008), 0.005, Color(0.36, 0.2, 0.1))
    for sx in [-1, 1]: # end straps back onto the belt
        K.rbox(st, K.T(Vector3(sx * 0.34, -0.01, z + 0.03)), Vector3(0.02, 0.03, 0.03), 0.005, Color(0.3, 0.17, 0.08))
    K.add_mesh(self, "ToolRail", K.finish(st, 6.0), K.mat("tex_door_paint_64.png", 0.25, true))
    for i in range(HOOK_X.size()):
        var hook := K.pivot(self, "Hook%d" % i, Vector3(HOOK_X[i], -0.05, z - 0.012))
        # swung forward onto the lap so ring and tool face the bowed head
        # (hanging straight down they would be seen end-on from above)
        hook.rotation.x = deg_to_rad(60.0)
        st = K.begin()
        K.rbox(st, K.T(Vector3(0, 0.0, 0)), Vector3(0.018, 0.02, 0.005), 0.004, Color(0.6, 0.6, 0.62))
        var ring: Array = []
        for j in range(13):
            var r := TAU * j / 12.0
            ring.append(Vector3(sin(r) * 0.036, -0.05 + cos(r) * 0.036, 0.0))
        K.tube(st, Transform3D.IDENTITY, ring, [0.008], 5, [Color(0.86, 0.87, 0.9)], false)
        K.add_mesh(hook, "Ring", K.finish(st, 6.0), K.mat("tex_chrome_64.png", 0.3, true))
        _hooks.append(hook)
## Which tool hangs on each hook ("" = the ring is empty).
func set_hung(ids: Array) -> void:
    for i in range(_hooks.size()):
        var id: String = str(ids[i]) if i < ids.size() else ""
        if id == _hung[i]:
            continue
        _hung[i] = id
        var hook: Node3D = _hooks[i]
        var old := hook.get_node_or_null("Tool")
        if old != null:
            hook.remove_child(old)
            old.queue_free()
        if id == "" or not ToolScenes.has(id):
            continue
        var tool: Node3D = (load(ToolScenes[id]) as PackedScene).instantiate()
        tool.name = "Tool"
        hook.add_child(tool)
        # hung upright facing the player, then sized so every tool reads at
        # the same height (TOOL_SIZE) and dangles just under its ring
        tool.rotation_degrees = {"knife": Vector3(90, 0, 0), "blender": Vector3(0, 90, 0), "big_saw": Vector3(90, 0, 90)}[id]
        var box := _local_aabb(tool)
        var ext := maxf(box.size.x, maxf(box.size.y, box.size.z))
        var s: float = (TOOL_SIZE * float({"knife": 1.4, "big_saw": 1.3}.get(id, 1.0))) / maxf(ext, 0.001) # the thin knife gets extra length
        tool.scale = Vector3.ONE * s
        box = _local_aabb(tool)
        tool.position = Vector3(-box.get_center().x, -0.085 - box.end.y, -box.get_center().z - 0.01)

const TOOL_SIZE := 0.2 ## m, largest side of a hung tool

## AABB of every mesh under n, in n's PARENT space (includes n's transform).
func _local_aabb(n: Node3D) -> AABB:
    var out := AABB()
    var first := true
    for mi in n.find_children("*", "MeshInstance3D", true, false):
        var mesh := (mi as MeshInstance3D).mesh
        if mesh == null:
            continue
        var xf: Transform3D = n.transform
        var p: Node = mi
        var chain := Transform3D.IDENTITY
        while p != n:
            chain = (p as Node3D).transform * chain
            p = p.get_parent()
        var b: AABB = (xf * chain) * mesh.get_aabb()
        out = b if first else out.merge(b)
        first = false
    return out
func hung() -> Array:
    return _hung.duplicate()

func hook_count() -> int:
    return _hooks.size()

## World point the player aims at to use hook i (the ring / the tool on it).
func hook_point(i: int) -> Vector3:
    var hook: Node3D = _hooks[i]
    return hook.global_transform * Vector3(0, -0.13, -0.01)

## The aimed hook swells a little (wordless: "this one"); -1 = none.
func set_focus(i: int) -> void:
    for k in range(_hooks.size()):
        (_hooks[k] as Node3D).scale = Vector3.ONE * (1.2 if k == i else 1.0)

func set_spray_count(cheap: int, expensive: int) -> void:
    var c := clampi(cheap, 0, 3)
    var e := clampi(expensive, 0, 3 - c)
    for i in range(3):
        var slot: Node3D = _cans[i]
        for ch in slot.get_children():
            ch.queue_free()
        if i < c + e:
            K.add_mesh(slot, "CanMesh", _can_mesh(i >= c), K.mat("tex_chrome_64.png", 0.35, true))

func set_canary(present: bool) -> void:
    _canary.visible = present

func canary_look(yaw_deg: float) -> void:
    _canary_head.rotation_degrees.y = yaw_deg

func set_canary_scared(on: bool) -> void:
    _scared = on

## A tool is hung on / taken off hook i: the ring swings a little.
func swing(i: int) -> void:
    if i >= 0 and i < _swing.size():
        _swing[i] = 1.0

var _swing: Array = [0.0, 0.0, 0.0]

func _process(delta: float) -> void:
    _time += delta
    for i in range(mini(_swing.size(), _hooks.size())):
        if _swing[i] > 0.0:
            _swing[i] = maxf(0.0, float(_swing[i]) - delta * 1.4)
            (_hooks[i] as Node3D).rotation.x = sin(_time * 14.0) * 0.32 * float(_swing[i]) * float(_swing[i])
    if _canary_head != null:
        var bob := sin(_time * (14.0 if _scared else 2.3)) * (0.006 if _scared else 0.002)
        _canary_head.position.y = 0.022 + bob
        _canary_head.rotation_degrees.z = sin(_time * 1.7) * (25.0 if _scared else 8.0)

func capture_setup() -> Dictionary:
    set_spray_count(2, 1)
    # first-person: eye above and slightly behind the waist, looking down
    return {"cam_pos": Vector3(0.03, 0.42, 0.06), "look_at": Vector3(0.0, -0.12, -0.1), "env": "dark", "fov": 70.0}