class_name FPProgression
extends RefCounted

## Game-side progression state (docs/spec/04-economy.md): teeth (money), arm
## hairs (mutation points: common + per-biome pools), ~30 mutations, tumor
## mutations, tools with one/two-handed rules, consumables, vent stock and
## the death drop payload. Pure data/logic; main.gd wires it to the world.

const SAVE_VERSION := 3

const BIOME_CORE := "core"
const BIOME_MANTLE := "mantle"
const BIOME_SURFACE := "surface"
const BIOMES: Array[String] = [BIOME_CORE, BIOME_MANTLE, BIOME_SURFACE]
const COMMON := FDKMutationTree.COMMON
const TUMOR_POOL := "tumor"

## docs/spec/04-economy.md: shell multiplier core x1, mantle x2, surface x3.
const SHELL_MULTIPLIER := {BIOME_CORE: 1, BIOME_MANTLE: 2, BIOME_SURFACE: 3}

## Teeth per flesh unit vomited into the toilet. One expedition fills about
## 100 flesh, so "one expedition's earnings" is about 8 teeth = 2 handfuls.
const TEETH_PER_FLESH := 0.08
const EXPEDITION_TEETH := 8
## One handful scooped from the tank and placed at the vent.
const HANDFUL_TEETH := 4
## 실제 섭취한 살에 껍질 배율을 적용해 털을 즉시 지급한다.
## 한 가닥 미만의 잔량은 다음 섭취로 넘긴다.
const FLESH_PER_BIOME_HAIR := 50.0
const FLESH_PER_COMMON_HAIR := 150.0

## docs/spec/04-economy.md price guide, in expeditions' earnings. Items without a guide
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
## Tumor mutations (docs/spec/05-mutations.md 4), granted at random at the
## mirror by pressing a tumor bump on the belly. Never twice the same.
const TUMOR_MUTATIONS: Array[String] = ["T1", "T2", "T3", "T4", "T5", "T6", "T7"]

## Body parts the mirror can hover (05-mutations.md: every mutation has a
## body part). "tumor" is the bump on the belly, handled separately.
const PARTS: Array[String] = ["face", "neck", "chest", "belly", "right_hand", "left_hand", "arms", "whole"]

## 04-economy.md 2: hairs per mutation by branch.
const BRANCH_COST := {"common": 12, "compressive": 5, "contractile": 10, "nerve": 15}
const BRANCH_POOL := {"common": COMMON, "compressive": BIOME_CORE, "contractile": BIOME_MANTLE, "nerve": BIOME_SURFACE}
const POOL_COST := {COMMON: 12, BIOME_CORE: 5, BIOME_MANTLE: 10, BIOME_SURFACE: 15}
## Combination: either biome, at 1.5x that biome's value.
const COMBO_FACTOR := 1.5

## Base values from docs/spec/01-body-eating.md (and 07 crush time).
const BASE_REACH := 2.5
const BASE_TEAR_CELLS := 1
const BASE_CHEW_TIME := 0.6
const BASE_CAPACITY := 100.0
const BASE_OVERFILL := 60.0
const BASE_OVERFILL_CHEW := 3.0
const BASE_BODY_RADIUS := 0.35
const BASE_CRUSH_TIME := 6.0
const BASE_CARRY := 40.0
const BASE_FOV := 90.0
const SQUEEZE_SLOW_AT := 0.5
## Tissue hardness (02-world-tissue.md 3), keyed by main.gd tissue id.
const TISSUE_HARDNESS := {0: 1.0, 1: 1.2, 2: 1.0, 3: 2.0, 4: 1.4}
const TISSUE_COMPRESSIVE := 0
const TISSUE_NERVE := 1
const TISSUE_MEMBRANE := 3
const TISSUE_CONTRACTILE := 4

var tools: FDKToolKit = FDKToolKit.new()
var hands: FPHandEquipment = FPHandEquipment.new()
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
## The work belt (tool hooks) comes with the first vent trade.
var has_belt: bool = false
var tumor_mutations: Array[String] = []
var deepest_shell: int = 0
var tumors_eaten: int = 0
## 구형 저장의 미지급 가중 살 단위를 읽는 호환 필드다.
## COMMON과 바이옴별 값은 이미 껍질 배율이 적용됐으며 한 번만 이전한다.
## 새 섭취는 위장·정산을 기다리지 않고 털과 잔량에 바로 반영한다.
var pending_hairs: Dictionary = {}
## 한 가닥 미만의 가중 섭취량을 다음 섭취에 합산한다.
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

