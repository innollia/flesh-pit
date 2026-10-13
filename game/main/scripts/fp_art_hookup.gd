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
const K := preload("res://main/art/fp_art_kit.gd")

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
## Plugging the blender into a nerve (docs/spec/06-tools.md 2): the jar turns
## about the handle so its base swings out toward the nerve, and a yellow
## strand pulled out of the wall runs into the socket under the base.
## plug_offset is how far the handle moved; the left hand follows it
## (FPHandMotions.shape_pose).
const PLUG_TIME := 0.3
const PLUG_PUSH := 0.1 ## m the handle moves toward the nerve
const PLUG_TURN := 0.65 ## share of the turn that would aim the base at the nerve
const NERVE_COLORS := [Color(1.0, 0.93, 0.45), Color(0.9, 0.74, 0.2)] ## paler than FDKNerveStalk
var plug_k := 0.0
var plug_offset := Vector3.ZERO
var nerve_strand: MeshInstance3D
var _plug_world := Vector3.ZERO
var _blender_rest := Transform3D.IDENTITY
var _strand_t := 0.0

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
	nerve_strand = MeshInstance3D.new()
	nerve_strand.name = "NerveStrand"
	# self-lit pale yellow so the strand reads against a veined nerve wall
	var strand_mat := StandardMaterial3D.new()
	strand_mat.vertex_color_use_as_albedo = true
	strand_mat.emission_enabled = true
	strand_mat.emission = Color(0.55, 0.42, 0.05)
	strand_mat.roughness = 0.35
	strand_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	nerve_strand.material_override = strand_mat
	nerve_strand.visible = false
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
	# waist: belt with sprays + canary in briefs, tumor bag on the left hip
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
	_blender_rest = blender.transform
	plug_k = 0.0
	plug_offset = Vector3.ZERO
	_put(nerve_strand, rig, Vector3.ZERO)
	nerve_strand.visible = false
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
	_sync_plug(_delta)
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

func _sync_plug(delta: float) -> void:
	var tt: FPTissueTools = m.tissue_tools
	var on := tt != null and tt.plugged and blender.visible
	if not on and plug_k <= 0.0:
		return
	if on:
		_plug_world = tt.plug_point
	plug_k = move_toward(plug_k, 1.0 if on else 0.0, delta / PLUG_TIME)
	var e := plug_k * plug_k * (3.0 - 2.0 * plug_k)
	var rig := blender.get_parent() as Node3D
	# turn about the handle the hand holds, so the hand stays on it
	var grip: Vector3 = _blender_rest * (blender.call("hand_grip") as Vector3)
	var to_nerve := rig.to_local(_plug_world) - grip
	var d := to_nerve.normalized() if to_nerve.length() > 0.01 else Vector3.FORWARD
	var turn := Quaternion.IDENTITY.slerp(Quaternion(Vector3.DOWN, d), PLUG_TURN * e)
	plug_offset = d * PLUG_PUSH * e
	var b := Basis(turn)
	blender.transform = Transform3D(b * _blender_rest.basis, grip + plug_offset + b * (_blender_rest.origin - grip))
	_strand_t += delta
	_build_strand(rig.to_local(_plug_world), blender.transform * (blender.call("socket_point") as Vector3), e)

## The strand comes out of the wall and reaches the socket as e goes 0 -> 1;
## it sags a little and swells in a slow pulse while charging.
func _build_strand(wall: Vector3, socket: Vector3, e: float) -> void:
	nerve_strand.visible = e > 0.01
	if not nerve_strand.visible:
		return
	var tip := wall.lerp(socket, e)
	var sag := Vector3(0, -0.04 * e * minf(1.0, wall.distance_to(socket)), 0)
	var pts := []
	var radii := []
	var cols := []
	for i in range(7):
		var u := float(i) / 6.0
		var mid := wall.lerp(tip, 0.5) + sag
		pts.append(wall.lerp(mid, u).lerp(mid.lerp(tip, u), u))
		radii.append(lerpf(0.03, 0.012, u) * (1.0 + 0.2 * sin(_strand_t * 9.0 - u * 6.0)))
		cols.append(NERVE_COLORS[i % 2])
	var st := K.begin()
	K.tube(st, Transform3D.IDENTITY, pts, radii, 5, cols, true)
	nerve_strand.mesh = K.finish(st, 8.0)

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

	var crouch := 1.0 if bool(pl.get("_is_crouching")) else 0.0
	if pl.get("_pivot_base_y") != null:
		crouch = clampf((0.70 - float(pl.get("_pivot_base_y"))) / 0.80, 0.0, 1.0)

	# The waist follows capsule posture, never the head's pitch/bob or its
	# terrain correction. The head moves when looking down; holsters remain
	# fixed to the body during WASD instead of acquiring their own velocity.
	belt.position = Vector3(0.0, 0.05 - 0.48 * crouch, 0.02)
	belt.rotation = Vector3.ZERO
	if m.is_pulling_canary() and m.canary_pull != null:
		var prone: float = m.canary_pull.prone()
		belt.position = belt.position.lerp(Vector3(0, -m.player.config.stand_height * 0.5 + 0.22, 0.52), prone)
		belt.rotation.x = -PI * 0.5 * prone
