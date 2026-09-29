class_name FDKSprayCan
extends RefCounted

## Biosecurity spray inventory (design-core 2/3): the player carries up to 3
## cans. A can permanently dissolves flesh in a sphere via
## FDKTerrainField.spray_sphere -- sprayed tissue becomes inedible and never
## regenerates again. Performance is sold in price tiers that trade can cost
## for how deep one application reaches:
##   TIER_CHEAP  -- treats mainly the surface layer (small radius)
##   TIER_DEEP   -- clears a thicker volume (larger radius), costs more
##
## This is plain data/logic (no visuals, no shop UI) so the game wires its
## own purchase flow and hands out FDKSprayCan instances.

enum Tier { CHEAP, DEEP }

const MAX_CARRIED: int = 3

## Radius in world meters per tier (placeholder tuning, see STATUS.md).
const TIER_RADIUS := {
	Tier.CHEAP: 0.6,
	Tier.DEEP: 1.3,
}

var tier: Tier = Tier.CHEAP

func _init(p_tier: Tier = Tier.CHEAP) -> void:
	tier = p_tier

func radius() -> float:
	return TIER_RADIUS.get(tier, TIER_RADIUS[Tier.CHEAP])

## Applies this can at world_pos on the given terrain field, permanently
## sealing tissue in its tier's radius. One can = one use (consumed after
## application); the inventory holder is responsible for removing it.
func apply(terrain: FDKTerrainField, world_pos: Vector3) -> int:
	if terrain == null:
		return 0
	return terrain.spray_sphere(world_pos, radius())

func serialize() -> Dictionary:
	return {"version": 1, "tier": tier}

static func deserialize_new(data: Dictionary) -> FDKSprayCan:
	return FDKSprayCan.new(int(data.get("tier", Tier.CHEAP)) as Tier)


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

	## Uses (and removes) the first can of the given tier, if any. Returns
	## the number of cells sealed, or -1 if no matching can was carried.
	func use(terrain: FDKTerrainField, world_pos: Vector3, tier: FDKSprayCan.Tier) -> int:
		for i in range(cans.size()):
			if cans[i].tier == tier:
				var sealed := cans[i].apply(terrain, world_pos)
				cans.remove_at(i)
				return sealed
		return -1

	func count() -> int:
		return cans.size()

	func count_of_tier(tier: FDKSprayCan.Tier) -> int:
		var n := 0
		for c in cans:
			if c.tier == tier:
				n += 1
		return n

	func serialize() -> Dictionary:
		var arr: Array = []
		for c in cans:
			arr.append(c.serialize())
		return {"version": 1, "cans": arr}

	func deserialize(data: Dictionary) -> void:
		cans.clear()
		var arr: Array = data.get("cans", [])
		for entry in arr:
			cans.append(FDKSprayCan.deserialize_new(entry))