## One mutation. `part` is the mirror part, `spot` the exact body place in
## the spec, `hand` which first-person hand it reshapes ("" none).
func _def(id: String, name_ko: String, branch: String, part: String, spot: String, hand: String, alt: Array[String] = []) -> void:
	var pool: String = alt[0] if not alt.is_empty() else String(BRANCH_POOL[branch])
	var cost := int(POOL_COST[pool]) if alt.is_empty() else int(ceil(float(POOL_COST[pool]) * COMBO_FACTOR))
	mutation_tree.define_node(id, [] as Array[String], pool, cost, alt)
	mutation_info[id] = {"name": name_ko, "part": part, "spot": spot, "hand": hand, "pool": pool, "group": branch, "alt": alt.duplicate()}

## docs/spec/05-mutations.md, sections 2 and 3 (29 ids; M11 was deleted and
## M03 was reused for the magnet eye). Branch only picks the hair colour.
func _define_mutations() -> void:
	_def("M01", "늘어난 위", "common", "belly", "배", "")
	_def("M02", "넓은 목구멍", "common", "neck", "목", "")
	_def("M03", "자기장 눈", "common", "face", "눈", "")
	_def("M04", "불거진 턱", "common", "face", "턱", "")
	_def("M05", "접히는 어깨", "common", "chest", "어깨", "")
	_def("M06", "긴 숨", "common", "chest", "가슴", "")
	_def("M07", "넓은 손바닥", "compressive", "right_hand", "오른손", "right")
	_def("M08", "물갈퀴", "compressive", "right_hand", "오른손", "right")
	_def("M09", "두꺼운 손톱", "compressive", "right_hand", "오른손", "right")
	_def("M10", "긴 마디", "compressive", "right_hand", "오른손", "right")
	_def("M12", "부푼 팔뚝", "compressive", "right_hand", "오른팔", "right")
	_def("M13", "빨판 주름", "compressive", "right_hand", "오른손", "right")
	_def("M14", "근육 과다", "contractile", "whole", "온몸", "both")
	_def("M15", "빠지는 턱", "contractile", "face", "턱", "")
	_def("M16", "되새김 위", "contractile", "belly", "배", "")
	_def("M17", "무통각증", "contractile", "whole", "온몸", "")
	_def("M18", "두더지 앞발", "contractile", "right_hand", "오른손", "right")
	_def("M19", "연동 기기", "contractile", "belly", "배", "")
	_def("M20", "과유연 관절", "contractile", "arms", "팔다리", "both")
	_def("M21", "발전 근육", "nerve", "left_hand", "왼팔", "left")
	_def("M22", "외계인 손", "nerve", "left_hand", "왼손", "left")
	_def("M23", "감각털", "nerve", "arms", "팔", "both")
	_def("M24", "올빼미 눈", "nerve", "face", "눈", "")
	_def("M25", "과잉 기억", "nerve", "face", "머리", "")
	_def("M26", "도롱뇽 재생", "nerve", "arms", "팔", "both")
	_def("M27", "코끼리 코", "nerve", "face", "코", "")
	_def("M28", "뼈 없는 팔", "combination", "left_hand", "왼팔", "left", [BIOME_CORE, BIOME_MANTLE] as Array[String])
	_def("M29", "휴면", "combination", "whole", "온몸", "", [BIOME_MANTLE, BIOME_SURFACE] as Array[String])
	_def("M30", "목주머니", "combination", "neck", "목", "", [BIOME_SURFACE, BIOME_CORE] as Array[String])

const TUMOR_INFO := {
	"T1": {"name": "반향정위", "part": "face"},
	"T2": {"name": "세 번째 팔", "part": "chest"},
	"T3": {"name": "손바닥 입", "part": "right_hand"},
	"T4": {"name": "부푼 몸통", "part": "belly"},
	"T5": {"name": "어안", "part": "face"},
	"T6": {"name": "세로 턱", "part": "face"},
	"T7": {"name": "부채 갈비", "part": "chest"},
}

func mutation_count() -> int:
	return mutation_info.size()

func mutations_for_part(part: String) -> Array[String]:
	var out: Array[String] = []
	for id in mutation_info.keys():
		if mutation_info[id]["part"] == part:
			out.append(id)
	out.sort()
	return out

