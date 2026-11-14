extends SceneTree

## Tests for T4: immediate hair growth on flesh eating and legacy save migration.
## Note: This suite verifies FPProgression and FPToiletSettlement component logic
## with constructed state dictionaries. Full main scene integration tests with
## 3D rendering, input, camera, restroom NPC interactions, and live binary user://save.bin
## files are scoped for T10.
##
## Run with:
##   godot_console --headless --path game --script res://tests/run_progression_t4_tests.gd

var _failures: int = 0
var _passed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _init() -> void:
	print("=== flesh-pit T4 progression tests ===")
	_test_immediate_hair_growth_and_surface_multiplier()
	_test_fractional_units_and_mixed_biome_carry()
	_test_immediate_mutation_consumption_and_preservation()
	_test_settle_zero_hair_gain()
	_test_toilet_lever_zero_hair_gain()
	_test_legacy_save_migration_once()
	_test_death_drop_recovery_no_duplicate()
	_test_legacy_death_drop_migration_once()
	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)

## Thresholds come from FPProgression: one biome hair per B weighted flesh, one
## common hair per C (decision 0012: 25 and 75, a cell is 2 flesh units).
const B := FPProgression.FLESH_PER_BIOME_HAIR
const C := FPProgression.FLESH_PER_COMMON_HAIR

func _hairs(weighted: float, per: float) -> int:
	return int(floor(weighted / per + 1e-6))

func _left(weighted: float, per: float) -> float:
	return weighted - float(_hairs(weighted, per)) * per

## 1. Immediate hair growth: eating flesh immediately grows hairs on the arm.
## Shell surface has x3 multiplier (B units * 3 = 3B weighted -> 3 surface hairs).
func _test_immediate_hair_growth_and_surface_multiplier() -> void:
	var prog := FPProgression.new()
	_assert(prog.hairs("core") == 0 and prog.hairs("surface") == 0 and prog.hairs(FPProgression.COMMON) == 0,
		"init: player starts with 0 hairs across all pools")
	_assert(is_equal_approx(B, 25.0) and is_equal_approx(C, 75.0),
		"thresholds: a biome hair per 25 weighted flesh, a common hair per 75 (decision 0012)")

	# Core: x1 multiplier. 6B units -> 6 core hairs and 6B / C common hairs.
	prog.on_flesh_eaten(0, 6.0 * B)
	_assert(prog.hairs("core") == 6,
		"immediate hair: eating 6 thresholds of core flesh immediately grows 6 core hairs (got %d)" % prog.hairs("core"))
	_assert(prog.hairs(FPProgression.COMMON) == _hairs(6.0 * B, C) and prog.hairs(FPProgression.COMMON) == 2,
		"immediate hair: the same flesh immediately grows 2 common hairs (got %d)" % prog.hairs(FPProgression.COMMON))
	_assert(prog.mutation_tree.points("core") == 6 and prog.mutation_tree.points(FPProgression.COMMON) == 2,
		"immediate hair: mutation_tree points match immediately")
	# one full stomach of core flesh (100 units = 50 cells): 4 core hairs, 1 common, 25 carried on
	var full := FPProgression.new()
	full.on_flesh_eaten(0, FPProgression.BASE_CAPACITY)
	_assert(full.hairs("core") == 4 and full.hairs(FPProgression.COMMON) == 1 and is_equal_approx(full.hair_carry[FPProgression.COMMON], 25.0),
		"a full stomach of core flesh grows 4 core hairs and 1 common, 25 carried (got %d, %d, %.1f)" % [full.hairs("core"), full.hairs(FPProgression.COMMON), full.hair_carry[FPProgression.COMMON]])

	# Surface: shell 2, multiplier x3. Eating B surface units -> 3B weighted -> 3 surface hairs.
	var prog_surf := FPProgression.new()
	prog_surf.on_flesh_eaten(2, B)
	_assert(prog_surf.hairs("surface") == 3,
		"surface x3: B surface units * 3 -> 3 surface hairs (got %d)" % prog_surf.hairs("surface"))
	_assert(prog_surf.hairs(FPProgression.COMMON) == _hairs(3.0 * B, C) and prog_surf.hairs(FPProgression.COMMON) == 1,
		"surface x3: the same weighted flesh yields 1 common hair (got %d)" % prog_surf.hairs(FPProgression.COMMON))
	_assert(is_equal_approx(prog_surf.hair_carry["surface"], 0.0),
		"surface x3: surface carry remainder is 0.0")
	_assert(is_equal_approx(prog_surf.hair_carry[FPProgression.COMMON], _left(3.0 * B, C)),
		"surface x3: common carry remainder is what the threshold leaves")

