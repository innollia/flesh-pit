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

## 1. Immediate hair growth: eating flesh immediately grows hairs on the arm.
## Shell surface has x3 multiplier (50 units * 3 = 150 weighted -> 3 surface, 1 common).
func _test_immediate_hair_growth_and_surface_multiplier() -> void:
	var prog := FPProgression.new()
	_assert(prog.hairs("core") == 0 and prog.hairs("surface") == 0 and prog.hairs(FPProgression.COMMON) == 0,
		"init: player starts with 0 hairs across all pools")

	# Core: x1 multiplier. 300 units -> 300 weighted -> 6 core, 2 common.
	prog.on_flesh_eaten(0, 300)
	_assert(prog.hairs("core") == 6,
		"immediate hair: eating 300 core units immediately grows 6 core hairs (got %d)" % prog.hairs("core"))
	_assert(prog.hairs(FPProgression.COMMON) == 2,
		"immediate hair: eating 300 core units immediately grows 2 common hairs (got %d)" % prog.hairs(FPProgression.COMMON))
	_assert(prog.mutation_tree.points("core") == 6 and prog.mutation_tree.points(FPProgression.COMMON) == 2,
		"immediate hair: mutation_tree points match immediately")

	# Surface: shell 2, multiplier x3. Eating 50 surface units -> 150 weighted -> 3 surface hairs, 1 common hair.
	var prog_surf := FPProgression.new()
	prog_surf.on_flesh_eaten(2, 50.0)
	_assert(prog_surf.hairs("surface") == 3,
		"surface x3: 50 surface units * 3 = 150 weighted -> 3 surface hairs (got %d)" % prog_surf.hairs("surface"))
	_assert(prog_surf.hairs(FPProgression.COMMON) == 1,
		"surface x3: 150 weighted flesh yields 1 common hair (got %d)" % prog_surf.hairs(FPProgression.COMMON))
	_assert(is_equal_approx(prog_surf.hair_carry["surface"], 0.0),
		"surface x3: surface carry remainder is 0.0")
	_assert(is_equal_approx(prog_surf.hair_carry[FPProgression.COMMON], 0.0),
		"surface x3: common carry remainder is 0.0")

## 2. Fractional units and mixed biome carry remainders.
## In-game cell eating yields 4.0 flesh units per cell (flesh_per_cell).
## Eating across different shells accumulates separate biome carry and joint common carry.
func _test_fractional_units_and_mixed_biome_carry() -> void:
	var prog := FPProgression.new()

	# Ingest 4.0 core units (equivalent to 1 single cell eaten)
	prog.on_flesh_eaten(0, 4.0)
	_assert(prog.hairs("core") == 0 and prog.hairs(FPProgression.COMMON) == 0,
		"fractional: 4.0 units is below 1 hair threshold")
	_assert(is_equal_approx(prog.hair_carry["core"], 4.0),
		"fractional: core carry has 4.0 units")
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], 4.0),
		"fractional: common carry has 4.0 units")

	# Ingest 11 more cells = 44.0 units -> total core 48.0 (still 0 hairs)
	prog.on_flesh_eaten(0, 44.0)
	_assert(prog.hairs("core") == 0,
		"fractional: 48.0 core units total -> 0 core hairs")
	_assert(is_equal_approx(prog.hair_carry["core"], 48.0),
		"fractional: core carry has 48.0 units")

	# Ingest 0.5 cells = 2.0 units -> completes 50.0 units -> 1 core hair!
	prog.on_flesh_eaten(0, 2.0)
	_assert(prog.hairs("core") == 1,
		"fractional: reaching 50.0 core units grants exactly 1 core hair")
	_assert(is_equal_approx(prog.hair_carry["core"], 0.0),
		"fractional: core carry resets remainder to 0.0")
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], 50.0),
		"fractional: common carry has 50.0 units")

	# Mixed biomes: eat 20 mantle units (x2 = 40 weighted)
	prog.on_flesh_eaten(1, 20.0)
	_assert(prog.hairs("mantle") == 0,
		"mixed biome: 40 weighted mantle units -> 0 mantle hairs")
	_assert(is_equal_approx(prog.hair_carry["mantle"], 40.0),
		"mixed biome: mantle carry is 40.0")
	# Common carry is now 50.0 + 40.0 = 90.0
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], 90.0),
		"mixed biome: common carry accumulated 90.0")

	# Eat 20 surface units (x3 = 60 weighted)
	prog.on_flesh_eaten(2, 20.0)
	# Surface: 60 / 50 = 1 surface hair, carry remainder 10.0
	_assert(prog.hairs("surface") == 1,
		"mixed biome: 60 weighted surface units -> 1 surface hair")
	_assert(is_equal_approx(prog.hair_carry["surface"], 10.0),
		"mixed biome: surface carry remainder is 10.0")
	# Common: 90.0 + 60.0 = 150.0 -> 1 common hair! remainder 0.0
	_assert(prog.hairs(FPProgression.COMMON) == 1,
		"mixed biome: common carry reached 150.0 -> 1 common hair granted")
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], 0.0),
		"mixed biome: common carry resets remainder to 0.0")

