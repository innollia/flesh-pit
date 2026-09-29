class_name FPProgression
extends RefCounted

## Game-side progression state (design-core 2/4/5/6/8): teeth (money), arm
## hairs (mutation points: common + per-biome pools), ~30 mutations, tumor
## mutations, tools with one/two-handed rules, consumables, vent stock and
## the death drop payload. Pure data/logic; main.gd wires it to the world.

const SAVE_VERSION := 2

const BIOME_CORE := "core"
const BIOME_MANTLE := "mantle"
const BIOME_SURFACE := "surface"
const BIOMES: Array[String] = [BIOME_CORE, BIOME_MANTLE, BIOME_SURFACE]
const COMMON := FDKMutationTree.COMMON
const TUMOR_POOL := "tumor"

## design-core 6: shell multiplier core x1, mantle x2, surface x3.
const SHELL_MULTIPLIER := {BIOME_CORE: 1, BIOME_MANTLE: 2, BIOME_SURFACE: 3}

## Teeth per flesh unit vomited into the toilet. One expedition fills about
## 100 flesh, so "one expedition's earnings" is about 8 teeth = 2 handfuls.
const TEETH_PER_FLESH := 0.08
const EXPEDITION_TEETH := 8
## One handful scooped from the tank and placed at the vent.
const HANDFUL_TEETH := 4
## 04-economy 2: hairs per settled flesh (after the shell multiplier).
## Fractions carry over to the next settlement.
const FLESH_PER_BIOME_HAIR := 50.0
const FLESH_PER_COMMON_HAIR := 150.0

## design-core 5 price guide, in expeditions' earnings. Items without a guide
## price (canary feed, tumor bag) are prototype picks, see the report.
const PRICE_UNITS := {
	"barrier": 0.5,
	"spray_cheap": 1.0,
	"knife": 2.0,
	"spray_deep": 3.0,
	"blender": 5.0,
	"big_saw": 10.0,
	"canary_feed": 0.5,
	"tumor_bag": 2.0,
}
## Stock unlocks with the deepest shell reached (0 core, 1 mantle, 2 surface).
const UNLOCK_SHELL := {
	"barrier": 0, "spray_cheap": 0, "knife": 0, "canary_feed": 0,
	"spray_deep": 1, "blender": 1, "tumor_bag": 1,
	"big_saw": 2,
}
const VENT_MAX_OFFER := 3

const MAX_BARRIERS := 3
const MAX_CANARY_FEED := 3

## Tumor kinds: two per shell. Throwing each one intact fills the codex.
const TUMOR_KINDS: Array[String] = ["core_knot", "core_bulb", "mantle_coil", "mantle_sac", "surface_star", "surface_ear"]
const TUMOR_TOOTH_PAYOUT := 24 ## "a large pile of teeth" = 3 expeditions
const TUMOR_EAT_POINTS := 1
const TUMOR_MUTATION_COST := 1
## Large, obvious tumor mutations, granted at random (design-core 6).
const TUMOR_MUTATIONS: Array[String] = ["extra_arm", "palm_mouth", "swollen_torso", "back_eyes", "split_jaw", "rib_fan"]

## Body parts the mirror can hover (design-core 5).
const PARTS: Array[String] = ["left_hand", "right_hand", "jaw", "torso", "legs"]

var tools: FDKToolKit = FDKToolKit.new()
var mutation_tree: FDKMutationTree = FDKMutationTree.new()
var tumors: FDKTumorKit = FDKTumorKit.new()
var vent: FDKVentShop = FDKVentShop.new()
var sprays: FDKSprayCan.Inventory = FDKSprayCan.Inventory.new()

## part -> Array of mutation ids, and id -> {part, hand, pool, group}
var mutation_info: Dictionary = {}

