class_name FDKMutationTree
extends RefCounted

## Mutation progression data structure (design-core 4): a point-based parent
## -> child upgrade tree with two point layers -- one shared "common" trunk
## and one pool per biome. Nodes can be purchased anywhere (no restroom/
## toilet gate); a node requires its parent(s) already purchased and enough
## points in the required pool(s).
##
## Reconverged combination nodes require BOTH prerequisite branches to
## already be satisfied, but can be PAID with either one of the
## contributing biome pools (see FDKMutationNode.pay_with_pools).
##
## Pure data/logic; no UI. A game defines its node list once (ids, costs,
## pools, parents) and calls purchase()/can_purchase() against player state.

const COMMON := "common"

class FDKMutationNode:
	extends RefCounted
	var id: String
	var parent_ids: Array[String] = [] ## empty = trunk root
	## Pool this node draws from normally (COMMON or a biome id). For a
	## reconverged combination node, use `alt_pools` instead/in addition.
	var pool: String = FDKMutationTree.COMMON
	## For a combination node: any ONE of these pools may pay the cost
	## (design-core 4: "paid with either one of the contributing biome point
	## pools rather than requiring both currencies simultaneously").
	var alt_pools: Array[String] = []
	var cost: int = 0

	func _init(p_id: String, p_parent_ids: Array[String], p_pool: String, p_cost: int, p_alt_pools: Array[String] = []) -> void:
		id = p_id
		parent_ids = p_parent_ids
		pool = p_pool
		cost = p_cost
		alt_pools = p_alt_pools

	func payable_pools() -> Array[String]:
		if alt_pools.size() > 0:
			return alt_pools
		return [pool]

var _nodes: Dictionary = {} ## id -> FDKMutationNode
var _purchased: Dictionary = {} ## id -> true
## pool id -> available points
var _points: Dictionary = {COMMON: 0}

func define_node(id: String, parent_ids: Array[String], pool: String, cost: int, alt_pools: Array[String] = []) -> void:
	_nodes[id] = FDKMutationNode.new(id, parent_ids, pool, cost, alt_pools)

func add_points(pool: String, amount: int) -> void:
	_points[pool] = int(_points.get(pool, 0)) + amount

## Every flesh-eating reward grants both a common component and the
## relevant biome-specific component at once (design-core 4). `common_amount`
## and `biome_amount` are computed by the caller from depth x flesh eaten.
func grant_reward(biome_pool: String, common_amount: int, biome_amount: int) -> void:
	add_points(COMMON, common_amount)
	add_points(biome_pool, biome_amount)

func points(pool: String) -> int:
	return int(_points.get(pool, 0))

func is_purchased(id: String) -> bool:
	return _purchased.get(id, false)

func _parents_satisfied(node: FDKMutationNode) -> bool:
	for pid in node.parent_ids:
		if not is_purchased(pid):
			return false
	return true

func can_purchase(id: String) -> bool:
	var node: FDKMutationNode = _nodes.get(id, null)
	if node == null or is_purchased(id):
		return false
	if not _parents_satisfied(node):
		return false
	for pool in node.payable_pools():
		if points(pool) >= node.cost:
			return true
	return false

## Purchases id anywhere (no location gate), paying from the first pool
## (in payable_pools order) that can afford it. Returns true on success.
func purchase(id: String) -> bool:
	var node: FDKMutationNode = _nodes.get(id, null)
	if node == null or not can_purchase(id):
		return false
	for pool in node.payable_pools():
		if points(pool) >= node.cost:
			_points[pool] = points(pool) - node.cost
			_purchased[id] = true
			return true
	return false

func get_node_def(id: String) -> FDKMutationNode:
	return _nodes.get(id, null)

func serialize() -> Dictionary:
	return {
		"version": 1,
		"purchased": _purchased.keys(),
		"points": _points.duplicate(true),
	}

func deserialize(data: Dictionary) -> void:
	_purchased.clear()
	for id in (data.get("purchased", []) as Array):
		_purchased[id] = true
	_points = (data.get("points", {COMMON: 0}) as Dictionary).duplicate(true)
	if not _points.has(COMMON):
		_points[COMMON] = 0
