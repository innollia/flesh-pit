extends SceneTree

## Restroom shell seams: looks along the ceiling's four edges and the upper
## wall corners from inside the closed room and counts the pixels on a seam
## that are clearly darker than the tile on both sides of it and not the
## room's own cool grey (whatever lies outside the room showing through a
## crack between the planes). Run WINDOWED:
##   godot_console --path game --resolution 960x540 --fixed-fps 60
##     --script res://tests/capture_room_seams.gd -- <out_dir> <tag>
## Prints one "SEAM <view> <leak pixels>" line per view and the total, saves
## the three worst views as <out_dir>/<tag>_<view>.png (every view with a
## later argument "all"), exits 1 when any view leaks or is a blank frame.
## With the argument "control" the ceiling wears the unsnapped flat material
## it had before the fix: that run must find leaks (it exits 1 when it finds
## none), which shows the counter sees what it is for. Isolated save slot and
## key file.

const DARKER := 0.78 # a seam pixel under this share of both sides, and warm, is a leak
const SIDE_PX := 6
const BAND_PX := 2

var m: Node3D
var out_dir := ""
var tag := "seams"
var cam: Camera3D

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://capture-room-seams")
	tag = args[1] if args.size() > 1 else "seams"
	DirAccess.make_dir_recursive_absolute(out_dir)
	run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func lum(img: Image, p: Vector2) -> float:
	var x := int(round(p.x))
	var y := int(round(p.y))
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return -1.0
	var c := img.get_pixel(x, y)
	return (c.r + c.g + c.b) / 3.0

## The room's tile and ceiling are cool greys (red never above green), and
## so is the shade of a tile's bevel in a wall corner. What shows through a
## crack is flesh or the dark behind it: warm, or next to black.
func outside_colour(img: Image, p: Vector2) -> bool:
	var c := img.get_pixel(int(round(p.x)), int(round(p.y)))
	return c.r > c.g + 0.012 or (c.r + c.g + c.b) / 3.0 < 0.12

## Leak pixels along the seam a -> b in `img` as seen by `cam`.
func seam_leaks(img: Image, a: Vector3, b: Vector3, seen: Dictionary) -> void:
	var steps := int(a.distance_to(b) / 0.01)
	for i in range(steps + 1):
		var w := a.lerp(b, float(i) / float(steps))
		var w2 := a.lerp(b, float(mini(i + 1, steps)) / float(steps)) if i < steps else a.lerp(b, float(i - 1) / float(steps))
		if cam.is_position_behind(w) or cam.is_position_behind(w2):
			continue
		var p := cam.unproject_position(w)
		var dir := cam.unproject_position(w2) - p
		if dir.length() < 0.001:
			continue
		var n := dir.normalized().orthogonal()
		var ref_a := lum(img, p + n * SIDE_PX)
		var ref_b := lum(img, p - n * SIDE_PX)
		if ref_a < 0.0 or ref_b < 0.0:
			continue
		var floor_l := minf(ref_a, ref_b) * DARKER
		for s in range(-BAND_PX, BAND_PX + 1):
			var q := p + n * float(s)
			var l := lum(img, q)
			if l >= 0.0 and l < floor_l and outside_colour(img, q):
				seen[Vector2i(int(round(q.x)), int(round(q.y)))] = true

func run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_room_seams.json"
	m.save_path = "user://capture-room-seams.bin"
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.player.set_physics_process(false)
	m.player.visible = false
	cam = Camera3D.new()
	cam.near = 0.02
	cam.fov = 75.0
	cam.cull_mask &= ~FPMirrorReflection.MIRROR_BODY_LAYER
	root.add_child(cam)
	m.restroom.set_door_open(false, true)
	m.apply_atmosphere_now()
	var control := OS.get_cmdline_user_args().has("control")
	if control:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.92, 0.92, 0.90)
		plain.roughness = 1.0
		(m.restroom.get_node("Tiles") as MeshInstance3D).mesh.surface_set_material(2, plain)
	await frames(20)
	var h := FPRestroom.HALF
	var top := 2.0 * h.y
	var seams: Array = [
		[Vector3(-h.x, top, -h.z), Vector3(h.x, top, -h.z)], [Vector3(-h.x, top, h.z), Vector3(h.x, top, h.z)],
		[Vector3(-h.x, top, -h.z), Vector3(-h.x, top, h.z)], [Vector3(h.x, top, -h.z), Vector3(h.x, top, h.z)],
	]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			seams.append([Vector3(sx * h.x, 2.15, sz * h.z), Vector3(sx * h.x, top, sz * h.z)])
	var results: Array = []
	var total := 0
	var blank := 0
	var eyes := [Vector3(0.0, 1.0, 0.0), Vector3(1.2, 0.9, 0.6), Vector3(-1.3, 1.25, -0.5), Vector3(0.3, 1.6, 0.3)]
	for e in range(eyes.size()):
		for k in range(12):
			var yaw := TAU * float(k) / 12.0 + 0.07 * float(e)
			var pitch := 0.55 + 0.11 * float(e % 2)
			cam.global_position = eyes[e]
			cam.rotation = Vector3(pitch, yaw, 0.0)
			cam.make_current()
			await frames(2)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			# a frame with nothing in it (a renderer that drew no scene) is
			# not a clean seam
			var small := img.duplicate() as Image
			small.resize(32, 18, Image.INTERPOLATE_BILINEAR)
			var lo := 1.0
			var hi := 0.0
			for py in range(18):
				for px in range(32):
					var l0 := lum(small, Vector2(px, py))
					lo = minf(lo, l0)
					hi = maxf(hi, l0)
			if hi - lo < 0.05:
				blank += 1
			var seen := {}
			for s in seams:
				seam_leaks(img, s[0], s[1], seen)
			var view := "e%d_y%02d" % [e, k]
			print("SEAM %s %d" % [view, seen.size()])
			total += seen.size()
			results.append([seen.size(), view, img])
	results.sort_custom(func(a, b): return a[0] > b[0])
	var keep := results.size() if OS.get_cmdline_user_args().has("all") else 3
	for i in range(mini(keep, results.size())):
		(results[i][2] as Image).save_png(out_dir.path_join("%s_%s.png" % [tag, results[i][1]]))
		print("SHOT ", out_dir.path_join("%s_%s.png" % [tag, results[i][1]]))
	print("--- room seams%s: %d leak pixels over %d views, %d blank ---" % [" (control)" if control else "", total, results.size(), blank])
	for f in ["user://capture-room-seams.bin", "user://keybinds_test_room_seams.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	m.queue_free()
	await frames(2)
	if control:
		quit(1 if total == 0 or blank > 0 else 0)
	else:
		quit(1 if total > 0 or blank > 0 else 0)
