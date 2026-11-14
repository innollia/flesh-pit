# 소비자 계약

## Main 저장 호출

save_to_disk()는 현재 단일 슬롯에 저장하며 성공 여부 bool을 반환한다. 기록·이름 변경 실패는 false다. load_from_disk()는 경로가 없거나 열 수 없거나 읽은 값이 Dictionary가 아니면 false이며, 성공하면 상태와 실제 지형 표시·충돌을 복원한다. 정상 플레이 경로 대신 별도 save_path를 지정해 소비자 검사를 실행한다.

Main의 저장 version은5이고 진행의 내부 version은3이다. 지형 payload는 chunks이며 각 청크의 좌표·밀도·조직·sealed·boost를 복원한다. 단일 슬롯을 다른 저장 형식으로 대체하는 변경은 기존 파일 소비자의 호환성을 함께 검증해야 한다. 설정 version1 JSON과 키 배치 JSON은 이 슬롯 payload가 아니다.

진행 저장과 죽음 드롭은 `migrated_v5_hairs` 표식으로 구형 털 이전의 중복 적용을 막는다. 표식 없는 구형 `pending_hairs` 값은 이미 껍질 배율을 적용한 가중 살 단위이므로 배율을 다시 곱하지 않고, 바이옴 50단위·공통 150단위 기준과 기존 `hair_carry`로 한 번 이전한다. 새 저장은 표식을 기록하며, 구형 죽음 드롭도 첫 복구 때 이전한 뒤 표식과 빈 `pending_hairs`로 재복구 중복을 막는다. 이미 버려져 저장되지 않은 위장 살은 복원할 수 없고, 그 양을 추측해 털을 다시 만들지 않는다.

실제 섭취 이벤트는 섭취된 살 단위만 털 계산에 전달한다. 들고 있는 살은 아직 섭취량이 아니며, 믹서기는 마시는 시점에 담긴 양의 60%만 섭취로 반영한다. `FDKStomachConfig.flesh_per_cell`의 기본값은 한 셀당 4 살 단위이고 소비자는 설정된 값을 받는다. 대형 톱 한 번은 최대 여섯 셀을 먹는다. 분수 잔여량은 풀별 `hair_carry`에 보존한다.

변기 레버 정산의 `FPProgression.settle()` 결과 모양은 `{teeth, hairs, by_pool}`이며, 현재 `hairs`와 모든 `by_pool` 값은 0이다. Main의 공개 `flushed(teeth_gain, hair_gain)` 신호 모양은 유지되고 레버를 당기면 두 번째 값은 0이다. 털은 실제 먹는 순간 이미 지급되며, 변기 정산은 이빨만 지급한다.

## 플레이어 이동 경계

`FDKFirstPersonController.movement_filter`는 선택적인 Callable이다. 초 단위 물리 프레임에서 요청된 세계 이동 벡터를 받아 허용된 이동 벡터를 반환하며, 컨트롤러는 이를 속도로 환산한 뒤 기존 `move_and_slide()`를 실행한다. 콜백이 없으면 기존 독립 컨트롤러의 물리 동작을 유지한다. Main이 현재 실제 지형과 전체 캡슐의 경계를 연결하며 키트는 Main을 참조하지 않는다.

`FDKFirstPersonController.shape_fits`도 선택적인 Callable이다. 현재 캡슐이 지금 자리에 맞는지(실제 지형 면이 관통하지 않고, 중심이 고체 안이 아니고, 건축물과 겹치지 않는지) bool로 답한다. 없으면 물리 겹침 질의를 쓴다. 컨트롤러는 몸이 살에 걸리면 낮은 턱을 넘고(config.step_height), 0.9 m까지의 입구로 기어오르고(config.climb_reach), 고개를 숙이거나(duck, 키 최저 config.squeeze_min_height) 몸을 뒤틀어(twist, 반지름 ×config.squeeze_min_radius_scale) 실제 캡슐을 바꾼다. 모든 변경은 shape_fits와 movement_filter를 통과해야 남는다. squeeze()는 0~1, 걷기 속도는 lerp(1, config.squeeze_speed_min, squeeze())배다. set_natural_radius(r)은 몸 자체 반지름(변이)을 정한다. probe_space(dir)는 앞 바닥 높이·천장·폭을 실제 충돌로 잰 사전이며, 판정 근거가 아니라 자세를 고르는 단서다. Main은 FPBodyClearance.fits()를 연결한다.

`move_locked`가 참이면 이동키 입력을 무시한다(시선·중력·자세는 그대로). 게임이 그 키를 따로 읽는다. `last_physics_us`, `last_posture_us`는 측정용 비용이다.

