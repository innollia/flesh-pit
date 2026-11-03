class_name FPShadowBody
extends Node

## The player's shadow. The first-person view has no whole body (hands on the
## camera, a waist ring at the belt, legs that cast nothing), so the shadow
## casting lamp (the restroom ceiling light) threw only a floating belt ring. This
## keeps a full FPMirrorBody under the player as a SHADOWS_ONLY caster: never
## drawn by any camera (eye, mirror, Tab), only into the lamps' shadow maps.
## It stands on the real feet in the capsule's real posture (the reflection's
## pose_body), takes the owned mutations, and wears its own belt with the
## same cans, hooks, tools, canary and bag, so the belt shadow sits on the
## body's waist. The first-person belt casts nothing (fp_belt cast_body_shadow).

## Layers the caster sits on: the default layer (most lamps' cull masks) and
## the waist layer (the restroom ceiling light's cull mask, which skips the
## default layer); shadow-only instances are invisible to cameras.
const LAYERS := 1 | (1 << 11)

var body: FPMirrorBody
var main: Node3D
var player: Node3D
var _sig := ""

func setup(m: Node3D) -> void:
	main = m
	player = m.player
	body = FPMirrorBody.new()
	body.name = "ShadowBody"
	player.add_child(body)
	body.build()
	_shadow_only(body)
	get_tree().node_added.connect(_on_node_added)

func _shadow_only(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		(n as VisualInstance3D).layers = LAYERS
	for c in n.get_children():
		_shadow_only(c)

## Hung tools, rebuilt cans and mutation pieces added later are shadow-only too.
func _on_node_added(n: Node) -> void:
	if body != null and n is GeometryInstance3D and body.is_ancestor_of(n):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		(n as VisualInstance3D).layers = LAYERS

func _signature(prog: FPProgression) -> String:
	return "%s|%d|%s" % [str(prog.all_mutations()), prog.belly_bumps(), str(prog.has_belt)]

func _process(_delta: float) -> void:
	sync()

func sync() -> void:
	if body == null or main == null or not is_instance_valid(player):
		return
	var prog: FPProgression = main.progression
	body.visible = not bool(main.get("ended"))
	if not body.visible:
		return
	var sig := _signature(prog)
	if sig != _sig:
		_sig = sig
		body.apply(prog.all_mutations(), prog.belly_bumps())
		_shadow_only(body)
	# seated on the toilet / settling: the folded crouch is the sitting shape
	var seated := bool(main.get("_seated")) or bool(main.get("_settling"))
	FPMirrorReflection.pose_body(body, player, 1.0 if seated else -1.0)
	var belt := body._belt
	if belt == null:
		return
	belt.call("set_worn", prog.has_belt)
	belt.call("set_canary", bool(main.get("has_canary")))
	belt.call("set_spray_count", prog.sprays.count_of_tier(FDKSprayCan.Tier.CHEAP) - int(prog.hands.holds("spray_cheap")), prog.sprays.count_of_tier(FDKSprayCan.Tier.DEEP) - int(prog.hands.holds("spray_deep")))
	belt.call("set_supplies", prog.canary_feed > 0 and not prog.hands.holds("canary_feed"), prog.barriers > 0 and not prog.hands.holds("barrier"))
	if main.get("belt_swap") != null:
		belt.call("set_hung", main.belt_swap.hung_ids())
	var bag := belt.get_node_or_null("TumorBag") as Node3D
	if bag != null:
		bag.visible = prog.has_bag

## Every mesh of the shadow body casts and none is drawn.
func casters() -> Array:
	var out: Array = []
	for mi in body.find_children("*", "GeometryInstance3D", true, false):
		out.append(mi)
	return out
