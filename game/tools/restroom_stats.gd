extends SceneTree

## Restroom render stats: restroom triangle count, draw calls, frame times.
## Needs a window: --windowed --resolution 1280x720 --script res://tools/restroom_stats.gd
var _main: Node3D
var _frame := 0
var _cpu := 0.0
var _gpu := 0.0
var _dc := 0.0
var _n := 0
var _t0 := 0

func _init() -> void:
	_main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)

func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			var idx = a[Mesh.ARRAY_INDEX]
			t += (idx.size() if idx != null and idx.size() > 0 else a[Mesh.ARRAY_VERTEX].size()) / 3
	for c in n.get_children():
		t += _tris(c)
	return t

func _process(_d: float) -> bool:
	_frame += 1
	var m = _main
	if _frame == 2:
		m.restroom.set_door_open(false, true)
		var p = m.player
		p.global_position = m.START_POS
		p.set("_yaw", m.START_YAW); p.rotation.y = m.START_YAW
		m.apply_atmosphere_now()
		RenderingServer.viewport_set_measure_render_time(get_root().get_viewport_rid(), true)
	if _frame == 60:
		_t0 = Time.get_ticks_usec()
	if _frame > 60 and _frame <= 360:
		var vp := get_root().get_viewport_rid()
		_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		_dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_n += 1
	if _frame == 361:
		var tiles = m.restroom.get_node_or_null("Tiles")
		print("STATS restroom_tris=%d tiles_tris=%d draw_calls=%.1f frame_ms=%.3f render_cpu_ms=%.3f render_gpu_ms=%.3f" % [_tris(m.restroom), _tris(tiles) if tiles else -1, _dc / _n, (Time.get_ticks_usec() - _t0) / 1000.0 / _n, _cpu / _n, _gpu / _n])
		quit(0)
	return false