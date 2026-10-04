class_name FPArtHookup
extends Node

## Puts the main/art prop models where main.gd used to have placeholder
## shapes or nothing: tools in the hands, arm hairs on the left forearm, the
## belt and tumor bag at the waist, tumor-mutation hands, barrier models on
## every placed barrier and the mirror highlight. Visual only: it reads game
## state each frame and never changes it (tests drive the same logic).

const KnifeScene := preload("res://main/art/fp_knife.tscn")
const ScissorsScene := preload("res://main/art/fp_scissors.tscn")
const BlenderScene := preload("res://main/art/fp_blender.tscn")
const SawScene := preload("res://main/art/fp_big_saw.tscn")
const HairScene := preload("res://main/art/fp_arm_hair.tscn")
const BeltScene := preload("res://main/art/fp_belt.tscn")
const BagScene := preload("res://main/art/fp_tumor_bag.tscn")
const TumorScene := preload("res://main/art/fp_tumor.tscn")
const MutHandsScene := preload("res://main/art/fp_mutation_hands.tscn")
const BarrierScene := preload("res://main/art/fp_barrier_stages.tscn")
const MUT_KINDS := ["T2", "T3", "T4"] ## extra arm, palm mouth, swollen torso

var m: Node3D
var knife: Node3D
var scissors: Node3D
var blender: Node3D
var saw: Node3D
var arm_hair: Node3D
var belt: Node3D
var bag: Node3D
var hand_tumor: Node3D
var mut_hands: Node3D
var _rig: Node3D
var _hair_key := ""
var _mut_key := "__uninitialized__"
var _last_carry := 0.0
var _consumables := [{}, {}]

func setup(main: Node3D) -> void:
	m = main
	_rig = m.hands_rig
	knife = KnifeScene.instantiate()
	knife.name = "HeldKnife"
	knife.rotation_degrees = Vector3(-8, 0, 0)
	scissors = ScissorsScene.instantiate()
	scissors.name = "HeldScissors"
	scissors.scale = Vector3.ONE * 0.8
	blender = BlenderScene.instantiate()
	blender.name = "HeldBlender"
	blender.scale = Vector3.ONE * 0.55
	hand_tumor = TumorScene.instantiate()
	hand_tumor.name = "HeldTumor"
	hand_tumor.scale = Vector3.ONE * 0.45
	saw = SawScene.instantiate()
	saw.name = "HeldSaw"
	saw.scale = Vector3.ONE * 0.5
	arm_hair = HairScene.instantiate()
	arm_hair.name = "ArmHair"
	_attach_to_rig(_rig)
	# mutation hands: a second rig with the tumor-mutation parts, swapped in
	# once any of those mutations is owned
	mut_hands = MutHandsScene.instantiate()
	mut_hands.name = "MutationHands"
	mut_hands.visible = false
	m.player.camera.add_child(mut_hands)
	var r2: Node3D = mut_hands.call("rig")
	m.chewer.grab_started.connect(r2.on_grab_started)
	m.chewer.chew_progress.connect(r2.on_chew_progress)
	m.chewer.cell_torn.connect(r2.on_cell_torn)
	m.chewer.released.connect(r2.on_released)
	m.player.footstep_bob.connect(r2.apply_bob)
	m.chewer.cell_torn.connect(_on_torn)
	# waist: belt with sprays + canary pocket, tumor bag on the left hip
	belt = BeltScene.instantiate()
	belt.spray_cast_shadows = false
	belt.name = "Belt"
	belt.position = Vector3(0, 0.05, 0.02)
	m.player.add_child(belt)
	_tag_body(belt)
	bag = BagScene.instantiate()
	bag.name = "TumorBag"
	bag.position = Vector3(-0.2, -0.02, 0.06)
	bag.scale = Vector3.ONE * 0.8
	belt.add_child(bag)

