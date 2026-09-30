class_name FPBeltSwap
extends RefCounted

## Look-down belt swap: bow the head past LOOK_DOWN_DEG and the belt's three
## tool hooks (knife, blender, big saw) come into view. Aiming at a hook
## lights the interact ring; fp_interact reaches down, hangs the held tool on
## its own hook and takes the aimed one (an empty ring = just put away). The
## hand dips for SWAP_TIME and the tool changes at the bottom of the dip.
## Rules (flesh in hand, one/two hands) stay in progression.equip. Tab /
## wheel / pad RB cycling is untouched.

const LOOK_DOWN_DEG := 55.0
const SLOTS := ["knife", "blender", "big_saw"] ## hook i holds SLOTS[i]
const AIM_DEG := 9.0
const REACH := 1.2
const SWAP_TIME := 0.75 ## reach down, hang, grab, bring up (fp_hand_motions "belt")
const DIP := 0.22 ## how far the hands drop toward the belt (m)
const HIP_TWIST := 0.9 ## rad the head may turn over the still hips

var m: Node3D
var swap_t := -1.0
var _want := ""
var _did := false
var _base_y := {}
var _anchored := false
var _hip_yaw := 0.0

func _init(main: Node3D) -> void:
	m = main

## No belt before the first vent trade: no hooks, no look-down swap.
func worn() -> bool:
	return m.progression != null and bool(m.progression.has_belt)

func looking_down() -> bool:
	return worn() and m.player.camera_pivot.rotation.x < -deg_to_rad(LOOK_DOWN_DEG)

func busy() -> bool:
	return swap_t >= 0.0

## What each hook shows: the owned tool unless it is in the hand.
func hung_ids() -> Array:
	var out: Array = []
	var prog = m.progression
	for id in SLOTS:
		out.append(id if prog.owns(id) and prog.equipped() != id else "")
	return out

## Index of the aimed hook, or -1.
func aimed_hook() -> int:
	var belt = m.art_hookup.belt if m.art_hookup != null else null
	if belt == null or not looking_down():
		return -1
	var ray: Array = m.player.get_look_ray()
	var best := -1
	var best_dot := cos(deg_to_rad(AIM_DEG))
	for i in range(int(belt.call("hook_count"))):
		var to: Vector3 = (belt.call("hook_point", i) as Vector3) - ray[0]
		if to.length() > REACH:
			continue
		var d: float = to.normalized().dot(ray[1])
		if d > best_dot:
			best_dot = d
			best = i
	return best

## What using hook i would equip: the tool on it, or bare hands for an empty
## ring while something is held. null = nothing to do.
func target_for(i: int) -> Variant:
	if i < 0:
		return null
	var hung: String = hung_ids()[i]
	if hung != "":
		return hung
	return "" if m.progression.equipped() != "" else null

func can_act() -> bool:
	return not busy() and target_for(aimed_hook()) != null

## Start the reach. Returns false when there is nothing to do or the rules
## refuse it (the hand still dips, and comes back with nothing).
func begin() -> bool:
	if busy():
		return false
	var want = target_for(aimed_hook())
	if want == null:
		return false
	if m.get("hand_motions") != null:
		m.hand_motions.play_belt(aimed_hook())
	_want = str(want)
	_did = false
	swap_t = 0.0
	for r in _rigs():
		_base_y[r] = r.position.y
	return true

## Instant version (tests and the bottom of the dip): hang + take.
func swap_now(id: String) -> bool:
	var before: String = m.progression.equipped()
	var ok: bool = m.equip_tool(id)
	if ok and before != id:
		m.emit_signal("belt_swapped", before, id)
	elif not ok:
		m.emit_signal("belt_refused")
	return ok and before != id

func tick(delta: float) -> void:
	if m.art_hookup != null and m.art_hookup.belt != null:
		var belt: Node3D = m.art_hookup.belt
		if bool(belt.get("worn")) != worn():
			belt.call("set_worn", worn())
		belt.call("set_hung", hung_ids())
		_twist_hips(belt, delta)
		belt.call("set_focus", aimed_hook() if not busy() and can_act() else -1)
	# bowed past LOOK_DOWN_DEG: both hands swing out so the belt is clear
	var ak := 0.0 if not worn() else clampf((-m.player.camera_pivot.rotation.x - deg_to_rad(LOOK_DOWN_DEG - 10.0)) / deg_to_rad(10.0), 0.0, 1.0)
	for r in _rigs():
		var rig = r.call("rig") if r.has_method("rig") else r
		if rig != null and "aside" in rig:
			rig.aside = move_toward(float(rig.aside), ak, delta * 5.0) if delta > 0.0 else ak
	if not busy():
		return
	swap_t += delta
	var k := clampf(swap_t / SWAP_TIME, 0.0, 1.0)
	var down := sin(k * PI)
	for r in _rigs():
		if _base_y.has(r):
			r.position.y = float(_base_y[r]) - DIP * down
	if k >= 0.5 and not _did:
		_did = true
		swap_now(_want)
	if k >= 1.0:
		for r in _rigs():
			if _base_y.has(r):
				r.position.y = float(_base_y[r])
		_base_y.clear()
		swap_t = -1.0

func _rigs() -> Array:
	var out: Array = []
	if m.hands_rig != null:
		out.append(m.hands_rig)
	if m.art_hookup != null and m.art_hookup.mut_hands != null:
		out.append(m.art_hookup.mut_hands)
	return out
## Bowed: the belt keeps its world yaw while the head turns (dragged along
## past HIP_TWIST). Upright: the hips ease back under the head.
func _twist_hips(belt: Node3D, delta: float) -> void:
	var yaw: float = m.player.rotation.y
	if looking_down():
		if not _anchored:
			_anchored = true
			_hip_yaw = yaw + belt.rotation.y
		var off := wrapf(_hip_yaw - yaw, -PI, PI)
		if absf(off) > HIP_TWIST:
			off = signf(off) * HIP_TWIST
			_hip_yaw = yaw + off
		belt.rotation.y = off
	else:
		_anchored = false
		belt.rotation.y = lerpf(belt.rotation.y, 0.0, clampf(delta * 6.0, 0.0, 1.0))