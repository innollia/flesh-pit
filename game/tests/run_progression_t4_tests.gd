extends SceneTree

## Tests for T4: immediate hair growth on flesh eating and legacy save migration.
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
	_test_immediate_hair_growth()
	_test_fractional_carry()
	_test_settle_zero_hair_gain()
	_test_toilet_lever_zero_hair_gain()
	_test_discard_stomach_preserves_hairs()
	_test_legacy_save_migration_once()
	_test_death_drop_recovery_no_duplicate()
	_test_legacy_death_drop_migration_once()
	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)

## 1. on_flesh_eaten(0, 300) should immediately grow 6 core hairs and 2 common hairs
## without needing flush or settle. Hairs are immediately available for mutation purchase.
func _test_immediate_hair_growth() -> void:
	var prog := FPProgression.new()
	_assert(prog.hairs("core") == 0 and prog.hairs(FPProgression.COMMON) == 0,
		"init: player starts with 0 hairs")
	prog.on_flesh_eaten(0, 300)
	_assert(prog.hairs("core") == 6,
		"immediate hair: eating 300 core units immediately grows 6 core hairs (got %d)" % prog.hairs("core"))
	_assert(prog.hairs(FPProgression.COMMON) == 2,
		"immediate hair: eating 300 core units immediately grows 2 common hairs (got %d)" % prog.hairs(FPProgression.COMMON))
	_assert(prog.mutation_tree.points("core") == 6 and prog.mutation_tree.points(FPProgression.COMMON) == 2,
		"immediate hair: mutation_tree points match immediately")
	# Can immediately buy a compressive mutation that costs 5 core hairs (e.g. M07 costs 5)
	_assert(prog.can_buy_mutation("M07"),
		"immediate hair: can buy mutation immediately without toilet flush")
	var bought := prog.buy_mutation("M07")
	_assert(bought and prog.has_mutation("M07") and prog.hairs("core") == 1,
		"immediate hair: mutation bought immediately, remaining core hairs 1")

## 2. Fractional carry: 25 units followed by 25 units accumulates to 1 hair.
func _test_fractional_carry() -> void:
	var prog := FPProgression.new()
	prog.on_flesh_eaten(0, 25)
	_assert(prog.hairs("core") == 0,
		"carry: 25 core units is below 50, 0 hairs grown")
	_assert(is_equal_approx(prog.hair_carry.get("core", 0.0), 25.0),
		"carry: 25 core units saved in hair_carry")
	prog.on_flesh_eaten(0, 25)
	_assert(prog.hairs("core") == 1,
		"carry: second 25 core units completes 50 units -> 1 core hair grown")
	_assert(is_equal_approx(prog.hair_carry.get("core", 0.0), 0.0),
		"carry: hair_carry core resets remainder to 0")

	# Mantle multiplier x2: 25 units * 2 = 50 weighted flesh -> 1 mantle hair
	prog.on_flesh_eaten(1, 25)
	_assert(prog.hairs("mantle") == 1,
		"carry: 25 mantle units with x2 multiplier gives 1 mantle hair immediately")

## 3. settle() awards teeth but hairs gain is always 0.
func _test_settle_zero_hair_gain() -> void:
	var prog := FPProgression.new()
	prog.on_flesh_eaten(0, 100) # grows 2 core hairs immediately
	var got := prog.settle(100.0)
	_assert(got["teeth"] == 8 and prog.teeth == 8,
		"settle: 100 flesh vomited yields 8 teeth in toilet tank")
	_assert(got["hairs"] == 0,
		"settle: settle hair gain is 0 under immediate hair growth rule")
	var by_pool: Dictionary = got.get("by_pool", {})
	_assert(int(by_pool.get("core", 0)) == 0 and int(by_pool.get(FPProgression.COMMON, 0)) == 0,
		"settle: by_pool has 0 for all hair pools")
	_assert(prog.hairs("core") == 2,
		"settle: previously grown hairs are retained after settle")

## 4. toilet_settlement press_lever emits lever_pulled with hair_gain = 0.
func _test_toilet_lever_zero_hair_gain() -> void:
	var prog := FPProgression.new()
	prog.on_flesh_eaten(0, 100)
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

## 5. Outdoor vomiting (discard_stomach) preserves already grown hairs.
func _test_discard_stomach_preserves_hairs() -> void:
	var prog := FPProgression.new()
	prog.on_flesh_eaten(0, 150) # 3 core hairs, 1 common hair
	_assert(prog.hairs("core") == 3 and prog.hairs(FPProgression.COMMON) == 1,
		"discard prep: 3 core hairs, 1 common hair grown")
	prog.discard_stomach()
	_assert(prog.hairs("core") == 3 and prog.hairs(FPProgression.COMMON) == 1,
		"discard: outdoor vomit does NOT lose already grown hairs")

## 6. Legacy v5 pending_hairs migration runs exactly once; no duplicates on reload.
func _test_legacy_save_migration_once() -> void:
	var old_save := {
		"version": 3,
		"teeth": 16,
		"pending_hairs": {"core": 100, "common": 150},
		"hair_carry": {"core": 0.0, "common": 0.0},
		"mutations": {"points": {"core": 0, "mantle": 0, "surface": 0, "common": 0}, "purchased": []}
	}
	var prog := FPProgression.new()
	prog.deserialize(old_save)
	_assert(prog.hairs("core") == 2,
		"legacy migration: 100 pending core flesh converted to 2 core hairs (got %d)" % prog.hairs("core"))
	_assert(prog.hairs(FPProgression.COMMON) == 1,
		"legacy migration: 150 pending common flesh converted to 1 common hair (got %d)" % prog.hairs(FPProgression.COMMON))

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

## 7. Death drop payload recovery does not duplicate hairs.
func _test_death_drop_recovery_no_duplicate() -> void:
	var prog := FPProgression.new()
	prog.on_flesh_eaten(0, 100) # 2 core hairs
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