var teeth: int = 0 ## in the toilet tank
var teeth_in_hand: int = 0 ## scooped handful(s), not yet placed at the vent
var barriers: int = 0 ## carried, unplaced
var canary_feed: int = 0
var has_bag: bool = false
var tumor_mutations: Array[String] = []
var deepest_shell: int = 0
## Hairs for flesh currently in the stomach: they only grow on the arm when
## the flesh is vomited into the toilet (or a rest point).
## Keys: COMMON + each biome. Values: weighted flesh units (unit x shell
## multiplier) still in the stomach; they turn into hairs on settling.
var pending_hairs: Dictionary = {}
## Leftover weighted flesh below one hair, carried to the next settlement.
var hair_carry: Dictionary = {}
## Junk the vent being pushed out and the player took (no use).
var junk_taken: int = 0
var _rng_state: int = 20260929

func _init() -> void:
	tools.define_tool("knife", FDKToolKit.Hand.RIGHT, false)
	tools.define_tool("blender", FDKToolKit.Hand.LEFT, false)
	tools.define_tool("big_saw", FDKToolKit.Hand.RIGHT, true)
	for id in PRICE_UNITS.keys():
		vent.define_item(id, price_for(id), float(UNLOCK_SHELL.get(id, 0)))
	tumors.bag_capacity = 2 if has_bag else 1
	_define_mutations()
	_clear_pending()
	hair_carry = {COMMON: 0.0}
	for b in BIOMES:
		hair_carry[b] = 0.0

func _clear_pending() -> void:
	pending_hairs = {COMMON: 0}
	for b in BIOMES:
		pending_hairs[b] = 0

# --- mutations -------------------------------------------------------------

func _def(id: String, pool: String, part: String, hand: String, group: String, cost: int, alt: Array[String] = []) -> void:
	mutation_tree.define_node(id, [] as Array[String], pool, cost, alt)
	mutation_info[id] = {"part": part, "hand": hand, "pool": pool, "group": group}

## design-core 6: ~30 mutations, 6 common + 7 per biome + 3 combination.
## Grouping only: no prerequisites. Left hand = blender/tool hand, right
## hand = tearing hand.
func _define_mutations() -> void:
	_def("thick_skin", COMMON, "torso", "", "common", 20)
	_def("wide_jaw", COMMON, "jaw", "", "common", 25)
	_def("calloused_soles", COMMON, "legs", "", "common", 20)
	_def("long_nails", COMMON, "right_hand", "right", "common", 25)
	_def("heavy_gut", COMMON, "torso", "", "common", 35)
	_def("thick_wrist", COMMON, "left_hand", "left", "common", 30)
	# compressive (core): soft, spongy, absorbing
	_def("core_padded_palm", BIOME_CORE, "right_hand", "right", "compressive", 15)
	_def("core_sponge_knuckles", BIOME_CORE, "left_hand", "left", "compressive", 15)
	_def("core_soft_throat", BIOME_CORE, "jaw", "", "compressive", 20)
	_def("core_fat_heels", BIOME_CORE, "legs", "", "compressive", 20)
	_def("core_swollen_belly", BIOME_CORE, "torso", "", "compressive", 30)
	_def("core_suction_fingers", BIOME_CORE, "right_hand", "right", "compressive", 35)
	_def("core_press_forearm", BIOME_CORE, "left_hand", "left", "compressive", 40)
	# contractile (mantle): fibrous, gripping, pulling
	_def("mantle_fiber_grip", BIOME_MANTLE, "right_hand", "right", "contractile", 30)
	_def("mantle_cord_tendons", BIOME_MANTLE, "left_hand", "left", "contractile", 30)
	_def("mantle_clench_jaw", BIOME_MANTLE, "jaw", "", "contractile", 40)
	_def("mantle_coil_calves", BIOME_MANTLE, "legs", "", "contractile", 40)
	_def("mantle_banded_ribs", BIOME_MANTLE, "torso", "", "contractile", 60)
	_def("mantle_hook_thumb", BIOME_MANTLE, "right_hand", "right", "contractile", 70)
	_def("mantle_winch_arm", BIOME_MANTLE, "left_hand", "left", "contractile", 80)
	# nerve (surface): twitchy, sensing
	_def("surface_twitch_fingers", BIOME_SURFACE, "right_hand", "right", "nerve", 45)
	_def("surface_feeler_hairs", BIOME_SURFACE, "left_hand", "left", "nerve", 45)
	_def("surface_buzzing_teeth", BIOME_SURFACE, "jaw", "", "nerve", 60)
	_def("surface_spring_knees", BIOME_SURFACE, "legs", "", "nerve", 60)
	_def("surface_glow_spine", BIOME_SURFACE, "torso", "", "nerve", 90)
	_def("surface_shock_palm", BIOME_SURFACE, "right_hand", "right", "nerve", 100)
	_def("surface_eel_wrist", BIOME_SURFACE, "left_hand", "left", "nerve", 120)
	# combination: payable from either contributing pool
	_def("combo_core_mantle", BIOME_CORE, "torso", "", "combination", 60, [BIOME_CORE, BIOME_MANTLE] as Array[String])
	_def("combo_mantle_surface", BIOME_MANTLE, "right_hand", "right", "combination", 90, [BIOME_MANTLE, BIOME_SURFACE] as Array[String])
	_def("combo_core_surface", BIOME_CORE, "left_hand", "left", "combination", 90, [BIOME_CORE, BIOME_SURFACE] as Array[String])