## Hairs this mutation costs when paid from `pool` (-1 if not payable there).
func cost_in(id: String, pool: String) -> int:
	var info: Dictionary = mutation_info.get(id, {})
	if info.is_empty():
		return -1
	var alt: Array = info["alt"]
	if alt.is_empty():
		return int(POOL_COST[pool]) if pool == info["pool"] else -1
	if pool not in alt:
		return -1
	return int(ceil(float(POOL_COST[pool]) * COMBO_FACTOR))

## Pool that would pay for id right now ("" if none can).
func paying_pool(id: String) -> String:
	var info: Dictionary = mutation_info.get(id, {})
	if info.is_empty() or mutation_tree.is_purchased(id):
		return ""
	var pools: Array = info["alt"] if not (info["alt"] as Array).is_empty() else [info["pool"]]
	for p in pools:
		if hairs(p) >= cost_in(id, p):
			return p
	return ""

func can_buy_mutation(id: String) -> bool:
	return paying_pool(id) != ""

## Buying pulls the hairs off the arm (combination: from whichever of its
## two biome pools can pay its own 1.5x price).
func buy_mutation(id: String) -> bool:
	var pool := paying_pool(id)
	if pool == "":
		return false
	mutation_tree.add_points(pool, -cost_in(id, pool))
	mutation_tree._purchased[id] = true
	return true

func has_mutation(id: String) -> bool:
	return mutation_tree.is_purchased(id) or id in tumor_mutations

func purchased_mutations() -> Array[String]:
	var out: Array[String] = []
	for id in mutation_info.keys():
		if mutation_tree.is_purchased(id):
			out.append(id)
	out.sort()
	return out

## Every owned mutation, hair and tumor ones, for the body visuals.
func all_mutations() -> Array[String]:
	var out := purchased_mutations()
	for t in tumor_mutations:
		out.append(t)
	return out

## 0..1 overall bodily change, for the hands rig and footstep weight.
func mutation_amount() -> float:
	return clampf((purchased_mutations().size() + tumor_mutations.size() * 2) / float(mutation_count()), 0.0, 1.0)

func hand_mutation_count(hand: String) -> int:
	var n := 0
	for id in purchased_mutations():
		var h: String = mutation_info[id]["hand"]
		if h == hand or h == "both":
			n += 1
	return n

# --- mutation effects (parameter names from CONTEXT.md / 01-body-eating.md) ---

func _m(id: String) -> bool:
	return has_mutation(id)

func reach() -> float:
	return BASE_REACH + (0.4 if _m("M10") else 0.0)

func tear_cells() -> int:
	return BASE_TEAR_CELLS + (1 if _m("M07") else 0) + (1 if _m("M14") else 0)

func base_chew_time() -> float:
	var t := BASE_CHEW_TIME
	if _m("M04"):
		t *= 0.85
	if _m("T3"):
		t *= 0.4
	return t

func capacity() -> float:
	var c := BASE_CAPACITY + (20.0 if _m("M01") else 0.0)
	return c * (2.0 if _m("T4") else 1.0)

func overfill_capacity() -> float:
	return BASE_OVERFILL + (40.0 if _m("M30") else 0.0)

func overfill_chew_multiplier() -> float:
	return 2.4 if _m("M02") else BASE_OVERFILL_CHEW

func body_radius() -> float:
	var r := BASE_BODY_RADIUS
	if _m("M05"):
		r *= 0.85
	if _m("T4"):
		r *= 1.3
	return r

func crush_time() -> float:
	return BASE_CRUSH_TIME + (3.0 if _m("M06") else 0.0)

func carry_capacity() -> float:
	return BASE_CARRY * (1.5 if _m("M13") else 1.0)

## Walk speed factor from mutations alone (M14 x0.9, T7 x0.8).
func walk_speed_factor() -> float:
	var f := 1.0
	if _m("M14"):
		f *= 0.9
	if _m("T7"):
		f *= 0.8
	return f

## Speed factor from squeeze (0..1): normally half at >= 0.5; M20 removes
## the slowdown, M19 turns it into a x1.3 push.
func squeeze_speed_factor(squeeze: float) -> float:
	if squeeze < SQUEEZE_SLOW_AT:
		return 1.0
	if _m("M19"):
		return 1.3
	if _m("M20"):
		return 1.0
	return 0.5

