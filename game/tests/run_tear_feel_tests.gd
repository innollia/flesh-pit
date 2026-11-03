extends SceneTree

## Tear feel (fp_tear_feel.gd, 2026-11-03 "살이 뿅 뿅 사라짐"): the visuals of
## a tear ride on the real removal and never stand in for it.
## - at the real cell_torn the density is already gone, and the same frame
##   already carries the snap, the wet rim, strands and the fistful in hand
## - work stays bounded however fast tears come (strand pieces, wound slots,
##   gore pieces), and everything settles back to rest
## - the jolt rides on restorable camera offsets: none left behind
## Timings of the real hole: run_eating_publication_timing_tests.gd.

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://capture-tear-feel-tests.bin"
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func snap_param() -> float:
	return float(FDKChunk.terrain_material(0).get_shader_parameter("snap_age"))

func wound_params() -> Array:
	var v = FDKChunk.terrain_material(2).get_shader_parameter("wounds")
	var out: Array = []
	if v != null:
		for w in v:
			if (w as Vector4).w > 0.0:
				out.append(w)
	return out

func run() -> void:
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(true, true)
	m.player.global_position = Vector3(0.0, 0.95, 0.2)
	await frames(30)
	var feel = m.tear_feel
	check(feel != null, "main has the tear feel")
	var cam: Camera3D = m.player.camera
	var rest_h := cam.h_offset
	var rest_v := cam.v_offset
	var rest_fov := cam.fov
	# --- a real tear through the chewer: removal first, visuals the same frame
	var p := Vector3(0.25, 1.25, FPRestroom.HALF.z + 0.75)
	check(m.terrain.density_at(p) >= m.terrain_config.iso_level, "fixture cell is flesh")
	var seen := {}
	var on_torn := func(at: Vector3) -> void:
		seen["density"] = m.terrain.density_at(at)
		seen["frame"] = Engine.get_process_frames()
	m.chewer.cell_torn.connect(on_torn, CONNECT_ONE_SHOT)
	var gore_before: int = m.gore.live_count()
	m.chewer.try_start(p)
	m.chewer.process_chew(10.0)
	check(seen.has("density") and float(seen.density) < m.terrain_config.iso_level, "the real density is gone when the tear fires (%s)" % str(seen.get("density")))
	check(is_equal_approx(feel.snap_age(), 0.0) and is_equal_approx(snap_param(), 0.0), "the snap starts on the tear frame itself (param %.2f)" % snap_param())
	check(wound_params().size() == 1 and is_equal_approx((wound_params()[0] as Vector4).w, 1.0), "the fresh rim is wet on the tear frame")
	check(feel.live_strands() == feel.STRANDS_PER_TEAR, "strands spring from the rim (%d)" % feel.live_strands())
	check(m.gore.live_count() >= gore_before + 30, "a big spray of bits and blood (%d new)" % (m.gore.live_count() - gore_before))
	var chunk: Node3D = m.hands_rig.torn_chunk()
	check(chunk != null, "the fist holds the torn chunk")
	if chunk != null:
		var box: AABB = (chunk as MeshInstance3D).get_aabb()
		check(box.size.x >= 0.09 and box.size.y >= 0.08, "a fistful, wider than the old 6 cm pebble (%s)" % str(box.size))
	m.chewer.stop()
	await frames(2)
	check(feel.jolt_offset() != Vector2.ZERO or feel.jolt_fov() != 1.0, "the view jolts at the snap")
	# --- burst of tears: work stays bounded
	var max_writes := 0
	var max_strands := 0
	for i in range(60):
		feel.on_tear(p + Vector3(0.5 * (i % 7), 0.25 * (i % 3), 0.0), cam.global_position)
		feel.tick(1.0 / 60.0)
		max_writes = maxi(max_writes, feel.last_strand_writes)
		max_strands = maxi(max_strands, feel.live_strands())
	check(max_strands <= feel.MAX_STRANDS / 2, "strands bounded (%d live)" % max_strands)
	check(max_writes <= feel.MAX_STRANDS, "strand instance writes bounded (%d a tick)" % max_writes)
	check(feel.wound_count() <= feel.MAX_WOUNDS and wound_params().size() <= feel.MAX_WOUNDS, "wound slots bounded (%d)" % feel.wound_count())
	check(m.gore.live_count() <= m.gore.MAX_BITS + m.gore.MAX_DROPS, "gore pieces bounded (%d)" % m.gore.live_count())
	# --- everything settles back
	var t := 0.0
	while t < 1.5:
		await process_frame
		t += get_root().get_process_delta_time()
	check(feel.snap_age() >= feel.SNAP_END and snap_param() >= feel.SNAP_END, "the snap ends (param %.2f)" % snap_param())
	check(feel.live_strands() == 0 and feel.last_strand_writes == 0, "the strands are gone")
	check(feel.jolt_offset() == Vector2.ZERO and is_equal_approx(feel.jolt_fov(), 1.0), "the jolt is over")
	check(is_equal_approx(cam.h_offset, rest_h) and is_equal_approx(cam.v_offset, rest_v) and absf(cam.fov - rest_fov) < 0.01, "no camera offset left behind (h %.4f v %.4f fov %.2f -> %.2f)" % [cam.h_offset, cam.v_offset, rest_fov, cam.fov])
	check(m.hands_rig.torn_chunk() == null, "the chunk is gone from the hand")
	for i in range(int(feel.WOUND_LIFE * 10.0) + 5):
		feel.tick(0.1)
	check(feel.wound_count() == 0 and wound_params().is_empty(), "the wet rims dry up")
	print("%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