func mutation_count() -> int:
	return mutation_info.size()

func mutations_for_part(part: String) -> Array[String]:
	var out: Array[String] = []
	for id in mutation_info.keys():
		if mutation_info[id]["part"] == part:
			out.append(id)
	out.sort()
	return out

func can_buy_mutation(id: String) -> bool:
	return mutation_tree.can_purchase(id)

func buy_mutation(id: String) -> bool:
	return mutation_tree.purchase(id)

func purchased_mutations() -> Array[String]:
	var out: Array[String] = []
	for id in mutation_info.keys():
		if mutation_tree.is_purchased(id):
			out.append(id)
	out.sort()
	return out

## 0..1 overall bodily change, for the hands rig and footstep weight.
func mutation_amount() -> float:
	return clampf((purchased_mutations().size() + tumor_mutations.size() * 2) / float(mutation_count()), 0.0, 1.0)

func hand_mutation_count(hand: String) -> int:
	var n := 0
	for id in purchased_mutations():
		if mutation_info[id]["hand"] == hand:
			n += 1
	return n

func hairs(pool: String) -> int:
	return mutation_tree.points(pool)

func total_hairs() -> int:
	var n := hairs(COMMON)
	for b in BIOMES:
		n += hairs(b)
	return n

# --- eating and settling -----------------------------------------------------

static func biome_for_shell(shell: int) -> String:
	return BIOMES[clampi(shell, 0, BIOMES.size() - 1)]

## One torn flesh unit, times the shell multiplier, is held as pending
## weighted flesh until vomited at the toilet or a rest point.
func on_flesh_eaten(shell: int, units: int = 1) -> void:
	var biome := biome_for_shell(shell)
	var gain: int = units * int(SHELL_MULTIPLIER[biome])
	pending_hairs[COMMON] = int(pending_hairs[COMMON]) + gain
	pending_hairs[biome] = int(pending_hairs[biome]) + gain
	deepest_shell = maxi(deepest_shell, shell)

## Weighted flesh still pending in the stomach (0 = nothing to settle).
func pending_hair_total() -> int:
	var n := 0
	for k in pending_hairs.keys():
		n += int(pending_hairs[k])
	return n

