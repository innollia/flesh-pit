extends SceneTree

class EyeProbe:
	extends Node
	var target: Node3D
	var peak: float = -INF
	var low: float = INF
	func _process(_delta: float) -> void:
		peak = maxf(peak, target.global_position.y)
		low = minf(low, target.global_position.y)

var m: Node3D
var passed := 0
var failed := 0
var fixture_floor: StaticBody3D

func _init() -> void:
	Engine.max_fps = 60
	if not OS.get_user_data_dir().contains("flesh-pit-restoration-"):
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func aim(point: Vector3) -> void:
	var direction: Vector3 = (point - m.player.camera.global_position).normalized()
	m.player._yaw = atan2(-direction.x, -direction.z)
	m.player._pitch = asin(direction.y)
	m.player.rotation.y = m.player._yaw
	m.player.camera_pivot.rotation.x = m.player._pitch

func press(action: String, count: int = 3) -> void:
	Input.action_press(action)
	await frames(count)
	Input.action_release(action)
	await frames(2)

func game_at(position: Vector3) -> void:
	if is_instance_valid(fixture_floor):
		fixture_floor.queue_free()
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://restoration-t9-test.bin"
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.player.global_position = position

func support_feet() -> void:
	fixture_floor = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 0.2, 2.0)
	shape.shape = box
	fixture_floor.add_child(shape)
	root.add_child(fixture_floor)
	fixture_floor.global_position = m.player.get_feet_position() - Vector3.UP * 0.1