## Effective hardness of a tissue id for the player's body.
## M08 compressive x0.7, M18 contractile x0.6, M12 excess over 1.0 x0.5,
## T6 membrane 2.0 -> 1.0, M09 bare-hand membrane chew x3.
func hardness(tissue: int, bare_hand: bool = false) -> float:
	var h: float = float(TISSUE_HARDNESS.get(tissue, 1.0))
	if tissue == TISSUE_MEMBRANE and _m("T6"):
		h = 1.0
	if tissue == TISSUE_COMPRESSIVE and _m("M08"):
		h *= 0.7
	if tissue == TISSUE_CONTRACTILE and _m("M18"):
		h *= 0.6
	if h > 1.0 and _m("M12"):
		h = 1.0 + (h - 1.0) * 0.5
	if tissue == TISSUE_MEMBRANE and bare_hand and _m("M09") and not _m("T6"):
		h *= 3.0
	return h

## Membrane needs a blade, unless thick nails (M09) or the vertical jaw (T6).
func can_grab_membrane_bare() -> bool:
	return _m("M09") or _m("T6")

func tissue_damage_factor() -> float:
	return 0.5 if _m("M17") else 1.0

func health_regen_factor() -> float:
	return 3.0 if _m("M26") else 1.0

func light_range_factor() -> float:
	return 1.6 if _m("M24") else 1.0

func restroom_glare_factor() -> float:
	return 2.0 if _m("M24") else 1.0

func fov() -> float:
	return 200.0 if _m("T5") else BASE_FOV

## M21: the blender charges itself in the left hand (per second).
func blender_self_charge() -> float:
	return 5.0 if _m("M21") else 0.0

## M16: every 60 s the flesh in the stomach shrinks by 10 %.
const CUD_PERIOD := 60.0
const CUD_SHRINK := 0.1
## M22: standing still, the left hand tears one cell in reach every 2 s.
const ALIEN_HAND_PERIOD := 2.0
## M15: a whole flesh pile swallowed in 3 s.
const GULP_TIME := 3.0
## M23: hair shiver lead time before a contraction.
const HAIR_WARN_TIME := 1.5
## M27: trunk twitch radius toward tumors.
const TRUNK_RADIUS := 10.0
## M29: dormancy wake delay.
const DORMANT_WAKE := 30.0
## T7: regen freeze radius while standing still.
const RIB_FAN_RADIUS := 1.5

func can_lift_without_blender() -> bool:
	return _m("M15")

## Hands: T3 mouth in the right palm cannot hold a pile; M28/T2 let two-hand
## tools work while carrying.
func right_hand_can_carry() -> bool:
	return not _m("T3")

func two_hand_tools_while_carrying() -> bool:
	return _m("M28") or _m("T2")

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

## Actual flesh units eaten, multiplied by shell multiplier, immediately
## grow hairs on the arm (biome: 1 per 50, common: 1 per 150; fractions carry).
## No need to flush or settle at the toilet (R17).
func on_flesh_eaten(shell: int, units: float = 1.0) -> void:
	if units <= 0.0:
		return
	var biome := biome_for_shell(shell)
	var mult: float = float(SHELL_MULTIPLIER.get(biome, 1))
	var weighted: float = float(units) * mult
	deepest_shell = maxi(deepest_shell, shell)

	# Biome pool hair growth
	var c_biome: float = float(hair_carry.get(biome, 0.0)) + weighted
	var n_biome: int = int(floor(c_biome / FLESH_PER_BIOME_HAIR + 1e-6))
	hair_carry[biome] = c_biome - float(n_biome) * FLESH_PER_BIOME_HAIR
	if n_biome > 0:
		mutation_tree.add_points(biome, n_biome)

	# Common pool hair growth
	var c_common: float = float(hair_carry.get(COMMON, 0.0)) + weighted
	var n_common: int = int(floor(c_common / FLESH_PER_COMMON_HAIR + 1e-6))
	hair_carry[COMMON] = c_common - float(n_common) * FLESH_PER_COMMON_HAIR
	if n_common > 0:
		mutation_tree.add_points(COMMON, n_common)

## Weighted flesh still pending in the stomach (0 under R17 immediate hair growth).
func pending_hair_total() -> int:
	var n := 0
	for k in pending_hairs.keys():
		n += int(pending_hairs[k])
	return n

## Settling vomited flesh: teeth into the tank. Under R17, hairs grew
## immediately when eaten, so settle hair gain is always 0.
## Returns {teeth, hairs, by_pool}.
func settle(flesh_amount: float) -> Dictionary:
	var gain_teeth := int(round(flesh_amount * TEETH_PER_FLESH))
	teeth += gain_teeth
	var by_pool := {COMMON: 0}
	for b in BIOMES:
		by_pool[b] = 0
	_clear_pending()
	return {"teeth": gain_teeth, "hairs": 0, "by_pool": by_pool}