## Settling vomited flesh: teeth into the tank, pending flesh turns into
## hairs (biome: 1 per 50, common: 1 per 150, fractions carried).
## Returns {teeth, hairs, by_pool}.
func settle(flesh_amount: float) -> Dictionary:
	var gain_teeth := int(round(flesh_amount * TEETH_PER_FLESH))
	teeth += gain_teeth
	var gain_hairs := 0
	var by_pool := {}
	for k in pending_hairs.keys():
		var per := FLESH_PER_COMMON_HAIR if k == COMMON else FLESH_PER_BIOME_HAIR
		var c := float(hair_carry.get(k, 0.0)) + float(pending_hairs[k])
		var n := int(floor(c / per + 1e-6))
		hair_carry[k] = c - n * per
		if n > 0:
			mutation_tree.add_points(k, n)
			gain_hairs += n
		by_pool[k] = n
	_clear_pending()
	return {"teeth": gain_teeth, "hairs": gain_hairs, "by_pool": by_pool}

## Vomit anywhere else: flesh and its pending hairs are simply gone.
func discard_stomach() -> void:
	_clear_pending()

# --- tools and hands ---------------------------------------------------------

func owns(id: String) -> bool:
	return tools.owns(id)

## Hands are busy with a flesh pile or a tumor carried without the bag.
func one_hand_busy(carrying_flesh: bool) -> bool:
	return carrying_flesh or tumor_in_hand()

func tumor_in_hand() -> bool:
	return tumors.carried_count() > (1 if has_bag else 0)

## Equip "" (bare hands), knife, blender or big_saw.
func equip(id: String, carrying_flesh: bool) -> bool:
	return tools.try_equip(id, one_hand_busy(carrying_flesh))

func equipped() -> String:
	return tools.equipped

## Call whenever a hand becomes busy: drops a two-handed tool.
func refresh_hands(carrying_flesh: bool) -> void:
	tools.force_one_handed_if_needed(one_hand_busy(carrying_flesh))

## One-handed actions (spray, barrier) need a free hand: not while the
## two-handed saw is up.
func one_handed_action_allowed() -> bool:
	return not tools.is_two_handed(tools.equipped)

## Chew-speed multiplier for the equipped tool.
func dig_multiplier() -> float:
	match tools.equipped:
		"knife": return 1.6
		"big_saw": return 2.6
		_: return 1.0

## Tough tissue (mantle contractile fibers) needs a blade: bare hands cannot
## tear it (design-core 4, knife = "cuts tough flesh bare hands cannot tear").
func can_tear(tough: bool) -> bool:
	if not tough:
		return true
	return tools.equipped == "knife" or tools.equipped == "big_saw"

## Blender packs flesh: stomach fill per flesh unit drunk.
const BLENDER_PACKING := 0.7

# --- consumables --------------------------------------------------------------

func use_barrier() -> bool:
	if barriers <= 0:
		return false
	barriers -= 1
	return true

## Uses a cheap can first unless `deep` is asked for. Returns the tier used
## or -1.
func pick_spray_tier(deep: bool) -> int:
	var order := [FDKSprayCan.Tier.DEEP, FDKSprayCan.Tier.CHEAP] if deep else [FDKSprayCan.Tier.CHEAP, FDKSprayCan.Tier.DEEP]
	for t in order:
		if sprays.count_of_tier(t) > 0:
			return t
	return -1

func feed_canary() -> bool:
	if canary_feed <= 0:
		return false
	canary_feed -= 1
	return true

# --- vent shop ----------------------------------------------------------------

func price_for(id: String) -> int:
	return maxi(1, int(round(float(PRICE_UNITS.get(id, 1.0)) * EXPEDITION_TEETH)))

func _maxed(id: String) -> bool:
	match id:
		"knife", "blender", "big_saw": return tools.owns(id)
		"barrier": return barriers >= MAX_BARRIERS
		"spray_cheap", "spray_deep": return not sprays.can_add()
		"canary_feed": return canary_feed >= MAX_CANARY_FEED
		"tumor_bag": return has_bag
	return false

## Scoop a handful from the open tank. Returns how many were taken.
func scoop_handful() -> int:
	var n := mini(HANDFUL_TEETH, teeth)
	teeth -= n
	teeth_in_hand += n
	return n