func mouse(held: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = held
	Input.parse_input_event(event)

func test_f_and_fixture_inputs() -> void:
	await game_at(Vector3(-1.25, 0.9, 0.72))
	aim(m.toilet_point())
	await frames(3)
	await press("fp_interact")
	check(m.is_seated(), "실제 그릇 조준 F로 앉는다")
	await press("ui_cancel")
	check(not m.is_seated() and m.player.is_physics_processing(), "앉은 뒤 Esc는 실제 몸을 복구한다")
	# 다음 독립 fixture는 실제 열린 문을 이미 가진 초기 자세이다.
	await game_at(Vector3(-0.9, 0.9, 0.4))
	m.restroom.set_door_open(true, true)
	var width: float = 2.0 * FPRestroom.DOOR_HALF_W - 0.01
	aim(m.restroom.door_pivot.to_global(Vector3(width * 0.5, FPRestroom.DOOR_H * 0.5, 0)))
	await frames(3)
	check(m.interact_target() == "door", "열린 문의 실제 중심이 조준된다")
	await press("fp_interact")
	check(not m.restroom.is_door_open(), "열린 문 조준 F는 닫기 입력을 받는다")
	await frames(45)
	aim(m.restroom.door_pivot.to_global(Vector3(width * 0.5, FPRestroom.DOOR_H * 0.5, 0)))
	await frames(3)
	await press("fp_interact")
	check(m.restroom.is_door_open(), "같은 정상 루프에서 문을 다시 연다")
	await game_at(Vector3(-1.25, 0.9, 0.72))
	var director: FDKAudioDirector = m.get_node("AudioHookup").director
	aim(m.tank_lid.lid.global_position)
	await frames(3)
	check(m.interact_target() == "tank_lid", "느슨한 탱크 뚜껑이 실제 조준 표적이다")
	await press("fp_interact")
	check(m.tank_lid.held and not m.tank_lid.on_tank, "F 입력으로 뚜껑을 집는다")
	aim(m.player.camera.global_position + Vector3.RIGHT)
	await frames(3)
	await press("fp_interact")
	check(not m.tank_lid.held and not m.tank_lid.on_tank, "다른 방향 F 입력으로 뚜껑을 바닥에 놓는다")
	check(director.played_log.has("tank_lid"), "실제 뚜껑 소유 상태 변경이 소리에 도달한다")
	m.toilet.bowl_flesh = 25.0
	aim(m.lever_point())
	await frames(3)
	check(m.interact_target() == "lever", "실제 레버가 조준된다")
	await press("fp_pick")
	check(is_zero_approx(m.toilet.bowl_flesh) and m.progression.teeth > 0, "정상 레버 입력은 실제 내용을 이빨로 정산한다")
	check(m.vent.spoken.has(FPVent.FIRST_CHAIN[0]), "첫 물내림은 기존 NPC 첫 대사를 발생시킨다")
	check(m.subtitles.current_text == FPSubtitles.line_text(FPVent.FIRST_CHAIN[0]), "첫 NPC 대사가 기존 자막에 도달한다")
	check(director.played_log.has("toilet_flush"), "실제 레버 신호가 물내림 소리를 발생시킨다")
	aim(m.restroom.tank_art.to_global(Vector3(0, 0.3, 0)))
	await frames(3)
	check(m.interact_target() == "tank_teeth", "열린 탱크 이빨이 좁은 실제 조준 표적이다")
	await press("fp_interact")
	check(m.progression.teeth_in_hand > 0, "정상 F 입력으로 열린 탱크에서 이빨을 푼다")
	await game_at(Vector3(-1.8, 0.9, -1.0))
	Input.action_press("fdk_crouch")
	await frames(3)
	aim(m.canary_hole_point())
	await frames(3)
	check(m.player._is_crouching and m.interact_target() == "canary", "Ctrl 실제 몸으로 낮은 카나리아 구멍에 도달한다")
	check(FPInteractions.check_aim(m, m.canary_hole_point(), "canary"), "카나리아는 실제 열린 물리 ray로 도달한다")
	var eye_before: float = m.player.camera_pivot.global_position.y
	var feet_before: float = m.player.get_feet_position().y
	var probe := EyeProbe.new()
	probe.target = m.player.camera_pivot
	probe.process_priority = 1000
	m.add_child(probe)
	var camera_probe := EyeProbe.new()
	camera_probe.target = m.player.camera
	camera_probe.process_priority = 1000
	m.add_child(camera_probe)
	await press("fp_interact")
	check(m.is_pulling_canary(), "정상 F 입력이 기존 카나리아 꺼내기를 시작한다")
	await frames(105)
	check(m.has_canary, "기존 꺼내기 시간 뒤 실제 새를 소지한다")
	check(probe.peak <= eye_before + 0.001, "실제 웅크린 카나리아 꺼내기 중 머리가 위로 튀지 않는다")
	check(probe.low < eye_before - 0.3, "기존 낮은 꺼내기 모션은 실제 발 기준으로 눈을 낮춘다")
	check(camera_probe.low > m.player.get_feet_position().y + m.player.camera.near and m.player.get_feet_position().y >= feet_before - 0.005, "실제 꺼내기 동안 눈과 몸이 바닥을 관통하지 않는다")
	check(not m.is_pulling_canary() and absf(m.player.camera_pivot.global_position.y - eye_before) < 0.002, "꺼내기 끝에는 실제 웅크린 눈높이를 복구한다")
	check(m.art_hookup.belt.get_node("Canary").visible, "꺼낸 카나리아는 기존 팬티 소지 표현에 도달한다")
	probe.queue_free()
	camera_probe.queue_free()
	Input.action_release("fdk_crouch")

func test_actual_eat_and_danger() -> void:
	await game_at(Vector3(8, 4.3, 8))
	var center := Vector3(8, 5, 8)
	m.terrain.fill_box_uniform(AABB(center - Vector3.ONE * 3.0, Vector3.ONE * 6.0), 1.0, 0)
	m.terrain.remesh_all()
	support_feet()
	aim(m.player.camera.global_position + Vector3.FORWARD)
	await frames(4)
	var tears: Array[Vector3] = []
	m.chewer.cell_torn.connect(func(p): tears.append(p))
	var biome: String = FPProgression.biome_for_shell(m.shell_at(center))
	var multiplier: float = FPProgression.SHELL_MULTIPLIER[biome]
	# 실제 첫 섭취가 임계값을 넘게 만드는 이미 얻은 소수 잔량 fixture.
	m.progression.hair_carry[biome] = 50.0 - m.stomach_config.flesh_per_cell * multiplier
	var before: int = m.progression.hairs(biome)
	mouse(true)
	for i in range(150):
		await process_frame
		if not tears.is_empty(): break
	mouse(false)
	await frames(2)
	check(tears.size() == 1, "정상 LMB 입력과 Main 루프가 실제 살을 뜯는다")
	if not tears.is_empty():
		check(m.terrain.density_at(tears[0]) < m.terrain_config.iso_level, "실제 제거한 밀도가 낮아진다")
	check(is_equal_approx(m.stomach.fill, m.stomach_config.flesh_per_cell), "실제 뜯기와 위장 살 단위가 같다")
	check(m.progression.hairs(biome) == before + 1, "실제 뜯기 순간 실제 단위 털이 물내림 없이 자란다")
	check(m.art_hookup.arm_hair.call("hair_total") == m.progression.total_hairs(), "정상 팔 표시 소비자가 실제 먹기 털을 즉시 표시한다")
	check(m.progression.pending_hair_total() == 0, "실제 먹기 뒤 정산 대기 털을 새로 만들지 않는다")
	RenderingServer.force_draw(false)
	print("T9 danger crush=", m.crush_progress(), " fov=", m.player.camera.fov, " offsets=", Vector2(m.player.camera.h_offset, m.player.camera.v_offset))
	check(m.crush_progress() > 0.0 and m.player.camera.fov < 75.0, "실제 고립 공간 위험이 정상 카메라 시야를 좁힌다")
	check(absf(m.player.camera.h_offset) + absf(m.player.camera.v_offset) > 0.0, "실제 위험의 기존 흔들림이 정상 루프에 남는다")
	check(RenderingServer.frame_pre_draw.is_connected(m._guard_terrain_eye), "production 렌더 직전 보정 연결이 유지된다")

func test_actual_nerve() -> void:
	await game_at(Vector3(8, 4.3, 8))
	var center: Vector3 = m.player.global_position
	m.terrain.fill_box_uniform(AABB(center - Vector3(3, 3, 3), Vector3(6, 6, 14)), 1.0, 0)
	m.terrain.fill_box_uniform(AABB(center - Vector3(0.5, 1.0, 2.0), Vector3(1.0, 2.7, 12.0)), 0.0, 0)
	m.terrain.remesh_all()
	support_feet()
	(fixture_floor.get_child(0).shape as BoxShape3D).size.z = 14.0
	fixture_floor.position.z += 4.0
	await frames(4)
	var created: FDKNerveStalk
	for index in range(18):
		aim(m.player.camera.global_position + Vector3.RIGHT)
		await frames(2)
		var count: int = m.excavated_cells
		mouse(true)
		for i in range(100):
			await process_frame
			if m.excavated_cells > count: break
		mouse(false)
		await frames(3)
		if m.excavated_cells < 8:
			check(m.nerves.is_empty(), "실제 여덟 번 굴착 전에는 신경이 생성되지 않는다")
		for n in m.nerves:
			if is_instance_valid(n) and n.is_inside_tree() and n.is_anchored():
				created = n
		if is_instance_valid(created): break
		# 좁은 실제 통로를 정상 옆걸음으로 이동해 아직 안 파낸 벽을 겨눈다.
		var previous_z: float = m.player.global_position.z
		Input.action_press("fdk_move_right")
		for i in range(60):
			await physics_frame
			if m.player.global_position.z >= previous_z + 0.5: break
		Input.action_release("fdk_move_right")
		await frames(2)
	print("T9 actual nerve excavated=", m.excavated_cells, " live=", m.nerves.size())
	check(m.excavated_cells >= 8 and is_instance_valid(created), "실제 반복 LMB 굴착 뒤 현재 살점에 붙은 신경이 생성된다")
	if is_instance_valid(created):
		var root_position: Vector3 = created.global_position
		var initial_count: int = m.excavated_cells
		aim(root_position)
		await frames(2)
		mouse(true)
		for i in range(300):
			await process_frame
			if not is_instance_valid(created) or not created.visible: break
		mouse(false)
		await frames(3)
		check(m.excavated_cells > initial_count, "신경 기반 방향의 정상 입력으로 실제 살을 더 제거한다")
		check(not is_instance_valid(created) or not created.visible, "실제 기반 굴착 뒤 기존 신경을 공중에 남기지 않는다")
	var floating := false
	for n in m.nerves:
		if is_instance_valid(n) and n.visible and not n.is_anchored(): floating = true
	check(not floating, "정상 루프의 현재 모든 보이는 신경은 실제 기반에 붙어 있다")

func test_normal_glare_and_save() -> void:
	await game_at(Vector3(0, 0.9, 5))
	m.restroom.set_door_open(true, true)
	m.terrain.fill_box_uniform(AABB(Vector3(-0.7, 0.0, 1.2), Vector3(1.4, 2.6, 4.8)), 0.0, 0)
	m.terrain.remesh_all()
	support_feet()
	(fixture_floor.get_child(0).shape as BoxShape3D).size = Vector3(1.4, 0.2, 6.0)
	fixture_floor.global_position = Vector3(0, -0.1, 3.0)
	await frames(3)
	check(m._is_dark_atmosphere(m.player.global_position), "현재 실제 동굴 위치는 밝은 문턱과 구분된다")
	var dwell: float = m.glare_controller.cave_time
	m.apply_atmosphere_now()
	check(is_equal_approx(m.glare_controller.cave_time, dwell), "즉시 시각 적용은 어둠 체류 시간을 가산하지 않는다")
	await create_timer(20.2).timeout
	check(m.glare_controller.glare_ready and m.glare_controller.cave_time >= 20.0, "정상 Main 20초 연속 실제 어둠 체류로만 눈부심을 무장한다")
	check(is_zero_approx(m._flash), "어두운 동굴 안에서 눈부심이 발동하지 않는다")
	aim(m.player.camera.global_position + Vector3.FORWARD)
	Input.action_press("fdk_move_forward")
	for i in range(300):
		await physics_frame
		if m.restroom.contains(m.player.global_position): break
	Input.action_release("fdk_move_forward")
	await frames(2)
	check(m.restroom.contains(m.player.global_position), "정상 이동으로 실제 동굴 통로에서 밝은 화장실에 돌아온다")
	check(m.glare_controller.total_flashes == 1 and m._flash > 0.0, "정상 밝은 귀환은 어둠 체류 뒤 눈부심을 한 번 발생시킨다")
	m.show_title()
	check(is_zero_approx(m._flash) and is_equal_approx(m.environment.tonemap_exposure, 1.0), "실제 눈부심 중 타이틀 진입은 멈춘 배경의 노출까지 즉시 초기화한다")
	m._leave_title()
	await press("fdk_move_back", 15)
	await press("fdk_move_forward", 15)
	check(m.glare_controller.total_flashes == 1, "실제 문턱 왕복은 추가 눈부심을 발생시키지 않는다")
	# 공간 귀환은 사용자 저장을 건드리지 않는 실제 저장 복원 경로로 확인한다.
	check(m.save_to_disk(), "현재 격리 슬롯 저장이 성공한다")
	check(m.load_from_disk(), "현재 격리 슬롯 복원이 성공한다")
	check(not m.glare_controller.glare_ready and is_zero_approx(m._flash), "실제 저장 복원은 어둠 무장과 플래시를 초기화한다")
	check(m.glare_controller.cave_time < 0.1, "저장 복원은 가짜 100초 체류를 만들지 않는다")
	m.show_title()
	check(not m.glare_controller.glare_ready and is_zero_approx(m._flash), "실제 타이틀 진입은 눈부심 상태를 초기화한다")
	paused = false

func run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://restoration-t9-test.bin"
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	# 초기 배치만 설정하고 정상 Main/플레이어 루프에서 입력을 처리한다.
	m.player.global_position = Vector3(-1.25, 0.9, 0.72)
	aim(m.toilet_point())
	await frames(4)
	check(m.is_processing() and m.player.is_physics_processing(), "정상 process와 physics가 실행된다")
	check(m.interact_target() == "toilet", "실제 가까운 그릇이 동일 조준 표적이다")
	m.stomach.add_flesh(25.0)
	Input.action_press("fp_vomit")
	await frames(4)
	check(m.is_settling(), "정상 V 입력으로 정산에 들어가고 held 입력으로 탈출하지 않는다")
	check(m.toilet.bowl_flesh > 0.0, "실제 구토 내용이 그릇에 남는다")
	var bowl: float = m.toilet.bowl_flesh
	var director: FDKAudioDirector = m.get_node("AudioHookup").director
	var flush_sounds: int = director.played_log.count("toilet_flush")
	Input.action_press("fdk_move_forward")
	await frames(3)
	check(not m.is_settling(), "새 이동 입력으로 자연스럽게 일어난다")
	check(is_equal_approx(m.toilet.bowl_flesh, bowl), "이동 탈출은 물을 내리지 않는다")
	check(m.player.is_physics_processing() and m.player.camera.current, "탈출 뒤 실제 물리와 카메라를 복구한다")
	check(director.played_log.count("toilet_flush") == flush_sounds, "정산에서 일어나기만 하면 물내림 소리를 재생하지 않는다")
	check(not m.vent.spoken.has(FPVent.FIRST_CHAIN[0]), "토하기와 일어서기만으로 NPC 첫 물내림 대사를 발생시키지 않는다")
	Input.action_release("fp_vomit")
	Input.action_release("fdk_move_forward")
	await frames(3)
	# 공유 섭취 소비자는 실제 운반 살 단위를 소비하고 동일 내용을 다시 지급하지 않는다.
	m.carried_flesh = 300.0
	m.carried_units = {0: 75}
	var before: int = m.progression.total_hairs()
	m.mutation_apply.gulp()
	check(m.progression.total_hairs() - before == 8, "운반 핵 300단위 섭취는 즉시 6+2가닥을 지급한다")
	m.mutation_apply.gulp()
	check(m.progression.total_hairs() - before == 8, "빈 운반 내용 재섭취는 털을 중복 지급하지 않는다")
	before = m.progression.total_hairs()
	m.tissue_tools._blend_amount = 300.0
	m.tissue_tools._blend_units = {0: 75}
	m.tissue_tools.finish_drink()
	check(m.progression.total_hairs() - before == 4, "믹서 300단위는 실제 마신 60퍼센트에 해당하는 3+1가닥만 지급한다")
	check(m.nerves.is_empty(), "초기 문 개방에는 신경이 생성되지 않는다")
	await test_f_and_fixture_inputs()
	await test_actual_eat_and_danger()
	await test_actual_nerve()
	await test_normal_glare_and_save()
	m.queue_free()
	await process_frame
	print("T9: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
