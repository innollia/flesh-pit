extends SceneTree

## Shape of the pulled flesh (2026-11-08 "살점을 팔때 *처럼 살 잡아당겨지는게
## 1인칭에서 안예쁨"). The pull must read as one rounded wet stretch toward
## the hands, not a star:
## - the shader draws FDKPullShape (same constants, no angular term, no
##   sideways gather into the grip)
## - sampled round the grip, the offset has no sideways part, no variation
##   with angle (no rays), a rounded top and a smooth monotone falloff
## - the strain shading depends on distance alone
## - the same measures flag the old pull (gather + 17 radial fibres), so they
##   can tell a star from a dome
## Real removal and its timing: run_tear_feel_tests.gd.

const SHADER := "res://addons/flesh_dig_kit/terrain/fdk_terrain_surface.gdshader"
const TOWARD := Vector3(0.0, 0.0, 1.0)
const RADIUS := 1.0
const ANGLES := 72
const RINGS := 40

var passed := 0
var failed := 0

func _init() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func ring_point(r: float, a: float) -> Vector3:
	return Vector3(cos(a), sin(a), 0.0) * r

## The pull as the shader drew it before 2026-11-08 (gather + tight cone).
func old_offset(rel: Vector3, amount: float, time: float) -> Vector3:
	var pd := rel.length()
	var pf := smoothstep(RADIUS, 0.0, pd)
	var dent := FDKPullShape.dent_amount(amount)
	var pull := FDKPullShape.pull_amount(amount)
	var pn := TOWARD
	var grip := -pn * pf * (0.16 * dent - 0.34 * pull * pf)
	grip -= rel * pf * 0.24 * pull
	grip += pn * pf * pull * (0.02 + 0.03 * pull) * sin(time * 47.0 + pd * 20.0)
	return grip

## The old red-fibre weight of the strain shading (0..1).
func old_fibre(rel: Vector3, amount: float) -> float:
	var pdist := rel.length()
	var tension := smoothstep(0.3, 1.0, amount) * smoothstep(RADIUS, 0.05, pdist)
	var ang := atan2(rel.y, rel.x)
	var wav := ang * 17.0 + 1.7 * sin(ang * 5.0 + pdist * 7.0) + pdist * 9.0
	var fib := 0.5 + 0.5 * sin(wav)
	return tension * tension * smoothstep(0.5, 0.92, fib)

## {sideways, angular, rise, roughness, top} of an offset function over rings
## round the grip. sideways: largest offset across `toward` (pinch creases);
## angular: largest spread of the lift round one ring (rays); rise: largest
## outward increase of the mean lift (a ridge); roughness: largest second
## difference of the mean lift (a kink); top: lift at 2 cm over lift at 0.
func measure(f: Callable) -> Dictionary:
	var sideways := 0.0
	var angular := 0.0
	var means: Array = []
	for i in range(RINGS + 1):
		var r := RADIUS * 1.1 * float(i) / RINGS
		var lo := INF
		var hi := -INF
		var sum := 0.0
		for k in range(ANGLES):
			var o: Vector3 = f.call(ring_point(r, TAU * k / ANGLES))
			var lift := o.dot(TOWARD)
			sideways = maxf(sideways, (o - TOWARD * lift).length())
			lo = minf(lo, lift)
			hi = maxf(hi, lift)
			sum += lift
		angular = maxf(angular, hi - lo)
		means.append(sum / ANGLES)
	var rise := 0.0
	var rough := 0.0
	for i in range(1, means.size()):
		rise = maxf(rise, absf(float(means[i])) - absf(float(means[i - 1])))
		if i + 1 < means.size():
			rough = maxf(rough, absf(float(means[i + 1]) - 2.0 * float(means[i]) + float(means[i - 1])))
	var top := 0.0
	var at0: float = (f.call(Vector3.ZERO) as Vector3).dot(TOWARD)
	if absf(at0) > 0.0001:
		top = (f.call(ring_point(0.02, 0.3)) as Vector3).dot(TOWARD) / at0
	# a sign change along the profile is a trough/ridge ring too
	for i in range(1, means.size()):
		if float(means[i]) * float(means[i - 1]) < -0.0000001:
			rise = maxf(rise, absf(float(means[i])))
	return {"sideways": sideways, "angular": angular, "ridge": rise, "rough": rough, "top": top, "peak": at0}