## Vomit anywhere else: flesh in stomach is gone, but already grown hairs remain.
func discard_stomach() -> void:
	_clear_pending()

# --- tools and hands ---------------------------------------------------------

func owns(id: String) -> bool:
	match id:
		"spray_cheap": return sprays.count_of_tier(FDKSprayCan.Tier.CHEAP) > 0
		"spray_deep": return sprays.count_of_tier(FDKSprayCan.Tier.DEEP) > 0
		"canary_feed": return canary_feed > 0
		"barrier": return barriers > 0
	return tools.owns(id)

## Hands are busy with a flesh pile or a tumor carried without the bag.
func one_hand_busy(carrying_flesh: bool) -> bool:
	return carrying_flesh or tumor_in_hand()

func tumor_in_hand() -> bool:
	return tumors.carried_count() > (1 if has_bag else 0)

## Equip "" (bare hands), knife, blender or big_saw.
func equip(id: String, carrying_flesh: bool) -> bool:
	# Legacy single-tool entry point for integrations and old save callers.
	if id != "" and not owns(id):
		return false
	if id == "big_saw" and one_hand_busy(carrying_flesh):
		return false
	hands.clear()
	hands.set_item(id, tools.hand_of(id), tools.is_two_handed(id))
	tools.equipped = id
	return true

func equip_hand(id: String, hand: int, carrying_flesh: bool) -> bool:
	if hand not in [FDKToolKit.Hand.LEFT, FDKToolKit.Hand.RIGHT]:
		return false
	if id != "" and not owns(id):
		return false
	if id == "blender" and hand != FDKToolKit.Hand.LEFT:
		return false
	if id != "" and one_hand_busy(carrying_flesh) and (hand == FDKToolKit.Hand.RIGHT or tools.is_two_handed(id)):
		return false
	hands.set_item(id, hand, tools.is_two_handed(id))
	tools.equipped = id
	return true

func activate_hand(hand: int) -> String:
	tools.equipped = hands.item(hand)
	return tools.equipped

func refresh_equipment() -> void:
	for hand in [FDKToolKit.Hand.LEFT, FDKToolKit.Hand.RIGHT]:
		var id := hands.item(hand)
		if id != "" and not owns(id):
			hands.set_item("", hand)
	if tools.equipped != "" and not owns(tools.equipped):
		tools.equipped = ""

func equipped() -> String:
	return tools.equipped

## Call whenever a hand becomes busy: drops a two-handed tool.
func refresh_hands(carrying_flesh: bool) -> void:
	tools.force_one_handed_if_needed(one_hand_busy(carrying_flesh))
	if one_hand_busy(carrying_flesh) and hands.holds("big_saw"):
		hands.clear()

## One-handed actions (spray, barrier) need a free hand: not while the
## two-handed saw is up.
func one_handed_action_allowed() -> bool:
	return not hands.holds("big_saw") and not tools.is_two_handed(tools.equipped)

## Chew-speed multiplier for the equipped tool.
func dig_multiplier() -> float:
	match tools.equipped:
		"knife": return 1.6
		"big_saw": return 2.6
		_: return 1.0

## Tough tissue (mantle contractile fibers) needs a blade: bare hands cannot
## tear it (docs/spec/04-economy.md, knife = "cuts tough flesh bare hands cannot tear").
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
	eat_tumor_kind(kind)
	return true

## Eating a tumor: a small bump rises on the belly (1 point = 1 bump).
## Once all 7 tumor mutations are owned no more bumps appear.
func eat_tumor_kind(kind: String) -> void:
	var pts := TUMOR_EAT_POINTS if tumor_mutations.size() + tumors.tumor_points < TUMOR_MUTATIONS.size() else 0
	tumors.eat(kind, pts)
	tumors_eaten += 1

## Bumps currently on the belly, waiting to be pressed at the mirror.
func belly_bumps() -> int:
	return tumors.tumor_points

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

## What drops at the death spot: stomach contents and carried consumables.
## Under R17, already grown hairs and purchased mutations stay on the body.
## Owned tools and teeth in the tank stay.
func take_death_payload(stomach_fill: float) -> Dictionary:
	var payload := {
		"stomach_fill": stomach_fill,
		"pending_hairs": pending_hairs.duplicate(true),
		"barriers": barriers,
		"sprays": sprays.serialize(),
		"canary_feed": canary_feed,
		"tumors": tumors._carried.duplicate(),
		"teeth_in_hand": teeth_in_hand,
		"migrated_v5_hairs": true,
	}
	barriers = 0
	canary_feed = 0
	teeth_in_hand = 0
	sprays.cans.clear()
	tumors._carried.clear()
	_clear_pending()
	tools.equipped = ""
	hands.clear()
	return payload