`FDKTerrainField.regen_stagger`(기본1)를 N으로 두면 청크마다 N번 호출에 한 번, 기다린 시간만큼 재생한다. `FDKChunk.REGEN_REMESH_DRIFT`(0.02)는 재생만으로 청크를 다시 메시화하는 누적 변화량이며, 표면을 넘거나 다 나으면 즉시 표시한다. 연속 변경의 최악을 검사할 때는 0으로 둔다. `step_contraction(delta, near, radius=8)`은 조이는 모서리 상자 기준이다. `last_process_us`, `remesh_count`, `patch_refresh_count`는 측정용이다.

허용된 이동은 출발 캡슐에서 반환 벡터까지의 실제 직선 전체 경로와 끝점이 안전해야 한다. 여러 축으로 꺾어 검사한 경로를 합벡터의 안전성으로 대신하지 않는다. 현재 살점이 몸을 침범한 경우의 짧은 탈출은 별도의 전체 캡슐 경로 검사와 기존 물리 충돌을 통해 수행한다.

## 조준 결과

Main._look_hit()는 맞지 않으면 빈 Dictionary, 맞으면 collider와 세계 position을 포함한 히트 사전을 반환한다. 실제 지형 collider는 fdk_terrain_chunk 메타를 가진다. 소비자는 원격 셀 좌표를 새로운 히트처럼 만들어 넣지 않는다. 도구는 같은 거리·차폐를 만족하는 히트에서 동작하며 실제 내부·임시 표면도 그 계약을 따른다.

## 먹기 신호

FDKChewer.try_start(world_pos)는 세계 위치를 받아 같은 셀을 이어 잡거나 새 셀 진행을 시작한다. 유효하지 않은 살에서는 stop으로 이어진다. process_chew(delta)는 초 단위 시간을 진행하고 stop()은 진행을 해제한다. terrain과 config가 없는 경우 진행하지 않는다.

grab_started(target_cell: Vector3i)는 셀을 새로 잡을 때, chew_progress(ratio: float,target_cell: Vector3i)는 진행0~1을, cell_torn(world_pos: Vector3)는 실제 제거 완료 세계 위치를 전달한다. released()는 잡던 상태에서 놓는 전환에 한 번 발생한다. 손과 소리는 신호를 구독하며 Chewer가 손 mesh 구조를 읽지 않는다.

FDKHandsRig.set_reach_point(world_pos)는 실제 접촉이 유지되는 동안 게임이 매 프레임 주는 잡은 지점이다. 앞장선 손은 그 방향으로 손끝이 닿게 뻗고 거기서 뜯으며, clear_reach_point() 뒤에는 원래의 고정 위치를 쓴다. 손 리그는 이 점만 읽고 지형을 읽거나 뜯기를 정하지 않는다. aside(허리 쪽으로 비킨 손)는 쉬는 손에만 적용된다.

잡기가 거절되면 Chewer는 시작하지 않으므로 신호가 없다. 게임이 FDKHandsRig.on_grab_refused()를 불러 손이 오므렸다 미끄러져 돌아오는 SLIP 상태(0.5 s)를 보인다. 게임 쪽 거절 신호는 Main.grab_refused(tissue: int, world_pos: Vector3)이고 소리 연결이 구독한다. 첫 레버 정산 전 밖의 헛구역질은 Main.dry_heaved()로 알리고 소리 연결이 구독한다.

위장이 가득 차서(FDKStomach.is_full()) 시작하지 못한 잡기는 FDKChewer.refused_full(world_pos: Vector3)로 알린다. try_start가 실제로 먹을 수 있는 살을 받았는데 위장 때문에만 거절한 경우이고, stop() 뒤에, 거절된 호출마다(입력을 누르고 있으면 매 프레임) 나간다. world_pos는 try_start가 받은 세계 위치다. 밀도와 위장은 변하지 않는다. 주기 제한은 게임이 한다: Main.stomach_refused(world_pos: Vector3)는 같은 거절을 누르고 있는 동안 0.9초(Main.FULL_REFUSE_EVERY)에 한 번, 끊겼다 다시 누르면 즉시 내고, world_pos는 벽의 실제 접점이다. 소리 연결은 Main.stomach_refused를 구독하고 grab_refuse(날붙이 필요)·gag_dry(여기선 못 토함)와 다른 소리를 붙인다. 들기 모드에서 손이 가득 찬 거절은 Main.carry_refused(world_pos: Vector3)이며 주기와 인자 뜻이 같다(Chewer 신호는 없다). 두 거절 모두 손 자세는 바꾸지 않고 지형 눌림(set_press 0.35, 0.3초)만 보인다. 위장 거절은 FPStomachView.heave()와 fp_danger_show.heave()(머리 숙임 0.35초)를 함께 부른다.

