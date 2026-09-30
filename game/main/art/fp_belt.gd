extends Node3D

## What the player sees looking down: the waist. Leather belt with a
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
const RX := 0.17
const RZ := 0.12
var _cans: Array = []
var _canary: Node3D
var _canary_head: Node3D
var _scared := false
var _time := 0.0
const HOOK_ANGLES := [-0.8, -1.3, -1.85]
const ToolScenes := {"knife": "res://main/art/fp_knife.tscn", "blender": "res://main/art/fp_blender.tscn", "big_saw": "res://main/art/fp_big_saw.tscn"}
var _hooks: Array = []
var _hung: Array = ["", "", ""]

func _ready() -> void:
    var st := K.begin()
    var cloth := Color(0.28, 0.3, 0.36)    # worn work trousers
    var cloth_d := Color(0.2, 0.21, 0.26)
    # trousers: a lofted hip + two leg stubs down to the knees
    var hip: Array = []
    for k in range(4):
        var y := -k * 0.07
        var ring := PackedVector3Array()
        for j in range(12):
            var a := TAU * j / 12.0
            ring.append(Vector3(cos(a) * RX * (1.0 + k * 0.04), y, sin(a) * RZ * (1.0 + k * 0.06)))
        hip.append(ring)
    FDKLowPoly.loft(st, hip, [cloth, cloth, cloth_d], true, false)
    for sx in [-1, 1]:
        K.tube(st, Transform3D.IDENTITY, [Vector3(sx * 0.09, -0.2, -0.01), Vector3(sx * 0.1, -0.38, -0.05), Vector3(sx * 0.1, -0.55, -0.09)], [0.085, 0.075, 0.068], 8, [cloth, cloth_d])
    # left front pocket opening (dark slit)
    K.quad(st, Transform3D.IDENTITY, Vector3(-0.13, -0.035, -RZ - 0.006), Vector3(-0.06, -0.03, -RZ - 0.012), Vector3(-0.07, -0.1, -RZ - 0.016), Vector3(-0.14, -0.1, -RZ - 0.008), Vector3(0, 0, -1), Color(0.07, 0.07, 0.09))
    K.add_mesh(self, "Trousers", K.finish(st, 5.0), K.mat("tex_fixture_128.png", 0.1, true))
    # belt band (a flattened loop just outside the waist)
    st = K.begin()
    var leather := Color(0.44, 0.26, 0.13)
    var loop: Array = []
    for j in range(17):
        var a := TAU * j / 16.0
        loop.append(Vector3(cos(a) * (RX + 0.008), 0.0, sin(a) * (RZ + 0.008)))
    K.tube(st, Transform3D.IDENTITY, loop, [0.032], 4, [leather], false, 0.25)
    # buckle
    K.rbox(st, K.T(Vector3(0, 0, -RZ - 0.018)), Vector3(0.032, 0.026, 0.006), 0.005, Color(0.7, 0.66, 0.5))
    K.rbox(st, K.T(Vector3(0, 0, -RZ - 0.024)), Vector3(0.02, 0.014, 0.003), 0.002, Color(0.2, 0.15, 0.1))
    K.add_mesh(self, "Belt", K.finish(st, 6.0), K.mat("tex_fixture_64.png", 0.25, true))
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
    _canary = K.pivot(self, "Canary", Vector3(-0.1, -0.03, -RZ - 0.02))
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

func _build_hooks() -> void:
    for i in range(HOOK_ANGLES.size()):
        var a: float = HOOK_ANGLES[i]
        var hook := K.pivot(self, "Hook%d" % i, Vector3(cos(a) * (RX + 0.045), -0.012, sin(a) * (RZ + 0.045)))
        hook.rotation.y = -a - PI * 0.5
        var st := K.begin()
        # leather tab riveted to the belt, then a steel ring hanging below it
        K.rbox(st, K.T(Vector3(0, -0.012, 0)), Vector3(0.02, 0.026, 0.006), 0.004, Color(0.24, 0.13, 0.07))
        var ring: Array = []
        for j in range(13):
            var r := TAU * j / 12.0
            ring.append(Vector3(sin(r) * 0.03, -0.062 + cos(r) * 0.03, -0.006))
        K.tube(st, Transform3D.IDENTITY, ring, [0.007], 5, [Color(0.86, 0.87, 0.9)], false)
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
        match id:
            "knife":   # hung by the handle, blade down
                tool.scale = Vector3.ONE * 1.1
                tool.rotation_degrees = Vector3(90, 0, 0)
                tool.position = Vector3(0, -0.09, -0.02)
            "blender": # clipped by its handle, jar hanging
                tool.scale = Vector3.ONE * 0.5
                tool.rotation_degrees = Vector3(0, 90, 0)
                tool.position = Vector3(0, -0.17, -0.05)
            "big_saw": # slung flat along the thigh
                tool.scale = Vector3.ONE * 0.36
                tool.rotation_degrees = Vector3(80, 0, 0)
                tool.position = Vector3(0, -0.14, -0.04)

func hung() -> Array:
    return _hung.duplicate()

func hook_count() -> int:
    return _hooks.size()

## World point the player aims at to use hook i (the ring / the tool on it).
func hook_point(i: int) -> Vector3:
    var hook: Node3D = _hooks[i]
    return hook.global_transform * Vector3(0, -0.07, -0.02)

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

func _process(delta: float) -> void:
    _time += delta
    if _canary_head != null:
        var bob := sin(_time * (14.0 if _scared else 2.3)) * (0.006 if _scared else 0.002)
        _canary_head.position.y = 0.022 + bob
        _canary_head.rotation_degrees.z = sin(_time * 1.7) * (25.0 if _scared else 8.0)

func capture_setup() -> Dictionary:
    set_spray_count(2, 1)
    # first-person: eye above and slightly behind the waist, looking down
    return {"cam_pos": Vector3(0.03, 0.42, 0.06), "look_at": Vector3(0.0, -0.12, -0.1), "env": "dark", "fov": 70.0}