## Recovering the drop: consumables come back up to their carry caps; the
## stomach flesh returns as fill (caller adds it). Already eaten flesh does
## NOT re-award hairs. Legacy payloads with unmigrated pending_hairs are
## migrated exactly once into hairs and hair_carry.
func restore_death_payload(p: Dictionary) -> float:
	var is_migrated: bool = bool(p.get("migrated_v5_hairs", false))
	var ph: Dictionary = p.get("pending_hairs", {})
	if not is_migrated and not ph.is_empty():
		for k in ph.keys():
			var val := float(ph[k])
			if val > 0.0:
				var per := FLESH_PER_COMMON_HAIR if k == COMMON else FLESH_PER_BIOME_HAIR
				var c := float(hair_carry.get(k, 0.0)) + val
				var n := int(floor(c / per + 1e-6))
				hair_carry[k] = c - float(n) * per
				if n > 0:
					mutation_tree.add_points(k, n)
		p["migrated_v5_hairs"] = true
		p["pending_hairs"] = {}
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
		"has_belt": has_belt,
		"deepest_shell": deepest_shell,
		"pending_hairs": pending_hairs.duplicate(true),
		"hair_carry": hair_carry.duplicate(true),
		"junk_taken": junk_taken,
		"tumor_mutations": tumor_mutations.duplicate(),
		"tumors_eaten": tumors_eaten,
		"rng": _rng_state,
		"tools": tools.serialize(),
		"hands": hands.serialize(),
		"mutations": mutation_tree.serialize(),
		"tumors": tumors.serialize(),
		"sprays": sprays.serialize(),
		"migrated_v5_hairs": true,
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
	hair_carry = {COMMON: 0.0}
	for b in BIOMES:
		hair_carry[b] = 0.0
	var hc: Dictionary = d.get("hair_carry", {})
	for k in hc.keys():
		hair_carry[k] = float(hc[k])
	junk_taken = int(d.get("junk_taken", 0))
	tumor_mutations.clear()
	const OLD_TUMOR := {"extra_arm": "T2", "palm_mouth": "T3", "swollen_torso": "T4", "back_eyes": "T5", "split_jaw": "T6", "rib_fan": "T7"}
	for m in (d.get("tumor_mutations", []) as Array):
		var id := String(OLD_TUMOR.get(String(m), String(m)))
		if id in TUMOR_MUTATIONS and id not in tumor_mutations:
			tumor_mutations.append(id)
	tumors_eaten = int(d.get("tumors_eaten", 0))
	_rng_state = int(d.get("rng", _rng_state))
	if d.has("tools"):
		tools.deserialize(d["tools"])
	elif v < 2:
		# v1 stored separate owns_* flags
		for id in ["knife", "blender", "big_saw"]:
			if bool(d.get("owns_" + id, false)):
				tools.grant(id)
	if d.has("hands"):
		hands.deserialize(d["hands"])
	else:
		hands.clear()
		hands.set_item(tools.equipped, tools.hand_of(tools.equipped), tools.is_two_handed(tools.equipped))
	if d.has("mutations"):
		mutation_tree.deserialize(d["mutations"])
	if d.has("tumors"):
		tumors.deserialize(d["tumors"])
	tumors.bag_capacity = 2 if has_bag else 1
	if d.has("sprays"):
		sprays.deserialize(d["sprays"])

	var is_migrated: bool = bool(d.get("migrated_v5_hairs", false))
	var ph: Dictionary = d.get("pending_hairs", {})
	if not is_migrated and not ph.is_empty():
		for k in ph.keys():
			var val := float(ph[k])
			if val > 0.0:
				var per := FLESH_PER_COMMON_HAIR if k == COMMON else FLESH_PER_BIOME_HAIR
				var c := float(hair_carry.get(k, 0.0)) + val
				var n := int(floor(c / per + 1e-6))
				hair_carry[k] = c - float(n) * per
				if n > 0:
					mutation_tree.add_points(k, n)
		_clear_pending()
	else:
		for k in ph.keys():
			pending_hairs[k] = int(ph[k])

	refresh_equipment()
	# older saves: anyone who already owns a tool has traded, so has the belt
	has_belt = bool(d.get("has_belt", owns("knife") or owns("blender") or owns("big_saw")))