func _attach_to_rig(rig: Node3D) -> void:
	var rw := rig.get_node("HandRight/Wrist") as Node3D
	var lw := rig.get_node("HandLeft/Wrist") as Node3D
	var lroot := rig.get_node("HandLeft") as Node3D
	_put(knife, rw, Vector3(0, -0.015, -0.06))
	_put(hand_tumor, rw, Vector3(0, -0.06, -0.08))
	_put(scissors, lw, Vector3(0, -0.012, -0.07))
	# the blender hangs in camera space low on the left, handle turned
	# outward, and the rig's left hand grips that handle (hold_left), so
	# the whole jar reads on screen instead of a corner under the wrist
	blender.rotation_degrees = Vector3(0, 180, 0)
	blender.set("tilt_dir", -1.0)
	var grip: Vector3 = (Basis(Vector3.UP, PI) * (blender.call("hand_grip") as Vector3)) * blender.scale.x
	# grip spot pushed out to the lower-left corner so the jar sits clear of
	# the flesh pile in the middle of the view (the left hand follows it)
	FDKHandsRig.HOLD_LEFT_POS = Vector3(-0.30, -0.10, -0.38)
	var hold: Vector3 = FDKHandsRig.HOLD_LEFT_POS
	_put(blender, rig, hold + Vector3(0.028, 0.01, -0.05) - grip)
	_put(saw, rig, Vector3(0, -0.2, -0.5))
	# arm hairs ride the left forearm (elbow at +0.34 behind the wrist)
	_put(arm_hair, lroot, Vector3(0, 0.0, 0.34))
	# Keep the original watch geometry throughout raise and release, on both
	# rig forearms so their existing mutation transforms still affect it.
	var hair_arm := arm_hair.get_node_or_null("Forearm") as MeshInstance3D
	if hair_arm != null:
		hair_arm.visible = false
		for side in ["HandLeft", "HandRight"]:
			var forearm := rig.get_node(side + "/Forearm") as MeshInstance3D
			forearm.mesh = hair_arm.mesh
			forearm.position = arm_hair.position
			if side == "HandLeft" and not forearm.has_meta("watch_skin"):
				forearm.material_override = forearm.material_override.duplicate()
				forearm.set_meta("watch_skin", true)
	_rig = rig
	if m._mirror_open:
		m.mirror.hand_root = lroot
		FPMirror.tag_layer(rig, FPMirror.HOLO_LAYER)

## Waist meshes go on main.BODY_LAYER (lit by the soft body fill, not the
## eye lamp). Tools hung later keep the default layer.
func _tag_body(n: Node) -> void:
	if n is VisualInstance3D and not (n is Light3D):
		(n as VisualInstance3D).layers = 1 << 11
	for c in n.get_children():
		_tag_body(c)

func _put(n: Node3D, parent: Node3D, at: Vector3) -> void:
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	parent.add_child(n)
	n.position = at
	m._tag_hands_layer(n, FPMirror.HOLO_LAYER if m._mirror_open else (FPMirrorReflection.HANDS_ROOM_LAYER if m._hands_in_room else 1))

func _on_torn(_p: Vector3) -> void:
	match m.progression.equipped():
		"knife":
			scissors.call("play_snip")
			m.scissors_snipped.emit()
		"big_saw":
			saw.call("play_stroke")
			m.saw_stroked.emit()