## 3. Immediate mutation consumption and earned preservation.
## Hairs can be spent immediately on mutations without restroom visits.
## Earned mutations, unspent hairs, and carry fractions are preserved on outdoor vomiting.
func _test_immediate_mutation_consumption_and_preservation() -> void:
	var prog := FPProgression.new()
	# Eat 250 core units -> 5 core hairs, 1 common hair (100 common carry)
	prog.on_flesh_eaten(0, 250.0)
	_assert(prog.hairs("core") == 5, "buy test: 5 core hairs earned")
	_assert(prog.can_buy_mutation("M07"), "buy test: compressive mutation M07 (cost 5) is affordable")

	# Purchase M07 immediately
	var bought := prog.buy_mutation("M07")
	_assert(bought and prog.has_mutation("M07"), "buy test: M07 purchased immediately")
	_assert(prog.hairs("core") == 0, "buy test: 5 core hairs consumed, 0 remaining")
	_assert(prog.hairs(FPProgression.COMMON) == 1, "buy test: 1 common hair remained unspent")
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], 100.0), "buy test: common carry remainder preserved")

	# Outdoor vomiting (discard_stomach) must preserve purchased mutations and remaining points
	prog.discard_stomach()
	_assert(prog.has_mutation("M07"), "preservation: purchased mutation M07 preserved after discard_stomach")
	_assert(prog.hairs("core") == 0 and prog.hairs(FPProgression.COMMON) == 1,
		"preservation: remaining hairs preserved after discard_stomach")
	_assert(is_equal_approx(prog.hair_carry[FPProgression.COMMON], 100.0),
		"preservation: fractional carry preserved after discard_stomach")

## 4. settle() awards teeth based on vomited flesh, but hair gain is strictly 0.
func _test_settle_zero_hair_gain() -> void:
	var prog := FPProgression.new()
	prog.on_flesh_eaten(0, 100.0) # 2 core hairs grown immediately
	var got := prog.settle(100.0)
	_assert(got["teeth"] == 8 and prog.teeth == 8,
		"settle: 100 flesh vomited yields 8 teeth in toilet tank")
	_assert(got["hairs"] == 0,
		"settle: settle hair gain is strictly 0 under immediate hair growth rule")
	var by_pool: Dictionary = got.get("by_pool", {})
	_assert(int(by_pool.get("core", 0)) == 0 and int(by_pool.get(FPProgression.COMMON, 0)) == 0,
		"settle: by_pool has 0 for all hair pools")
	_assert(prog.hairs("core") == 2,
		"settle: previously grown hairs are retained untouched")

	# Repeated settle with 0 flesh
	var empty := prog.settle(0.0)
	_assert(empty["teeth"] == 0 and empty["hairs"] == 0,
		"settle: repeated empty settle awards 0 teeth and 0 hairs")
	_assert(prog.hairs("core") == 2,
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
## They are directly converted to hairs (without multiplying by new cell factor 4).
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
	_assert(prog.hairs("core") == 2,
		"legacy migration: 100 pending core flesh converted directly to 2 core hairs (got %d)" % prog.hairs("core"))
	_assert(prog.hairs(FPProgression.COMMON) == 1,
		"legacy migration: 150 pending common flesh converted directly to 1 common hair (got %d)" % prog.hairs(FPProgression.COMMON))

	# Serialize into new save
	var new_save := prog.serialize()
	_assert(bool(new_save.get("migrated_v5_hairs", false)) == true,
		"legacy migration: serialized new save has migrated_v5_hairs flag")

	# Re-deserialize into a fresh progression instance (save -> reload cycle)
	var prog2 := FPProgression.new()
	prog2.deserialize(new_save)
	_assert(prog2.hairs("core") == 2,
		"legacy migration: reloading new save does not duplicate core hairs (got %d)" % prog2.hairs("core"))
	_assert(prog2.hairs(FPProgression.COMMON) == 1,
		"legacy migration: reloading new save does not duplicate common hairs (got %d)" % prog2.hairs(FPProgression.COMMON))

	# Even if deserialize is called again on the same instance
	prog2.deserialize(new_save)
	_assert(prog2.hairs("core") == 2 and prog2.hairs(FPProgression.COMMON) == 1,
		"legacy migration: repeated deserialize on same instance does not duplicate hairs")

## 7. Death drop payload recovery does not duplicate hairs under new rules.
func _test_death_drop_recovery_no_duplicate() -> void:
	var prog := FPProgression.new()
	prog.on_flesh_eaten(0, 100.0) # 2 core hairs
	_assert(prog.hairs("core") == 2, "death test: 2 core hairs before death")
	var payload := prog.take_death_payload(40.0)
	_assert(prog.hairs("core") == 2, "death: hairs are preserved on death")

	# Recover drop
	var fill := prog.restore_death_payload(payload)
	_assert(is_equal_approx(fill, 40.0), "recovery: stomach fill restored")
	_assert(prog.hairs("core") == 2, "recovery: hairs not duplicated on drop recovery (got %d)" % prog.hairs("core"))

	# Repeated recovery of the same payload
	prog.restore_death_payload(payload)
	_assert(prog.hairs("core") == 2, "recovery: repeated recovery gives 0 duplicate hairs")

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
	_assert(prog.hairs("core") == 2,
		"legacy drop: unmigrated pending hairs in legacy payload granted on recovery (core %d)" % prog.hairs("core"))
	_assert(prog.hairs(FPProgression.COMMON) == 1,
		"legacy drop: unmigrated pending hairs in legacy payload granted on recovery (common %d)" % prog.hairs(FPProgression.COMMON))

	# Repeated recovery of legacy payload
	prog.restore_death_payload(legacy_payload)
	_assert(prog.hairs("core") == 2 and prog.hairs(FPProgression.COMMON) == 1,
		"legacy drop: repeated recovery of migrated legacy payload yields 0 duplicate hairs")