func shader_vertex_and_fragment() -> PackedStringArray:
	var code := FileAccess.get_file_as_string(SHADER)
	var v := code.find("void vertex()")
	var fr := code.find("void fragment()")
	return PackedStringArray([code.substr(v, fr - v), code.substr(fr)])

func run() -> void:
	# --- the shader draws FDKPullShape
	var parts := shader_vertex_and_fragment()
	var vtx := parts[0]
	var frag := parts[1]
	check(vtx.contains("FDKPullShape.offset"), "the shader's pull names its measured mirror")
	check(vtx.contains("(-%.2f * dent + %.2f * pull) * bell" % [FDKPullShape.DENT, FDKPullShape.LIFT]) and vtx.contains("mix(wide, dome, pull)"), "dent, lift and bell match FDKPullShape")
	check(vtx.contains("press_radius * %.1f" % FDKPullShape.DOME_SCALE) and vtx.contains("%.3f * pull * pull * bell" % FDKPullShape.QUIVER), "dome width and quiver match FDKPullShape")
	check(not vtx.contains("side * pf"), "no sideways gather of the skin into the grip")
	check(not frag.contains("atan("), "the strain shading has no angle (no radial fibres)")
	check(not vtx.contains("pd * 20.0"), "the quiver has no distance phase (no rings)")
	# --- the pull, measured round the grip through the tear
	for amount in [0.2, 0.5, 0.75, 0.95, 1.0]:
		for time in [0.0, 0.37]:
			var s := measure(func(rel: Vector3) -> Vector3: return FDKPullShape.offset(rel, TOWARD, amount, RADIUS, time))
			var tag := "amount %.2f t %.2f" % [amount, time]
			check(float(s.sideways) < 0.00001, "%s: nothing moves sideways (%.4f m)" % [tag, s.sideways])
			check(float(s.angular) < 0.00001, "%s: the same lift all round each ring (%.4f m)" % [tag, s.angular])
			check(float(s.ridge) < 0.00001, "%s: the offset fades outward without a ridge or trough (%.4f)" % [tag, s.ridge])
			if absf(float(s.peak)) > 0.001:
				check(float(s.top) > 0.995, "%s: a rounded top, not a point (%.4f)" % [tag, s.top])
			check(float(s.rough) < 0.012, "%s: a smooth falloff (second difference %.4f)" % [tag, s.rough])
	var full := measure(func(rel: Vector3) -> Vector3: return FDKPullShape.offset(rel, TOWARD, 0.95, RADIUS, 0.0))
	check(float(full.peak) > 0.2, "the flesh is still drawn out toward the hands (%.3f m)" % full.peak)
	var dent := measure(func(rel: Vector3) -> Vector3: return FDKPullShape.offset(rel, TOWARD, 0.3, RADIUS, 0.0))
	check(float(dent.peak) < -0.1, "it still dents first (%.3f m)" % dent.peak)
	# --- strain shading: distance alone
	var strain_spread := 0.0
	var strain_peak := 0.0
	for i in range(RINGS + 1):
		var r := RADIUS * 1.1 * float(i) / RINGS
		var lo := INF
		var hi := -INF
		for k in range(ANGLES):
			var w := FDKPullShape.strain(ring_point(r, TAU * k / ANGLES), 0.95, RADIUS)
			lo = minf(lo, w)
			hi = maxf(hi, w)
		strain_spread = maxf(strain_spread, hi - lo)
		strain_peak = maxf(strain_peak, hi)
	check(strain_spread < 0.00001, "strain shading has no rays (spread %.4f)" % strain_spread)
	check(strain_peak > 0.8, "the stretched skin still shows its strain (%.2f)" % strain_peak)
	# --- the measures catch the old star
	var old := measure(func(rel: Vector3) -> Vector3: return old_offset(rel, 0.95, 0.0))
	check(float(old.sideways) > 0.02, "old pull's sideways gather is caught (%.3f m)" % old.sideways)
	var old_spread := 0.0
	for i in range(1, RINGS):
		var r := RADIUS * float(i) / RINGS
		var lo := INF
		var hi := -INF
		for k in range(ANGLES):
			var w := old_fibre(ring_point(r, TAU * k / ANGLES), 0.95)
			lo = minf(lo, w)
			hi = maxf(hi, w)
		old_spread = maxf(old_spread, hi - lo)
	check(old_spread > 0.3, "old radial fibres are caught (spread %.2f)" % old_spread)
	print("%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