func _process(_delta: float) -> void:
	if m == null:
		return
	_sync_belt_posture(_delta)
	var prog: FPProgression = m.progression
	knife.visible = prog.hands.holds("knife")
	if knife.visible and _rig != null:
		var wrist: Node3D = _rig.get_node("HandLeft/Wrist" if prog.hands.left == "knife" else "HandRight/Wrist")
		if knife.get_parent() != wrist:
			_put(knife, wrist, Vector3(0, -0.015, -0.06))
	scissors.visible = prog.hands.right == "knife" and prog.hands.left == "" and m.carried_flesh <= 0.0
	blender.visible = prog.hands.holds("blender")
	if _rig != null:
		_rig.set("hold_left", blender.visible)
	saw.visible = prog.hands.holds("big_saw")
	for hand in range(2):
		var id := prog.hands.item(hand)
		for existing in _consumables[hand]:
			_consumables[hand][existing].visible = existing == id
		if id in ["spray_cheap", "spray_deep", "canary_feed", "barrier"]:
			if not _consumables[hand].has(id):
				var prop := FPConsumable.make(id)
				_consumables[hand][id] = prop
			var wrist: Node3D = _rig.get_node("HandLeft/Wrist" if hand == 0 else "HandRight/Wrist")
			var prop: Node3D = _consumables[hand][id]
			if prop.get_parent() != wrist:
				_put(prop, wrist, Vector3(0, -0.025, -0.06))
			prop.visible = true
	hand_tumor.visible = prog.tumor_in_hand()
	knife.call("set_bloody", m.hand_blood)
	blender.call("set_fill", clampf(m.carried_flesh / 40.0, 0.0, 1.0))
	blender.call("set_spin", m.blender_charge > 0.0 and m.carried_flesh > 0.0)
	if _last_carry > 0.0 and m.carried_flesh <= 0.0 and blender.visible and m.blender_charge < 1.0:
		blender.call("play_drink")
	_last_carry = m.carried_flesh
	_sync_hairs(prog)
	_sync_mutations(prog)
	var sp := prog.sprays
	belt.call("set_spray_count", sp.count_of_tier(FDKSprayCan.Tier.CHEAP) - int(prog.hands.holds("spray_cheap")), sp.count_of_tier(FDKSprayCan.Tier.DEEP) - int(prog.hands.holds("spray_deep")))
	belt.call("set_supplies", prog.canary_feed > 0 and not prog.hands.holds("canary_feed"), prog.barriers > 0 and not prog.hands.holds("barrier"))
	belt.call("set_canary", m.has_canary)
	belt.call("set_canary_scared", m.canary_urgency > 0.5)
	bag.visible = prog.has_bag
	var carried: Array = prog.tumors.get("_carried") if prog.tumors.get("_carried") != null else []
	var in_bag := prog.has_bag and carried.size() > 0
	if in_bag != bool(bag.call("has_tumor")):
		bag.call("set_tumor", in_bag, _variant(carried[carried.size() - 1] if in_bag else ""))
	_sync_barriers()
	var mir: Node3D = m.restroom.mirror_art
	if mir != null:
		mir.call("set_focus", false and (m.player.global_position.distance_to(m.mirror_point()) < 1.1 and m._looking_at(m.mirror_point(), 35.0, 1.6)))

static func _variant(kind: Variant) -> int:
	var k := FPProgression.TUMOR_KINDS.find(str(kind))
	return maxi(0, k) % 3

func _sync_hairs(prog: FPProgression) -> void:
	var key := "%d/%d/%d/%d" % [prog.hairs(FPProgression.COMMON), prog.hairs("core"), prog.hairs("mantle"), prog.hairs("surface")]
	if key == _hair_key:
		return
	var before := _hair_key
	_hair_key = key
	var biome := {"core": prog.hairs("core"), "mantle": prog.hairs("mantle"), "surface": prog.hairs("surface")}
	var total := prog.hairs(FPProgression.COMMON) + int(biome["core"]) + int(biome["mantle"]) + int(biome["surface"])
	var shown: int = arm_hair.call("hair_total")
	if before != "" and total < shown:
		arm_hair.call("drop_hairs", shown - total)
	else:
		arm_hair.call("set_hair", prog.hairs(FPProgression.COMMON), biome)

