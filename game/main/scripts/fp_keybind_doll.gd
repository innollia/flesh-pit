extends Node

## The key screen's protagonists (fp_keybind_menu.gd): the player's own body
## (FPMirrorBody, wearing the mutations they have) stands six times on a
## turntable in a low-res view of its own. The one in front is lit and loops
## the chosen action's motion with the game's own props (knife, tumor,
## barrier, torn flesh, lever); the previous and next actions' bodies wait
## in the dark at the sides, by the arrows, looking on. Stepping turns the
## table and the next body walks into the light. Bodies are posed through
## their public joints after their own set_posture each frame; nothing in
## FPMirrorBody changes.

const VIEW := Vector2i(480, 250)
const SLOTS := 6
const STEP := TAU / SLOTS
const RING := 1.5
const FLESH_TEX := "res://addons/flesh_dig_kit/textures/tex_torn_chunk_128.png"
## How far the front body turns for each action (deg): the working hand
## toward the camera (the body is the mirror model: its right hand is on +X,
## so a negative turn brings the right side near) and the reach side-on.
const TURN := {
	"fp_vomit": -40.0, "fp_interact": -50.0, "fp_carry": -40.0, "fp_barrier": -45.0,
	"fp_eat_tumor": -40.0, "fp_tool_next": -35.0, "fp_tool_prev": 35.0,
	"fp_mutate": 40.0, "fdk_eat": 50.0, "fp_pick": -50.0,
}

var view: SubViewport
var camera: Camera3D
var table: Node3D
## Per body: {body, action, t, w}. w blends the action's motion in (front).
var slots: Array = []
var order: Array = []
var index := 0
var ring_angle := 0.0
var ring_target := 0.0
## The body being posed (the pose helpers act on it) and its blend.
var body: FPMirrorBody
var _t := 0.0
var _w := 0.0
var _front: FPMirrorBody
var _knife_r: Node3D
var _knife_l: Node3D
var _tumor: Node3D
var _barrier: Node3D
var _lump_r: MeshInstance3D
var _lump_l: MeshInstance3D
var _pile: MeshInstance3D
var _wall: MeshInstance3D
var _lever: Node3D
var _lever_rod: Node3D
var _drops: Array = []
var _drop_mesh: Mesh
var _last_heave := -1

func build() -> SubViewport:
	view = SubViewport.new()
	view.name = "DollView"
	view.own_world_3d = true
	view.transparent_bg = true
	view.size = VIEW
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.36, 0.36)
	env.environment.ambient_light_energy = 0.22
	view.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, -35, 0)
	key.light_color = Color(1.0, 0.86, 0.76)
	key.light_energy = 0.12
	view.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 150, 0)
	rim.light_color = Color(1.0, 0.45, 0.38)
	rim.light_energy = 0.45
	view.add_child(rim)
	# the light the front body steps into
	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.88, 0.78)
	spot.light_energy = 12.0
	spot.spot_range = 7.0
	spot.spot_angle = 13.0
	spot.spot_attenuation = 0.6
	view.add_child(spot)
	spot.look_at_from_position(Vector3(0.4, 3.0, 2.2), Vector3(0.0, 0.8, 0.0))
	camera = Camera3D.new()
	camera.fov = 34.0
	view.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 1.08, 3.6), Vector3(0.0, 0.92, -0.3))
	camera.current = true
	table = Node3D.new()
	table.name = "Turntable"
	view.add_child(table)
	for i in range(SLOTS):
		var b := FPMirrorBody.new()
		b.name = "Protagonist%d" % i
		table.add_child(b)
		b.build() # idempotent; built here even before the tree runs
		slots.append({"body": b, "action": "", "t": 0.0, "w": 0.0})
	_build_props()
	_place(0.0)
	return view

## Wear what the player has now: mutations, belly bumps, the belt.
func dress(prog: Object) -> void:
	if prog == null:
		return
	for s in slots:
		var b: FPMirrorBody = s.body
		b.apply(prog.all_mutations(), prog.belly_bumps())
		if b._belt != null:
			b._belt.call("set_worn", prog.has_belt)