## Teeth placed at the vent (03-restroom 7): the being keeps them all, no
## change. Few teeth -> junk only. Enough -> one of the dearest affordable
## items, the rest random cheaper ones (can be worth less than paid).
func vent_offer(placed: int) -> Array[String]:
	var cands: Array[String] = []
	for id in PRICE_UNITS.keys():
		if vent.try_price(id, placed, float(deepest_shell)) < 0 or _maxed(id):
			continue
		cands.append(id)
	if cands.is_empty():
		return ["junk"] as Array[String]
	cands.sort_custom(func(a, b): return price_for(a) > price_for(b) or (price_for(a) == price_for(b) and a < b))
	var out: Array[String] = [cands[0]]
	var rest: Array[String] = cands.slice(1)
	while out.size() < VENT_MAX_OFFER and not rest.is_empty():
		out.append(rest.pop_at(_rand() % rest.size()))
	if out.size() < VENT_MAX_OFFER:
		out.append("junk")
	return out

## Absurd overpay: at least this many teeth (twice the dearest unlocked
## item) makes the being laugh and spill early items.
func vent_absurd_threshold() -> int:
	var top := 0
	for id in PRICE_UNITS.keys():
		if vent.is_unlocked(id, float(deepest_shell)):
			top = maxi(top, price_for(id))
	return int(ceil(float(top) * FPVent.ABSURD_MULT))

## Early (core-unlocked) items that spill out on an absurd overpay.
func vent_spill() -> Array[String]:
	var out: Array[String] = []
	for id in FPVent.spill_list():
		if not _maxed(id):
			out.append(id)
	return out

func grant_item(id: String) -> bool:
	if _maxed(id):
		return false
	match id:
		"knife", "blender", "big_saw": tools.grant(id)
		"barrier": barriers += 1
		"spray_cheap": sprays.add(FDKSprayCan.new(FDKSprayCan.Tier.CHEAP))
		"spray_deep": sprays.add(FDKSprayCan.new(FDKSprayCan.Tier.DEEP))
		"canary_feed": canary_feed += 1
		"tumor_bag":
			has_bag = true # one basketball bag holds one tumor; a hand holds one more
			tumors.bag_capacity = 2
		"junk": junk_taken += 1
		_: return false
	return true

# --- tumors -------------------------------------------------------------------

func pick_up_tumor(kind: String, carrying_flesh: bool) -> bool:
	if carrying_flesh and tumors.carried_count() >= (1 if has_bag else 0):
		return false # no free hand
	if not tumors.pick_up(kind):
		return false
	refresh_hands(carrying_flesh)
	return true

func carried_tumors() -> Array:
	return tumors._carried.duplicate()

func eat_carried_tumor() -> bool:
	if tumors.carried_count() == 0:
		return false
	var kind: String = tumors._carried.pop_back()
	tumors.eat(kind, TUMOR_EAT_POINTS)
	return true

## Throw every carried tumor into the toilet: teeth + codex entries.
func throw_tumors_in_toilet() -> int:
	var got := 0
	for kind in tumors._carried.duplicate():
		var pay := tumors.throw_in_toilet(kind, TUMOR_TOOTH_PAYOUT)
		if pay > 0:
			teeth += pay
			got += pay
	return got

func codex_complete() -> bool:
	for k in TUMOR_KINDS:
		if not tumors.is_in_codex(k):
			return false
	return true

func _rand() -> int:
	_rng_state = (_rng_state * 1103515245 + 12345) & 0x7fffffff
	return _rng_state

## Spend tumor points at the mirror: a random large mutation not yet owned.
func buy_tumor_mutation() -> String:
	if tumors.tumor_points < TUMOR_MUTATION_COST:
		return ""
	var left: Array[String] = []
	for m in TUMOR_MUTATIONS:
		if m not in tumor_mutations:
			left.append(m)
	if left.is_empty():
		return ""
	tumors.tumor_points -= TUMOR_MUTATION_COST
	var pick: String = left[_rand() % left.size()]
	tumor_mutations.append(pick)
	return pick

