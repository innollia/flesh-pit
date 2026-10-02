extends SceneTree

## R1/V1: integrate the real field/chunk regrowth, without periodic squeeze.
## The baseline changes only regen_rate; geometry, tissue, depth and spray
## are identical. Sampling raw density keeps contraction out of healing time.
const OLD_RATE := 0.01
const STEP := 0.05
const FAR := Vector3(1000, 1000, 1000)
const CENTER := Vector3(0, 1, 0)
const SAMPLE := Vector3i(2, 2, 2)
const TISSUES := [0, 1, 2, 4]
const TISSUE_NAMES := ["compressive", "nerve", "legacy_fat", "membrane", "contractile"]
const DEPTH_CHUNKS := [2, 5, 7]
var _passed := 0
var _failed := 0

func _init() -> void:
	_run_timing_matrix()
	_run_protection_tests()
	_run_spray_tests()
	_run_safe_space_tests()
	_run_nonregenerating_tissue_tests()
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	quit(1 if _failed else 0)

func _assert(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + message)

func _field(rate: float, tissue: int, cc: Vector3i = Vector3i.ZERO) -> FDKTerrainField:
	var field := FDKTerrainField.new()
	field.config = FDKTerrainConfig.new()
	field.config.chunk_size = 6
	field.config.regen_rate = rate
	field.regen_rate_scale = func(p: Vector3) -> float:
		return FPWorldFeatures.regen_scale(p, CENTER, FPWorldFeatures.SHELL_THICKNESS)
	field.get_or_create_chunk(cc).fill_uniform(1.0, tissue)
	return field

func _density(chunk: FDKChunk, corner: Vector3i = SAMPLE) -> float:
	return chunk.get_density_at_corner(corner.x, corner.y, corner.z)

func _remove(chunk: FDKChunk, wide: bool) -> void:
	if wide:
		for z in range(1, 4):
			for y in range(1, 4):
				for x in range(1, 4):
					chunk.dig_cell(Vector3i(x, y, z), 1.0)
	else:
		chunk.dig_cell(SAMPLE, 1.0)

func _spray_near(field: FDKTerrainField, chunk: FDKChunk) -> int:
	# Melt an adjacent cell which does not share SAMPLE; SAMPLE is in its
	# real one-metre boost ring. Do not manufacture a boost in test data.
	var hit := chunk.position + (Vector3(SAMPLE) + Vector3(1.5, 0.5, 0.5)) * field.config.cell_size
	return field.spray_surface(hit, Vector3.UP, 0.1, 0.01)

func _measure(rate: float, tissue: int, cc: Vector3i, wide: bool, spray: bool) -> Dictionary:
	var field := _field(rate, tissue, cc)
	var chunk := field.get_chunk(cc)
	_remove(chunk, wide)
	if spray:
		_assert(_spray_near(field, chunk) == 1, "timing spray melts exactly one adjacent cell")
	_assert(_density(chunk) == 0.0, "timing starts at completely removed density")
	var s := field.config.chunk_size
	var depth := FPWorldFeatures.regen_scale(chunk.position + Vector3.ONE * s * field.config.cell_size * 0.5, CENTER, FPWorldFeatures.SHELL_THICKNESS)
	var neighbours := chunk._solid_neighbours(SAMPLE.x, SAMPLE.y, SAMPLE.z, s + 1)
	var crowd := FDKChunk.crowd_growth_factor(neighbours) if tissue == FDKTissueRules.COMPRESSIVE else 1.0
	var multiplier := FDKTissueRules.regen_multiplier(tissue) * (2.0 if spray else 1.0) * crowd * depth
	field.regenerate_all(STEP, FAR, 0.9)
	_assert(is_equal_approx(_density(chunk), rate * multiplier * STEP), "first tick preserves tissue x spray x crowd x depth and starts immediately")
	var ticks := 1
	while _density(chunk) < field.config.iso_level and ticks < 20000:
		field.regenerate_all(STEP, FAR, 0.9)
		ticks += 1
	_assert(_density(chunk) >= field.config.iso_level, "removed flesh continuously returns to solid")
	_assert(not chunk._has_contract, "healing measurement excludes periodic contraction")
	var result := {"seconds": ticks * STEP, "multiplier": multiplier, "neighbours": neighbours, "depth": depth}
	field.free()
	return result

func _run_timing_matrix() -> void:
	var current := FDKTerrainConfig.new().regen_rate
	print("R1 raw-density crossing, dt=%.2fs; old_rate=%.3f; current_rate=%.3f" % [STEP, OLD_RATE, current])
	print("| tissue | shell | void | spray | initial multiplier | old seconds | current seconds | ratio |")
	print("|---|---|---|---|---:|---:|---:|---:|")
	for tissue in TISSUES:
		for shell in range(DEPTH_CHUNKS.size()):
			for wide in [true, false]:
				for spray in [false, true]:
					var cc := Vector3i(DEPTH_CHUNKS[shell], 0, 0)
					var old := _measure(OLD_RATE, tissue, cc, wide, spray)
					var now := _measure(current, tissue, cc, wide, spray)
					var ratio: float = now.seconds / old.seconds
					var label := "%s shell%d %s spray=%s" % [TISSUE_NAMES[tissue], shell, "wide" if wide else "narrow", spray]
					print("| %s | %d | %s | %s | %.3f | %.2f | %.2f | %.3f |" % [TISSUE_NAMES[tissue], shell, "wide" if wide else "narrow", spray, now.multiplier, old.seconds, now.seconds, ratio])
					_assert(ratio >= 3.0, label + " takes at least three times the previous healing time")
					_assert(is_equal_approx(old.multiplier, now.multiplier), label + " preserves all rate multipliers")
					_assert(is_equal_approx(old.depth, 1.0 + shell * FDKDepthDanger.DANGER_STEP), label + " exercises the intended depth")
					if tissue == FDKTissueRules.COMPRESSIVE:
						_assert((now.neighbours == 0) if wide else (now.neighbours >= 2), label + " exercises actual wide/narrow neighbourhood")