## The actions on the table, in order.
func set_actions(p_order: Array) -> void:
	order = p_order.duplicate()

## Turn the table so action `i` is in front, the short way round. `snap`
## jumps there without turning (opening the screen).
func show_index(i: int, snap: bool = false) -> void:
	if order.is_empty():
		return
	var n := order.size()
	var d := posmod(i - index + n / 2, n) - n / 2
	index = posmod(i, n)
	ring_target -= d * STEP
	if snap:
		ring_angle = ring_target
	_assign()

## The action now in front.
func front_action() -> String:
	return order[index] if not order.is_empty() else ""

func turning() -> bool:
	return absf(ring_angle - ring_target) > 0.02

## Slot offset of body j from the front once the turn is done.
func _offset(j: int) -> int:
	return roundi(wrapf(j * STEP + ring_target, -PI, PI) / STEP)

func _assign() -> void:
	if slots.is_empty():
		return
	var n := order.size()
	for j in range(SLOTS):
		var a: String = order[posmod(index + _offset(j), n)] if n > 0 else ""
		if slots[j].action != a:
			slots[j].action = a
			slots[j].w = 0.0
			slots[j].t = 0.0

func _place(_delta: float) -> void:
	for j in range(SLOTS):
		var world := wrapf(j * STEP + ring_angle, -PI, PI)
		var b: FPMirrorBody = slots[j].body
		b.position = Vector3(sin(world) * RING, 0.0, (cos(world) - 1.0) * RING)
		b.visible = absf(world) < 1.75

