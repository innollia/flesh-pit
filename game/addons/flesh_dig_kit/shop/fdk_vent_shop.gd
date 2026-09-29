class_name FDKVentShop
extends RefCounted

## Vent shop catalog (docs/spec/04-economy.md): pure data + purchase logic, no UI.
## The player spends teeth (money); prices are the docs/spec/04-economy.md price
## guide scaled from "one expedition''s earnings" into absolute teeth.
## Stock unlocks with depth and other conditions (`unlock_depth`, checked
## by the caller against FDKTerrainField.depth_at).
##
## Item ids match the tool/consumable ids used elsewhere (FDKToolKit,
## FDKSprayCan.Inventory, FDKBarrierField) so a purchase can be routed
## straight into those systems by id.

class FDKShopItem:
	extends RefCounted
	var id: String
	var price: int
	var unlock_depth: float
	func _init(p_id: String, p_price: int, p_unlock_depth: float = 0.0) -> void:
		id = p_id
		price = p_price
		unlock_depth = p_unlock_depth

var _items: Dictionary = {} ## id -> FDKShopItem
var _order: Array[String] = [] ## definition order == default slot order

func define_item(id: String, price: int, unlock_depth: float = 0.0) -> void:
	_items[id] = FDKShopItem.new(id, price, unlock_depth)
	if id not in _order:
		_order.append(id)

func get_item(id: String) -> FDKShopItem:
	return _items.get(id, null)

func is_unlocked(id: String, current_depth: float) -> bool:
	var item: FDKShopItem = _items.get(id, null)
	return item != null and current_depth >= item.unlock_depth

## Slot index -> item id, skipping locked items, in definition order.
## Returns "" for a slot past the last unlocked item.
func slot_item_id(slot: int, current_depth: float) -> String:
	var unlocked: Array = []
	for id in _order:
		if is_unlocked(id, current_depth):
			unlocked.append(id)
	return unlocked[slot] if slot >= 0 and slot < unlocked.size() else ""

## Returns the teeth price, or -1 if unaffordable/locked/unknown.
func try_price(id: String, teeth: int, current_depth: float) -> int:
	var item: FDKShopItem = _items.get(id, null)
	if item == null or not is_unlocked(id, current_depth) or teeth < item.price:
		return -1
	return item.price