## 2. Fractional units and mixed biome carry remainders.
## In-game cell eating yields flesh_per_cell flesh units per cell (2.0).
## Eating across different shells accumulates separate biome carry and joint common carry.
func _test_fractional_units_and_mixed_biome_carry() -> void:
	var prog := FPProgression.new()
	var cell: float = FDKStomachConfig.new().flesh_per_cell
	_assert(is_equal_approx(cell, 2.0), "a whole cell is 2 flesh units (decision 0012)")

	# Ingest one single cell
	prog.on_flesh_eaten(0, cell)
	_assert(prog.hairs("core") == 0 and prog.hairs(FPProgression.COMMON) == 0,
		"fractional: one cell is below 1 hair threshold")
	_assert(is_equal_approx(prog.hair_carry["core"], cell),
		"fractional: core carry has one cell's units")
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], cell),
		"fractional: common carry has one cell's units")

	# Up to half a cell short of the threshold: still 0 hairs
	prog.on_flesh_eaten(0, B - 1.5 * cell)
	_assert(prog.hairs("core") == 0,
		"fractional: half a cell short of the threshold -> 0 core hairs")
	_assert(is_equal_approx(prog.hair_carry["core"], B - 0.5 * cell),
		"fractional: core carry is half a cell short of the threshold")

	# Ingest 0.5 cells -> completes the threshold -> 1 core hair!
	prog.on_flesh_eaten(0, 0.5 * cell)
	_assert(prog.hairs("core") == 1,
		"fractional: reaching the core threshold grants exactly 1 core hair")
	_assert(is_equal_approx(prog.hair_carry["core"], 0.0),
		"fractional: core carry resets remainder to 0.0")
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], B),
		"fractional: common carry has one biome threshold of units")

	# Mixed biomes: eat 0.4B mantle units (x2 = 0.8B weighted)
	prog.on_flesh_eaten(1, 0.4 * B)
	_assert(prog.hairs("mantle") == 0,
		"mixed biome: 0.8 thresholds of weighted mantle flesh -> 0 mantle hairs")
	_assert(is_equal_approx(prog.hair_carry["mantle"], 0.8 * B),
		"mixed biome: mantle carry is the weighted flesh")
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], 1.8 * B),
		"mixed biome: common carry accumulated across biomes")

	# Eat 0.4B surface units (x3 = 1.2B weighted)
	prog.on_flesh_eaten(2, 0.4 * B)
	_assert(prog.hairs("surface") == 1,
		"mixed biome: 1.2 thresholds of weighted surface flesh -> 1 surface hair")
	_assert(is_equal_approx(prog.hair_carry["surface"], 0.2 * B),
		"mixed biome: surface carry remainder is 0.2 thresholds")
	# Common: 1.8B + 1.2B = 3B = C -> 1 common hair, remainder 0.0
	_assert(prog.hairs(FPProgression.COMMON) == _hairs(3.0 * B, C) and prog.hairs(FPProgression.COMMON) == 1,
		"mixed biome: common carry reached its threshold -> 1 common hair granted")
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], _left(3.0 * B, C)),
		"mixed biome: common carry resets remainder")