func _run_protection_tests() -> void:
	for rate in [OLD_RATE, FDKTerrainConfig.new().regen_rate]:
		var field := _field(rate, FDKTissueRules.COMPRESSIVE)
		var chunk := field.get_chunk(Vector3i.ZERO)
		var outside := Vector3i(4, 2, 2)
		chunk.dig_cell(SAMPLE, 1.0)
		chunk.dig_cell(outside, 1.0)
		var body := Vector3(SAMPLE) * field.config.cell_size
		field.regenerate_all(1.0, body, 0.9)
		_assert(_density(chunk) == 0.0, "body sphere prevents regeneration inside 0.9m")
		_assert(_density(chunk, outside) > 0.0, "flesh outside body sphere continues to regenerate")
		chunk.dig_cell(outside, 1.0)
		var barriers := FDKBarrierField.new()
		var barrier := barriers.place(body, 0.9)
		field.regen_blockers = [Vector4(barrier.position.x, barrier.position.y, barrier.position.z, barrier.radius)]
		field.regenerate_all(1.0, FAR, 0.9)
		_assert(_density(chunk) == 0.0, "placed barrier prevents regeneration inside its radius")
		_assert(_density(chunk, outside) > 0.0, "flesh outside barrier continues to regenerate")
		field.regen_blockers.clear()
		field.regenerate_all(STEP, FAR, 0.9)
		_assert(_density(chunk) > 0.0, "regeneration resumes on first tick after protection leaves")
		field.regenerate_all(10000.0, FAR, 0.9)
		_assert(_density(chunk) == 1.0, "healing is capped at original density")
		barriers.free()
		field.free()

func _run_spray_tests() -> void:
	for rate in [OLD_RATE, FDKTerrainConfig.new().regen_rate]:
		var field := _field(rate, FDKTissueRules.COMPRESSIVE)
		var chunk := field.get_chunk(Vector3i.ZERO)
		_assert(_spray_near(field, chunk) == 1, "actual surface spray melts one cell")
		var melted_cell := SAMPLE + Vector3i.RIGHT
		var melted_center := (Vector3(melted_cell) + Vector3.ONE * 0.5) * field.config.cell_size
		_assert(field.is_sealed_at(melted_center), "sprayed cell is permanently sealed")
		_assert(not field.is_edible_at(melted_center), "sprayed cell stays inedible")
		chunk.dig_cell(SAMPLE, 1.0)
		field.regenerate_all(10000.0, FAR, 0.9)
		_assert(_density(chunk) > 0.0, "spray neighbour regrows")
		for z in range(2):
			for y in range(2):
				for x in range(2):
					_assert(_density(chunk, melted_cell + Vector3i(x, y, z)) == 0.0, "all sprayed-cell corners remain dissolved")
		field.free()

func _run_safe_space_tests() -> void:
	# Use the game's world sampler, retaining its original-density zeroes.
	var rests: Array[Vector3] = [Vector3(15, 1, 0)]
	for rate in [OLD_RATE, FDKTerrainConfig.new().regen_rate]:
		var field := FDKTerrainField.new()
		field.config = FDKTerrainConfig.new()
		field.config.chunk_size = 6
		field.config.regen_rate = rate
		field.density_sampler = func(p: Vector3) -> float:
			return FPWorldFeatures.world_density(p, FPRestroom.HALF, FPRestroom.DOOR_HALF_W, FPRestroom.DOOR_H, 0.04, 0.04, CENTER, FPWorldFeatures.OUTER_RADIUS, rests)
		for point in [CENTER, rests[0]]:
			var chunk := field.get_or_create_chunk(field.world_to_chunk_coord(point))
			var local := Vector3i(((point - chunk.position) / field.config.cell_size).round())
			_assert(_density(chunk, local) == 0.0, "restroom/shelter starts carved by real world sampler")
			# Remove solid flesh outside the safe interior in the same chunk.
			chunk.dig_cell(Vector3i(4, 2, 4), 1.0)
			field.regenerate_all(10000.0, FAR, 0.9)
			_assert(_density(chunk, local) == 0.0, "restroom/shelter never grows above original empty density")
		field.free()

func _run_nonregenerating_tissue_tests() -> void:
	for tissue in [FDKTissueRules.MEMBRANE, FDKTissueRules.MELTED]:
		var field := _field(FDKTerrainConfig.new().regen_rate, tissue)
		var chunk := field.get_chunk(Vector3i.ZERO)
		chunk.dig_cell(SAMPLE, 1.0)
		field.regenerate_all(10000.0, FAR, 0.9)
		_assert(_density(chunk) == 0.0, "existing zero-regeneration tissue rule remains intact")
		field.free()