func _sync_mutations(prog: FPProgression) -> void:
	var all: Array = prog.all_mutations()
	var key := ",".join(all)
	if key != _mut_key:
		_mut_key = key
		var owned: Array = []
		for k in MUT_KINDS:
			if k in all:
				owned.append(k)
		for k in MUT_KINDS:
			mut_hands.call("set_mutation", k, k in owned)
		var r2: Node3D = mut_hands.call("rig")
		# hair mutations reshape both rigs; tumor parts need the second rig
		mut_hands.call("apply_all", [m.hands_rig, r2], all)
		var use_mut := not owned.is_empty()
		mut_hands.visible = true
		r2.visible = use_mut
		r2.set_process(use_mut)
		mut_hands.set_process(use_mut or "M27" in all)
		r2.pose_hook = m.hand_motions
		m.hands_rig.visible = not use_mut
		_attach_to_rig(r2 if use_mut else m.hands_rig)
	# M27: the trunk tip twitches toward a tumor within 10 m
	if "M27" in all:
		var dir := Vector3.ZERO
		var cam: Camera3D = m.player.camera
		var best := FPProgression.TRUNK_RADIUS
		for t in m.tumor_nodes:
			if is_instance_valid(t) and t.visible:
				var d: float = cam.global_position.distance_to(t.global_position)
				if d < best:
					best = d
					dir = cam.global_transform.basis.inverse() * (t.global_position - cam.global_position).normalized()
		mut_hands.call("set_trunk_target", dir)

## Mirrors hands state onto the mutation rig while it is the visible one.
func _physics_process(_d: float) -> void:
	if m == null or not mut_hands.visible:
		return
	var r2: FDKHandsRig = mut_hands.call("rig")
	r2.set_mutation(m.progression.mutation_amount())
	r2.set_carry(clampf(m.carried_flesh / 40.0, 0.0, 1.0) if m.carried_flesh > 0.0 else 0.0)

func _sync_barriers() -> void:
	for b in m.barrier_field.get_barriers():
		var art: Node3D = b.get_meta("art") if b.has_meta("art") else null
		if art == null:
			art = BarrierScene.instantiate()
			art.name = "BarrierArt"
			b.add_child(art)
			b.set_meta("art", art)
			var look: Vector3 = m.player.get_look_ray()[1]
			var flat := Vector3(look.x, 0, look.z)
			if flat.length() > 0.1:
				art.look_at(b.global_position - flat.normalized(), Vector3.UP)
			art.scale = Vector3.ONE * clampf(b.radius / 0.85, 0.5, 2.5)
			art.call("play_deploy")
			b.set_meta("art_stage", 0)
		if b.is_broken():
			if not b.has_meta("art_broken"):
				b.set_meta("art_broken", true)
				art.call("play_break")
			continue
		var st := mini(b.damage_step(), 3)
		if int(b.get_meta("art_stage")) != st:
			b.set_meta("art_stage", st)
			art.call("set_stage", st)

func _sync_belt_posture(_delta: float) -> void:
	if belt == null or not is_instance_valid(belt) or m == null or not is_instance_valid(m.player):
		return
	var pl: Node3D = m.player
	var pivot: Node3D = pl.get_node_or_null("CameraPivot")
	if pivot == null:
		return
	var feet_y := -0.9
	if pl.has_method("get_feet_position"):
		feet_y = pl.to_local(pl.call("get_feet_position")).y
	var eye_h: float = pivot.position.y - feet_y
	var h_scale: float = clampf(eye_h / 1.60, 0.45, 1.05)
	var base_waist_y: float = feet_y + 0.962 * h_scale

	var pitch: float = pivot.rotation.x
	var pitch_down: float = -minf(pitch, 0.0)
	var down_t: float = clampf(pitch_down / deg_to_rad(89.0), 0.0, 1.0)
	var bow: float = sin(down_t * PI * 0.5)

	var bob_base_y: float = float(pl.get("_pivot_base_y")) if pl.get("_pivot_base_y") != null else pivot.position.y
	var bob_y: float = pivot.position.y - bob_base_y
	var bob_x: float = pivot.position.x

	var waist_x: float = bob_x * 0.5
	var waist_y: float = base_waist_y + bob_y * 0.6 - 0.03 * bow * h_scale
	var waist_z: float = 0.02 + 0.04 * bow * h_scale

	belt.position = Vector3(waist_x, waist_y, waist_z)
	belt.rotation.x = -0.12 * bow