## 3. Immediate mutation consumption and earned preservation.
## Hairs can be spent immediately on mutations without restroom visits.
## Earned mutations, unspent hairs, and carry fractions are preserved on outdoor vomiting.
func _test_immediate_mutation_consumption_and_preservation() -> void:
	var prog := FPProgression.new()
	var cost := int(FPProgression.POOL_COST[FPProgression.BIOME_CORE])
	var eaten := float(cost) * B
	var commons := _hairs(eaten, C)
	_assert(cost == 12 and int(FPProgression.POOL_COST[FPProgression.COMMON]) == 24 and int(FPProgression.POOL_COST[FPProgression.BIOME_MANTLE]) == 20 and int(FPProgression.POOL_COST[FPProgression.BIOME_SURFACE]) == 30,
		"hair prices: core 12, mantle 20, surface 30, common 24 (decision 0012)")
	_assert(is_equal_approx(eaten / FPProgression.BASE_CAPACITY, 3.0),
		"a core mutation is three full stomachs of core flesh")
	prog.on_flesh_eaten(0, eaten)
	_assert(prog.hairs("core") == cost, "buy test: a mutation's worth of core hairs earned")
	_assert(prog.can_buy_mutation("M07"), "buy test: compressive mutation M07 is affordable")

	# Purchase M07 immediately
	var bought := prog.buy_mutation("M07")
	_assert(bought and prog.has_mutation("M07"), "buy test: M07 purchased immediately")
	_assert(prog.hairs("core") == 0, "buy test: the core hairs are consumed, 0 remaining")
	_assert(prog.hairs(FPProgression.COMMON) == commons and commons == 4, "buy test: 4 common hairs remained unspent")
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], _left(eaten, C)), "buy test: common carry remainder preserved")

	# Outdoor vomiting (discard_stomach) must preserve purchased mutations and remaining points
	prog.discard_stomach()
	_assert(prog.has_mutation("M07"), "preservation: purchased mutation M07 preserved after discard_stomach")
	_assert(prog.hairs("core") == 0 and prog.hairs(FPProgression.COMMON) == commons,
		"preservation: remaining hairs preserved after discard_stomach")
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], _left(eaten, C)),
		"preservation: fractional carry preserved after discard_stomach")

## 4. settle() awards teeth based on vomited flesh, but hair gain is strictly 0.
func _test_settle_zero_hair_gain() -> void:
	var prog := FPProgression.new()
	prog.on_flesh_eaten(0, 100.0) # 100 / B core hairs grown immediately
	var got := prog.settle(100.0)
	_assert(got["teeth"] == 8 and prog.teeth == 8,
		"settle: 100 flesh vomited yields 8 teeth in toilet tank")
	_assert(got["hairs"] == 0,
		"settle: settle hair gain is strictly 0 under immediate hair growth rule")
	var by_pool: Dictionary = got.get("by_pool", {})
	_assert(int(by_pool.get("core", 0)) == 0 and int(by_pool.get(FPProgression.COMMON, 0)) == 0,
		"settle: by_pool has 0 for all hair pools")
	_assert(prog.hairs("core") == _hairs(100.0, B),
		"settle: previously grown hairs are retained untouched")

	# Repeated settle with 0 flesh
	var empty := prog.settle(0.0)
	_assert(empty["teeth"] == 0 and empty["hairs"] == 0,
		"settle: repeated empty settle awards 0 teeth and 0 hairs")
	_assert(prog.hairs("core") == _hairs(100.0, B),
		"settle: hairs unchanged after empty settle")

## 5. toilet_settlement press_lever emits lever_pulled with hair_gain = 0.
func _test_toilet_lever_zero_hair_gain() -> void:
	var prog := FPProgression.new()
	prog.on_flesh_eaten(0, 100.0)
	var toilet := FPToiletSettlement.new()
	toilet.vomit_into(100.0)
	var captured := {"teeth": -1, "hairs": -1}
	toilet.lever_pulled.connect(func(t, h):
		captured["teeth"] = t
		captured["hairs"] = h
	)
	var result := toilet.press_lever(prog)
	_assert(result["teeth"] == 8 and captured["teeth"] == 8,
		"toilet lever: teeth gained is 8")
	_assert(result["hairs"] == 0 and captured["hairs"] == 0,
		"toilet lever: lever_pulled signal hair_gain is 0")

	# Second pull of empty lever
	var empty := toilet.press_lever(prog)
	_assert(empty["teeth"] == 0 and empty["hairs"] == 0,
		"toilet lever: second empty lever press yields 0 teeth and 0 hairs")

