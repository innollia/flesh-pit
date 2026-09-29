class_name FDKHazardCheck
extends RefCounted

## Danger/death checks (docs/spec/07-danger-navigation.md), pure logic against a terrain field.
## Two death causes:
##  - crush death: the player''s own position becomes solid because
##    regenerating flesh closed the passage around them (checked every
##    tick against FDKTerrainField.density_at).
##  - tissue hazard: standing too close to a disturbed/hazard tissue
##    (e.g. a convulsing nerve) for too long accumulates damage.
##
## No visuals; callers hook the returned bool/float into their own
## death/respawn and screen-shake presentation.

const CRUSH_DENSITY := 0.92 ## occupied-space density above which the player''s own cell reads as solid flesh

var hazard_dps: float = 40.0 ## damage per second while inside a hazard radius
var hazard_radius: float = 1.1
var health: float = 100.0
var crushed: bool = false

## Call once per physics tick. `terrain` needs density_at(Vector3)->float.
func check_crush(terrain: Object, player_pos: Vector3) -> bool:
	if terrain.density_at(player_pos) >= CRUSH_DENSITY:
		crushed = true
	return crushed

## Call once per tick per active hazard (e.g. a disturbed FDKNerveStalk).
## Returns true if this hazard is currently damaging the player.
func apply_hazard_tick(player_pos: Vector3, hazard_pos: Vector3, delta: float) -> bool:
	if player_pos.distance_to(hazard_pos) > hazard_radius:
		return false
	health = maxf(0.0, health - hazard_dps * delta)
	return true

func is_dead() -> bool:
	return crushed or health <= 0.0

func reset() -> void:
	crushed = false
	health = 100.0

func serialize() -> Dictionary:
	return {"version": 1, "health": health, "crushed": crushed}

func deserialize(data: Dictionary) -> void:
	health = float(data.get("health", 100.0))
	crushed = bool(data.get("crushed", false))