func _blob(r: Vector3, seed: int, tint: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	FDKLowPoly.add_blob(st, Vector3.ZERO, r, 0.35, seed, tint, tint.darkened(0.15))
	var mi := MeshInstance3D.new()
	mi.mesh = FDKLowPoly.with_box_uvs(st.commit(), 10.0)
	mi.material_override = FDKPs1Material.get_material(FLESH_TEX, 1.0, true, 0.8, 0.4)
	return mi

func _build_props() -> void:
	var knife_scene: PackedScene = load("res://main/art/fp_knife.tscn")
	_knife_r = knife_scene.instantiate()
	_knife_l = knife_scene.instantiate()
	_tumor = (load("res://main/art/fp_tumor.tscn") as PackedScene).instantiate()
	_barrier = (load("res://main/art/fp_barrier_stages.tscn") as PackedScene).instantiate()
	_lump_r = _blob(Vector3(0.045, 0.035, 0.04), 61, Color(1, 1, 1))
	_lump_l = _blob(Vector3(0.045, 0.035, 0.04), 62, Color(1, 1, 1))
	_pile = _blob(Vector3(0.11, 0.06, 0.09), 63, Color(1, 1, 1))
	view.add_child(_pile)
	# the flesh wall the hands tear at
	_wall = _blob(Vector3(0.34, 0.42, 0.16), 64, Color(0.85, 0.7, 0.7))
	# a restroom lever for 상호작용
	_lever = Node3D.new()
	var chrome := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_chrome_64.png", 1.0, false, 0.6, 0.3)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.16, 0.05)
	base.mesh = bm
	base.material_override = chrome
	_lever.add_child(base)
	_lever_rod = Node3D.new()
	_lever.add_child(_lever_rod)
	var rod := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.012
	rm.bottom_radius = 0.012
	rm.height = 0.22
	rm.radial_segments = 6
	rod.mesh = rm
	rod.material_override = chrome
	rod.position = Vector3(0, 0.11, 0.03)
	_lever_rod.add_child(rod)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.03
	km.height = 0.06
	km.radial_segments = 6
	km.rings = 3
	knob.mesh = km
	knob.material_override = FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_door_paint_64.png", 1.0, false, 0.4, 0.5)
	knob.position = Vector3(0, 0.23, 0.03)
	_lever_rod.add_child(knob)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	FDKLowPoly.add_blob(st, Vector3.ZERO, Vector3.ONE, 0.3, 65, Color(0.66, 0.7, 0.24), Color(0.56, 0.6, 0.18))
	_drop_mesh = st.commit()

## The props live on the body in front.
func _give_props(b: FPMirrorBody) -> void:
	if b == _front:
		return
	_front = b
	var to_hand := {_knife_r: "hand_r", _knife_l: "hand_l", _tumor: "hand_r", _lump_r: "hand_r", _lump_l: "hand_l"}
	for prop in to_hand:
		_move_to(prop, b.sub_node(to_hand[prop]))
	for prop in [_barrier, _wall, _lever]:
		_move_to(prop, b)
	for k in [_knife_r, _knife_l]:
		k.position = Vector3(0, 0.05, 0.02)
		k.rotation_degrees = Vector3(90, 0, 0)
		k.scale = Vector3.ONE * 0.8
	_tumor.position = Vector3(0, 0.07, 0.04)
	_tumor.scale = Vector3.ONE * 0.45
	for l in [_lump_r, _lump_l]:
		l.position = Vector3(0, 0.07, 0.035)

func _move_to(prop: Node3D, parent: Node3D) -> void:
	if prop.get_parent() == parent:
		return
	if prop.get_parent() != null:
		prop.get_parent().remove_child(prop)
	parent.add_child(prop)

func _hide_props() -> void:
	for n in [_knife_r, _knife_l, _tumor, _barrier, _lump_r, _lump_l, _pile, _wall, _lever]:
		(n as Node3D).visible = false

# --- posing (each scaled by _w: 0 = standing, 1 = the full motion) ------------

func _posture(crouch: float, pitch: float) -> void:
	body.set_posture(crouch * _w, 0.0, 0.0, pitch * _w)

## Arm `s` ("r"/"l"): raised forward (rad), out to the side, elbow bent.
func _arm(s: String, fwd: float, out: float, elbow: float) -> void:
	var sgn := 1.0 if s == "r" else -1.0
	var upper := body.sub_node("upper_" + s)
	upper.basis = Basis(Vector3.RIGHT, -fwd * _w) * Basis(Vector3.BACK, sgn * out * _w) * upper.basis
	var fore := body.part_node("right_hand" if s == "r" else "left_hand")
	fore.basis = Basis(Vector3.RIGHT, -elbow * _w) * fore.basis

func _wrist(s: String, pitch: float) -> void:
	var hand := body.sub_node("hand_" + s)
	hand.basis = Basis(Vector3.RIGHT, pitch * _w) * hand.basis

## Fold forward at the waist.
func _bend(a: float) -> void:
	var pivot := Vector3(0, 0.97, 0)
	var turn := Transform3D(Basis(Vector3.RIGHT, a * _w), pivot) * Transform3D(Basis.IDENTITY, -pivot)
	for p in ["belly", "chest", "arms", "neck", "face"]:
		var n := body.part_node(p)
		n.transform = turn * n.transform

func _nod(a: float) -> void:
	var face := body.part_node("face")
	face.basis = Basis(Vector3.RIGHT, a * _w) * face.basis

static func _win(ph: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, ph) * (1.0 - smoothstep(c, d, ph))

func _process(delta: float) -> void:
	if slots.is_empty() or not view.is_inside_tree():
		return
	ring_angle = lerpf(ring_angle, ring_target, 1.0 - exp(-delta * 7.0))
	if not turning():
		ring_angle = ring_target
	_place(delta)
	_hide_props()
	for j in range(SLOTS):
		var s: Dictionary = slots[j]
		var front := _offset(j) == 0
		var world := wrapf(j * STEP + ring_angle, -PI, PI)
		# the front body starts its motion once it is in the light
		var target_w := 1.0 if front and absf(world) < 0.25 else 0.0
		s.w = move_toward(s.w, target_w, delta * 3.0)
		s.t = s.t + delta if s.w > 0.0 else 0.0
		body = s.body
		_t = s.t
		_w = s.w
		# in line they turn a little toward the one in the light
		body.rotation.y = lerpf(-world * 0.45, deg_to_rad(float(TURN.get(s.action, -30.0))), _w)
		if front:
			_give_props(body)
		if _w <= 0.0:
			_wait(world)
			continue
		match s.action:
			"fp_vomit": _vomit()
			"fp_interact": _interact()
			"fp_carry": _carry()
			"fp_barrier": _place_barrier()
			"fp_eat_tumor": _eat_tumor()
			"fp_tool_next": _swap_tool("r")
			"fp_tool_prev": _swap_tool("l")
			"fp_mutate": _watch_forearm()
			"fdk_eat": _tear("l")
			"fp_pick": _tear("r")
			_: _wait(world)
	_step_drops(delta)

## Standing in line: breathing, weight shifting, the head turned toward the
## one in the light.
func _wait(world: float) -> void:
	_w = 1.0
	var t := Time.get_ticks_msec() / 1000.0 + world * 3.0
	body.set_posture(0.0, 0.0, 0.0, 0.0)
	_bend(0.02 * sin(t * 1.6))
	var face := body.part_node("face")
	face.basis = Basis(Vector3.UP, -signf(world) * 0.4) * face.basis
	for s in ["r", "l"]:
		_arm(s, 0.05, 0.04 + 0.02 * sin(t * 1.1), 0.15)

func _vomit() -> void:
	var ph := fmod(_t, 2.4) / 2.4
	var heave := 0.0
	var k := -1
	for i in range(3):
		var c := 0.35 + 0.15 * i
		var h := exp(-pow((ph - c) / 0.035, 2.0))
		if h > heave:
			heave = h
		if absf(ph - c) < 0.02:
			k = i
	_posture(0.15, -0.5)
	_bend(0.42 + 0.16 * heave)
	_nod(0.25 + 0.15 * heave)
	for s in ["r", "l"]:
		_arm(s, 0.35, 0.14, 1.5 + 0.2 * heave)
	if _w > 0.9 and k >= 0 and k != _last_heave:
		_last_heave = k
		var mouth := body.part_node("face").global_transform * Vector3(0, -0.06, 0.09)
		for j in range(4):
			_drops.append({"pos": mouth, "vel": body.global_basis * Vector3((j - 1.5) * 0.12, -0.2, 0.7 + 0.1 * j), "life": 0.9})
	if ph < 0.1:
		_last_heave = -1

func _interact() -> void:
	var ph := fmod(_t, 2.2) / 2.2
	var reach := _win(ph, 0.0, 0.28, 0.78, 1.0)
	var pull := _win(ph, 0.35, 0.55, 0.78, 1.0)
	_posture(0.0, -0.1)
	_arm("r", lerpf(0.05, 1.35, reach) - 0.55 * pull, 0.08 * reach, lerpf(0.15, 0.3, reach) + 0.5 * pull)
	_lever.visible = _w > 0.6
	_lever.position = Vector3(0.22, 1.12, 0.62)
	_lever_rod.rotation.x = 0.5 - 1.1 * pull

func _carry() -> void:
	var ph := fmod(_t, 2.6) / 2.6
	var lift := _win(ph, 0.15, 0.5, 0.82, 1.0)
	_posture(0.45 * (1.0 - lift), -0.45)
	for s in ["r", "l"]:
		_arm(s, 0.42 + 0.22 * lift, 0.06, 1.25 + 0.25 * lift)
		_wrist(s, 0.3)
	_pile.visible = _w > 0.6
	var a := body.sub_node("hand_r").global_position
	var b := body.sub_node("hand_l").global_position
	_pile.global_position = (a + b) * 0.5 + Vector3(0, 0.05, 0)
	_pile.global_basis = body.global_basis

func _place_barrier() -> void:
	var ph := fmod(_t, 3.0) / 3.0
	var push := smoothstep(0.15, 0.4, ph)
	var spread := smoothstep(0.42, 0.62, ph)
	var gone := smoothstep(0.88, 0.98, ph)
	_posture(0.2 * push, -0.1)
	for s in ["r", "l"]:
		_arm(s, lerpf(0.9, 1.35, push) - 0.6 * spread, 0.12, lerpf(1.0, 0.35, push) + 0.4 * spread)
	_barrier.visible = _w > 0.6 and gone < 0.99
	_barrier.position = Vector3(0, 0.75 - 0.2 * spread, lerpf(0.35, 0.85, push))
	_barrier.call("set_expand", lerpf(0.15, 1.0, spread))
	_barrier.scale = Vector3.ONE * 0.6 * (1.0 - gone)

func _eat_tumor() -> void:
	var ph := fmod(_t, 2.8) / 2.8
	var bring := _win(ph, 0.08, 0.35, 0.86, 1.0)
	var chewing := smoothstep(0.35, 0.86, ph)
	_posture(0.0, 0.0)
	_arm("r", lerpf(0.15, 0.62, bring), 0.2 * bring, lerpf(0.3, 2.25, bring))
	_wrist("r", -0.4 * bring)
	_nod(-0.08 * bring + (sin(_t * 14.0) * 0.05 if bring > 0.95 else 0.0))
	_tumor.visible = _w > 0.6 and ph < 0.86
	_tumor.scale = Vector3.ONE * 0.45 * (1.0 - 0.7 * chewing)

func _swap_tool(s: String) -> void:
	var ph := fmod(_t, 2.2) / 2.2
	var down := _win(ph, 0.05, 0.28, 0.4, 0.58)
	var up := _win(ph, 0.45, 0.7, 0.9, 1.0)
	_posture(0.0, -0.5 * down)
	_nod(0.35 * down)
	_arm(s, -0.2 * down + 0.95 * up, 0.28 * down + 0.06, 0.25 * down + 1.15 * up)
	var knife := _knife_r if s == "r" else _knife_l
	knife.visible = _w > 0.6 and ph > 0.4 and ph < 0.95

func _watch_forearm() -> void:
	var ph := fmod(_t, 3.0) / 3.0
	var raise := _win(ph, 0.05, 0.3, 0.86, 1.0)
	_posture(0.0, -0.6 * raise)
	_nod(0.4 * raise)
	_arm("l", 0.95 * raise, -0.2 * raise, 1.75 * raise)
	_arm("r", 0.75 * raise, -0.05 * raise, 1.55 * raise + 0.12 * sin(_t * 9.0) * raise)

func _tear(s: String) -> void:
	var ph := fmod(_t, 1.8) / 1.8
	var reach := smoothstep(0.0, 0.3, ph)
	var tear := smoothstep(0.42, 0.56, ph)
	var back := 1.0 - smoothstep(0.84, 1.0, ph)
	var sgn := 1.0 if s == "r" else -1.0
	_posture(0.0, -0.05)
	_arm(s, (lerpf(0.2, 1.4, reach) - 0.75 * tear) * back, 0.05, (lerpf(0.4, 0.12, reach) + 1.25 * tear) * back)
	_wall.visible = _w > 0.6
	_wall.position = Vector3(sgn * 0.16, 1.32, 0.95)
	var lump := _lump_r if s == "r" else _lump_l
	lump.visible = _w > 0.6 and tear > 0.2 and back > 0.3

func _step_drops(delta: float) -> void:
	var keep: Array = []
	for d in _drops:
		d.life -= delta
		if d.life <= 0.0:
			if d.has("mi"):
				(d.mi as Node).queue_free()
			continue
		d.vel.y -= 9.8 * delta
		d.pos += d.vel * delta
		if not d.has("mi"):
			var mi := MeshInstance3D.new()
			mi.mesh = _drop_mesh
			mi.material_override = FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_membrane_128.png", 1.0, true, 1.0, 0.2)
			mi.scale = Vector3.ONE * 0.025
			view.add_child(mi)
			d["mi"] = mi
		(d.mi as Node3D).global_position = d.pos
		keep.append(d)
	_drops = keep