FDKHandsRig에 더한 진입점 셋은 부르지 않으면 0이고, 0일 때 기존 IDLE·GRAB·TEAR·SLIP·RELEASE 자세 값은 그대로다. on_reach_short(world_pos)는 조준한 살이 팔보다 멀 때 게임이 매 프레임 부른다. 쉬는 손(IDLE)만 그 점을 향해 REACH_MAX까지 뻗고 손가락은 쉬는 자세 그대로 편 채 0.004 m로 떤다. 마지막 호출 0.12초 뒤 스스로 돌아온다. 쥐지 않으므로 GRAB·SLIP과 환풍구 넛지의 빈손 쥠과 구분된다. set_crush(0..1)은 쉬는 손을 가운데로 0.06 m, 눈 쪽으로 0.04 m 모으고 일하는 손에는 적용되지 않는다. set_strain(0..1)은 GRAB의 당김 떨림 진폭을 최대 2.5배, 주파수를 0.6배까지 바꾼다. 손 리그는 이 값들만 받고 위장·압사·지형을 읽지 않는다.

FPStomachView.swallow_kick(units, delay)는 삼킨 살 단위만큼 위장 덩어리를 한 번 올렸다 내린다(4단위가 최대 한 번, 0.35초). Main.show_swallow(units)가 뜯김 0.3초 뒤(FPStomachView.SWALLOW_DELAY, 삼킴 소리와 같은 지연)로 부르며, 손에 드는 살에는 부르지 않는다. 표시일 뿐 위장 값을 바꾸지 않는다.

한 손 도구(믹서기)는 FDKHandsRig.hold_left로 왼손에 쥔다. 손은 빈 채로 화면 아래로 내려갔다가 도구를 쥐고 올라오며, 내려놓을 때는 반대로 간다. 게임은 도구를 왼손 Wrist 자식으로 달고 left_grip_shown()이 참일 때만 보인다. 도구를 카메라 공간에 따로 두면 손보다 먼저 나타나고 걷기 흔들림을 따르지 않는다(2026-11-03).

두 손 도구(큰 톱)는 FDKHandsRig.hold_both로 두 손에 쥔다. 두 손이 함께 화면 아래로 내려갔다가 도구를 쥐고 올라온다. 게임은 도구를 오른손 Wrist 자식으로 달고 both_grip_shown()이 참일 때만 보인다. 두 손은 서로 거울 자세이고 흔들림·aside·hold_shift·누르기를 똑같이 받으므로, 게임이 hold_both_pos.x를 두 손잡이 간격에 맞추면 왼손도 왼쪽 손잡이를 계속 쥔다. 톱질은 hold_shift로 두 손을 함께 민다(2026-11-03).

## 지형 수정

FDKTerrainField.dig_at(world_pos: Vector3,amount: float)는 실제 셀과 이웃 공유 모서리 밀도를 제거하고 게시할 지형을 표시한다. 반환값은 없으며 부작용 결과는 밀도·메시·충돌에서 확인한다. serialize()/deserialize(Dictionary)는 청크 상태를 주고받는다. 소비자는 복원 뒤 실제 화면이 필요한 시점에 게시를 준비해야 하며 데이터 적용만으로 첫 화면 준비를 단정하지 않는다.

살점 면의 표시 계약. 지형 메시의 삼각형은 `FDKChunk._face_tissue`(패치는 `FDKTerrainField.face_tissue(centroid_world, outward)`)가 고른 조직의 표면에 들어간다. 무게중심에서 면 법선의 살 쪽으로 반 칸 들어간 칸의 조직이며 `Main._terrain_target`의 조준 규칙과 같다. 둘 중 하나를 바꾸면 다른 쪽과 `run_terrain_visual_tests.gd` A절을 같이 바꾼다.

새살은 정점 색 `COLOR.r = 1 - 진행`으로 전한다. 진행은 정점이 든 칸의 8개 모서리 가운데 `FDKChunk.regrow_progress`(이웃 청크 모서리는 `FDKTerrainField.corner_regrow_global`)의 최댓값이다. 색 배열이 없는 메시는 흰색이라 새살이 없다. 청크 경계의 겹친 정점은 같은 8개 모서리를 읽어 같은 값을 받는다. 재생이 붙들린 구(몸, 방벽)는 `regenerate_all` 끝에 `FDKChunk.set_regrow_hold_all(holds)`로 셰이더의 `regrow_hold[8]`에 넘긴다.

