class_name FDKSprayCan
extends RefCounted

## Biosecurity spray (docs/spec/06-tools.md 5). The player carries up to 3
## cans; each can sprays 6 times. One spray melts the wall the player aims at
## (FDKTerrainField.spray_surface): melted cells never regrow and cannot be
## eaten, and the flesh within 1.0 m of them regrows x2.0 faster, so the
## squeeze never goes away.
##   CHEAP -- melts one cell layer (0.5 m) into the surface
##   DEEP  -- melts three layers (1.5 m)
## Plain data/logic (no visuals, no shop UI).

enum Tier { CHEAP, DEEP }

const MAX_CARRIED: int = 3
const SPRAYS_PER_CAN: int = 6
const SPRAY_RADIUS := 0.75
const BOOST_RANGE := 1.0
const BOOST_MULT := 2.0
const TIER_DEPTH := {
	Tier.CHEAP: 0.5,
	Tier.DEEP: 1.5,
}

var tier: Tier = Tier.CHEAP
var uses_left: int = SPRAYS_PER_CAN

func _init(p_tier: Tier = Tier.CHEAP) -> void:
	tier = p_tier

func depth() -> float:
	return TIER_DEPTH.get(tier, TIER_DEPTH[Tier.CHEAP])

## Kept for older callers: the reach of one spray.
func radius() -> float:
	return SPRAY_RADIUS

## One spray at the aimed wall point, melting along `into` (the look
## direction). Uses one of the can's sprays. Returns cells melted.
func apply(terrain: FDKTerrainField, world_pos: Vector3, into: Vector3 = Vector3.ZERO) -> int:
	if terrain == null or uses_left <= 0:
		return 0
	if into.length() < 0.01:
		into = (world_pos - terrain.depth_origin).normalized()
		if into.length() < 0.01:
			into = Vector3.FORWARD
	uses_left -= 1
	return terrain.spray_surface(world_pos, into, SPRAY_RADIUS, depth(), BOOST_RANGE, BOOST_MULT)

func is_empty() -> bool:
	return uses_left <= 0

func serialize() -> Dictionary:
	return {"version": 2, "tier": tier, "uses_left": uses_left}

static func deserialize_new(data: Dictionary) -> FDKSprayCan:
	var c := FDKSprayCan.new(int(data.get("tier", Tier.CHEAP)) as Tier)
	c.uses_left = int(data.get("uses_left", SPRAYS_PER_CAN))
	return c


## Holds the player's current can inventory (carry cap 3, mixed tiers).
class Inventory:
	extends RefCounted

	var cans: Array[FDKSprayCan] = []

	func can_add() -> bool:
		return cans.size() < FDKSprayCan.MAX_CARRIED

	func add(can: FDKSprayCan) -> bool:
		if not can_add():
			return false
		cans.append(can)
		return true

	## One spray from the first can of the given tier; an emptied can is
	## dropped. Returns cells melted, or -1 if no matching can was carried.
	func use(terrain: FDKTerrainField, world_pos: Vector3, tier: FDKSprayCan.Tier, into: Vector3 = Vector3.ZERO) -> int:
		for i in range(cans.size()):
			if cans[i].tier == tier and not cans[i].is_empty():
				var melted := cans[i].apply(terrain, world_pos, into)
				if cans[i].is_empty():
					cans.remove_at(i)
				return melted
		return -1

	func count() -> int:
		return cans.size()

	func count_of_tier(tier: FDKSprayCan.Tier) -> int:
		var n := 0
		for c in cans:
			if c.tier == tier:
				n += 1
		return n

	## Sprays left across every can of a tier (the belt shows the cans).
	func sprays_left(tier: FDKSprayCan.Tier) -> int:
		var n := 0
		for c in cans:
			if c.tier == tier:
				n += c.uses_left
		return n

	func serialize() -> Dictionary:
		var arr: Array = []
		for c in cans:
			arr.append(c.serialize())
		return {"version": 2, "cans": arr}

	func deserialize(data: Dictionary) -> void:
		cans.clear()
		var arr: Array = data.get("cans", [])
		for entry in arr:
			cans.append(FDKSprayCan.deserialize_new(entry))