## 6. Legacy v5 pending_hairs migration runs exactly once.
## The pending_hairs values in legacy v5 saves were already weighted flesh units.
## They are directly converted to hairs at the current thresholds (no cell factor).
func _test_legacy_save_migration_once() -> void:
	var old_save := {
		"version": 3,
		"teeth": 16,
		# Legacy weighted flesh: 100 core units, 150 common units
		"pending_hairs": {"core": 100, "common": 150},
		"hair_carry": {"core": 0.0, "common": 0.0},
		"mutations": {"points": {"core": 0, "mantle": 0, "surface": 0, "common": 0}, "purchased": []}
	}
	var prog := FPProgression.new()
	prog.deserialize(old_save)
	_assert(prog.hairs("core") == _hairs(100.0, B),
		"legacy migration: 100 pending core flesh converted directly to core hairs at the threshold (got %d)" % prog.hairs("core"))
	_assert(prog.hairs(FPProgression.COMMON) == _hairs(150.0, C),
		"legacy migration: 150 pending common flesh converted directly to common hairs at the threshold (got %d)" % prog.hairs(FPProgression.COMMON))

	# Serialize into new save
	var new_save := prog.serialize()
	_assert(bool(new_save.get("migrated_v5_hairs", false)) == true,
		"legacy migration: serialized new save has migrated_v5_hairs flag")

	# Re-deserialize into a fresh progression instance (save -> reload cycle)
	var prog2 := FPProgression.new()
	prog2.deserialize(new_save)
	_assert(prog2.hairs("core") == _hairs(100.0, B),
		"legacy migration: reloading new save does not duplicate core hairs (got %d)" % prog2.hairs("core"))
	_assert(prog2.hairs(FPProgression.COMMON) == _hairs(150.0, C),
		"legacy migration: reloading new save does not duplicate common hairs (got %d)" % prog2.hairs(FPProgression.COMMON))

	# Even if deserialize is called again on the same instance
	prog2.deserialize(new_save)
	_assert(prog2.hairs("core") == _hairs(100.0, B) and prog2.hairs(FPProgression.COMMON) == _hairs(150.0, C),
		"legacy migration: repeated deserialize on same instance does not duplicate hairs")

## 7. Death drop payload recovery does not duplicate hairs under new rules.
func _test_death_drop_recovery_no_duplicate() -> void:
	var prog := FPProgression.new()
	prog.on_flesh_eaten(0, 100.0)
	var grown := _hairs(100.0, B)
	_assert(prog.hairs("core") == grown and grown > 0, "death test: core hairs before death")
	var common := prog.hairs(FPProgression.COMMON)
	var payload := prog.take_death_payload(40.0)
	# half of the coloured hairs grown since the restroom stay on the body,
	# rounded down; the common ones stay on the arm (decision 0017)
	var left := int(floor(float(grown) * FPProgression.DEATH_HAIR_SHARE))
	_assert(left > 0 and prog.hairs("core") == grown - left, "death: %d of %d core hairs stay on the body" % [left, grown])
	_assert(FPProgression.payload_hairs(payload) == left, "death: the body holds exactly those hairs")
	_assert(prog.hairs(FPProgression.COMMON) == common, "death: common hairs are preserved on death")

	# Recover drop
	var fill := prog.restore_death_payload(payload)
	_assert(is_equal_approx(fill, 40.0), "recovery: stomach fill restored")
	_assert(prog.hairs("core") == grown, "recovery: hairs not duplicated on drop recovery (got %d)" % prog.hairs("core"))

	# Repeated recovery of the same payload
	prog.restore_death_payload(payload)
	_assert(prog.hairs("core") == grown, "recovery: repeated recovery gives 0 duplicate hairs")

## 8. Legacy death drop payload migration runs exactly once on recovery.
## Legacy death drops containing unmigrated pending_hairs are converted directly on first recovery.
func _test_legacy_death_drop_migration_once() -> void:
	var legacy_payload := {
		"stomach_fill": 100.0,
		"pending_hairs": {"core": 100, "common": 150},
		"barriers": 1
	}
	var prog := FPProgression.new()
	_assert(prog.hairs("core") == 0 and prog.hairs(FPProgression.COMMON) == 0,
		"legacy drop: starts with 0 hairs")
	var fill := prog.restore_death_payload(legacy_payload)
	_assert(is_equal_approx(fill, 100.0), "legacy drop: fill restored")
	_assert(prog.hairs("core") == _hairs(100.0, B),
		"legacy drop: unmigrated pending hairs in legacy payload granted on recovery (core %d)" % prog.hairs("core"))
	_assert(prog.hairs(FPProgression.COMMON) == _hairs(150.0, C),
		"legacy drop: unmigrated pending hairs in legacy payload granted on recovery (common %d)" % prog.hairs(FPProgression.COMMON))

	# Repeated recovery of legacy payload
	prog.restore_death_payload(legacy_payload)
	_assert(prog.hairs("core") == _hairs(100.0, B) and prog.hairs(FPProgression.COMMON) == _hairs(150.0, C),
		"legacy drop: repeated recovery of migrated legacy payload yields 0 duplicate hairs")