수축 예고는 셰이더가 `FDKTissueRules.contract_preview`와 같은 식으로 점마다 계산한다. 시계와 범위는 `step_contraction`이 `FDKChunk.set_contract_clock(clock, near, cell_size, chunk_size)`로 넘기고, 조임이 돌지 않으면 시계는 음수다. 식을 바꾸면 GDScript 쪽과 셰이더 쪽을 같이 바꾼다(`run_terrain_visual_tests.gd` C절이 문자열과 실제 조임 목록으로 대조한다).

`FDKTerrainField.set_press(center, toward, amount, gain := 1.0)`의 gain은 잡은 칸 조직의 `pull_gain`이다. 값 하나가 모든 조직 재질에 똑같이 들어가므로 조직 경계의 정점이 갈라지지 않는다. `FDKPullShape.offset(..., gain := 1.0)`이 같은 값을 받는다. `FPTearFeel.on_chew(ratio, contact, toward, tissue := COMPRESSIVE)`와 `on_tear(world_pos, eye, tissue := COMPRESSIVE)`는 조직 번호를 받아 `FDKTissueRules.look(tissue)`의 값을 쓴다. 인자를 주지 않으면 압축 살이다.

## 소리 디렉터

FDKAudioDirector는 신호를 구독하고 소비자가 준 값을 읽기만 한다. 없는 소리 id는 조용히 건너뛴다.
- connect_chewer(chewer)는 grab_started·chew_progress·cell_torn·released를 구독하고 chewer를 보관한다. chew_progress(ratio)는 당김 층 pull_stretch의 음량(`pull_db`, ratio 제곱)과 높이(`pull_pitch`)를 움직이고, cell_torn과 released는 그 층을 바로 끈다. cell_torn의 뜯김은 `chewer.last_units ÷ chewer.config.flesh_per_cell`(0~1)만큼 크고 낮다(`thin_tear_db`, `thin_tear_pitch`). `_on_cell_torn(world_pos, whole := 1.0)`을 직접 부르는 소비자(M22)는 온전한 한 칸으로 난다. 삼킴은 `swallow_delay`(0.3초) 뒤다.
- 뜯김 id는 `TISSUE_TEAR`가 조직 id(FDKTissueRules)로 고른다: 0 tear_flesh, 1 tear_nerve, 2 tear_fat, 3 tear_membrane, 4 tear_muscle, 6 tear_cartilage, 7 tear_cloth, 8 tear_hair. 표에 없거나 manifest에 없는 id는 tear_flesh다.
- 재생 삐걱임은 `life_enabled`가 true인 동안만 난다(기본 false, 배경 이름과 무관). `creak_source`(Callable → Vector3 또는 null)가 실제로 자라는 자리를 주고, 소비자가 `life_urgency`(0~1)를 넣으면 간격이 `life_interval` → `life_interval_urgent`, 음량이 −6 → 0 dB로 간다. 이미 뽑아 둔 긴 대기는 지금 urgency의 가장 긴 간격으로 잘린다.
- 발소리는 footstep_bob의 골짜기마다, `listener`가 직전 골짜기 뒤로 수평 `step_min_travel`(0.12 m) 넘게 움직였을 때만 난다. listener가 없으면 골짜기마다 난다.

게임 쪽 연결(fp_audio_hookup): `FDKTerrainField.contraction_warning(world_pos)` → contract_warn(그 자리. `world_pos`는 `step_contraction`에 준 점에서 가장 가까운 조이는 모서리이고, 그 모서리의 조임 `CONTRACT_WARN`초 전에 청크마다 한 번 난다), `Main.stomach_refused(world_pos)` → full_refuse(위치 없음), 끼임 이벤트 `squeeze` → squeeze_breath, `Main.crush_progress()` → 상시 층 crush_breath(SFX 버스, 음량 = 진행, 재생 속도 0.9~1.25). 전부 읽기와 구독이다.

외부 HTTP API나 로그인 프로토콜은 제공하지 않는다. 키트의 Godot 호출과 신호, 로컬 파일 형식이 소비자 경계다.

## 음성과 자막

`AudioHookup/Voice`(audio/fp_vent_voice.gd)는 `voice_started(line_id: String, seconds: float)`와 `voice_cut(line_id: String)`을 내고, Main이 `FPSubtitles.follow_voice`·`FPSubtitles.voice_cut`에 연결한다. 음성이 나오는 줄의 자막은 대기열을 건너뛰어 바로 나오고 `max(seconds + VOICE_TAIL, VOICE_MIN_TIME)` 동안 남는다. 끊긴 음성의 자막은 내려가고 대기 중인 줄이 이어진다. 음성 없는 줄끼리는 기존 대기열 그대로다. 연결 순서상 자막의 `line_spoken` 구독이 음성보다 먼저여야 하며, 소리 연결은 지연 호출되는 `_wire`에서 구독한다.