# --- death --------------------------------------------------------------------

## What drops at the death spot: stomach contents (with its pending hairs)
## and carried consumables. Owned tools and teeth in the tank stay.
func take_death_payload(stomach_fill: float) -> Dictionary:
	var payload := {
		"stomach_fill": stomach_fill,
		"pending_hairs": pending_hairs.duplicate(true),
		"barriers": barriers,
		"sprays": sprays.serialize(),
		"canary_feed": canary_feed,
		"tumors": tumors._carried.duplicate(),
		"teeth_in_hand": teeth_in_hand,
	}
	barriers = 0
	canary_feed = 0
	teeth_in_hand = 0
	sprays.cans.clear()
	tumors._carried.clear()
	_clear_pending()
	tools.equipped = ""
	return payload

## Recovering the drop: consumables come back up to their carry caps; the
## stomach flesh returns as fill (caller adds it) with its pending hairs.
func restore_death_payload(p: Dictionary) -> float:
	var ph: Dictionary = p.get("pending_hairs", {})
	for k in ph.keys():
		pending_hairs[k] = int(pending_hairs.get(k, 0)) + int(ph[k])
	barriers = mini(MAX_BARRIERS, barriers + int(p.get("barriers", 0)))
	canary_feed = mini(MAX_CANARY_FEED, canary_feed + int(p.get("canary_feed", 0)))
	teeth_in_hand += int(p.get("teeth_in_hand", 0))
	var inv := FDKSprayCan.Inventory.new()
	inv.deserialize(p.get("sprays", {}))
	for c in inv.cans:
		sprays.add(c)
	for k in (p.get("tumors", []) as Array):
		tumors.pick_up(String(k))
	return float(p.get("stomach_fill", 0.0))

# --- save ---------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"teeth": teeth,
		"teeth_in_hand": teeth_in_hand,
		"barriers": barriers,
		"canary_feed": canary_feed,
		"has_bag": has_bag,
		"deepest_shell": deepest_shell,
		"pending_hairs": pending_hairs.duplicate(true),
		"hair_carry": hair_carry.duplicate(true),
		"junk_taken": junk_taken,
		"tumor_mutations": tumor_mutations.duplicate(),
		"rng": _rng_state,
		"tools": tools.serialize(),
		"mutations": mutation_tree.serialize(),
		"tumors": tumors.serialize(),
		"sprays": sprays.serialize(),
	}

func deserialize(d: Dictionary) -> void:
	var v := int(d.get("version", 1))
	teeth = int(d.get("teeth", 0))
	teeth_in_hand = int(d.get("teeth_in_hand", 0))
	barriers = int(d.get("barriers", 0))
	canary_feed = int(d.get("canary_feed", 0))
	has_bag = bool(d.get("has_bag", false))
	deepest_shell = int(d.get("deepest_shell", 0))
	_clear_pending()
	var ph: Dictionary = d.get("pending_hairs", {})
	for k in ph.keys():
		pending_hairs[k] = int(ph[k])
	var hc: Dictionary = d.get("hair_carry", {})
	for k in hc.keys():
		hair_carry[k] = float(hc[k])
	junk_taken = int(d.get("junk_taken", 0))
	tumor_mutations.clear()
	for m in (d.get("tumor_mutations", []) as Array):
		tumor_mutations.append(String(m))
	_rng_state = int(d.get("rng", _rng_state))
	if d.has("tools"):
		tools.deserialize(d["tools"])
	elif v < 2:
		# v1 stored separate owns_* flags
		for id in ["knife", "blender", "big_saw"]:
			if bool(d.get("owns_" + id, false)):
				tools.grant(id)
	if d.has("mutations"):
		mutation_tree.deserialize(d["mutations"])
	if d.has("tumors"):
		tumors.deserialize(d["tumors"])
	tumors.bag_capacity = 2 if has_bag else 1
	if d.has("sprays"):
		sprays.deserialize(d["sprays"])
