# STATUS

Single entry point for progress and validation. Updated after every step.

## 범위 (2026-09-29 형님 지시)

프론트엔드(손 메시·손가락·손 애니메이션, 화장실·변기 생김새, 위 게이지 시각
표현, 셰이딩·색 튜닝, 캡처 판정)는 다른 모델이 맡는다. 이 세션은 백엔드만
담당: 지형 밀도·메싱·충돌, 파기/재생, 위 상태, 먹기 판정 로직, 1인칭 이동
로직, 저장, 성능 측정, 자체 테스트, export_kit.py, 공유 zip 시험.

## Step 0-2: skeleton + terrain + eat + player backend + perf fix

- Created `game/` git repo (no push, local only).
- project.godot: renderer forced to gl_compatibility (Compatibility).
- addons/flesh_dig_kit/: plugin.cfg + plugin.gd stub (no editor UI yet).
- terrain/: FDKTerrainConfig, FDKChunk (density grid + naive surface-nets
  meshing with unshared per-face vertices for flat low-poly shading,
  vertex color by tissue id), FDKTerrainField (chunk management,
  world<->cell conversion, dig_at/regenerate_all, depth_at() for concentric
  shells, carve_sphere/fill_box_uniform, serialize/deserialize).
- eat/: FDKStomachConfig, FDKStomach (fill/overfill/vomit + fill_ratio(),
  signals), FDKChewer (hold-to-chew timing scaled by overfill; signal
  contract below).
- player/: FDKPlayerConfig, FDKInputActions (registers fdk_move_*,
  fdk_look_* keyboard-only look, fdk_crouch, fdk_eat, fdk_jump in code),
  FDKFirstPersonController (mouse+keyboard look, keyboard-only look
  fallback, crouch, climb, footstep bob signal, get_look_ray()).
- main/main.gd: white restroom (carved sphere) + flesh wall beyond the
  door (design-core.md section 8), wiring terrain+stomach+chewer+player,
  serialize()/deserialize() for save/load.
- tests/run_tests.gd: 27 self-tests (terrain dig/regen/depth/serialize,
  stomach fill/overfill/vomit/fill_ratio/serialize, chewer timing + full
  signal contract). tests/run_headless.gd: 300-frame main.tscn run, no
  crash. tests/measure_remesh.gd: single-chunk remesh benchmark.
- tools/export_kit.py: zips addons/flesh_dig_kit into dist/, versioned
  from plugin.cfg.
- Perf fix: naive remesh() called the bounds-checked get_density_at_corner
  up to 48x per solid cell and measured ~18ms/remesh at chunk_size=16 (over
  the 8ms budget). Rewrote it to precompute a padded corner-solid bit array
  once per remesh and index it directly (no method calls, no Callables in
  the hot loop) -> 5.9ms average. See fdk_chunk.gd's remesh() docstring.

## 검증 결과 (전부 종료 코드 0, Godot 4.7.2 console build)

- import (--editor --import): exit 0, no SCRIPT ERROR / stderr output.
- self-tests (tests/run_tests.gd): 27 passed, 0 failed.
- headless 300-frame run (tests/run_headless.gd, main.tscn): ran 300
  frames without crashing, clean stderr.
- remesh benchmark (tests/measure_remesh.gd): chunk_size=16, cell_size=0.5
  -> average 5.9ms/remesh (budget 8ms, PASS).
- export_kit.py: wrote dist/flesh_dig_kit-0.1.0.zip (30 files). Verified
  by extracting into a scratch empty project (minimal project.godot,
  main_scene = addons/flesh_dig_kit/demo/fdk_demo.tscn): import exits 0
  with no errors, and a 200-frame headless run of the demo scene completes
  without crashing. Confirms the kit is genuinely self-contained.
- save/load integration test (tests/run_save_load.gd): dig + partial
  stomach fill -> serialize() -> mutate further -> deserialize() ->
  confirms stomach.fill and terrain density are restored to the saved
  snapshot, not the further-mutated state. 3/3 passed.

## 프론트엔드 인계 (Frontend handoff)

### 이미 진행되다가 범위 밖으로 보류된 것

`addons/flesh_dig_kit/player/fdk_hands_rig.gd`에 Skeleton3D 기반 손 리그
(손목-손바닥-손가락덩어리 3관절 + 엄지 3관절, 관절 각도 제한 상수 포함)와
`addons/flesh_dig_kit/demo/fdk_demo.gd` / `main/scripts/main.gd`의 연결
코드를 작성 중이었다. **범위 변경 지시로 이 상태에서 커밋해 두고 멈췄다.**
이 파일들은 참고용 스타팅 포인트일 뿐, 프론트엔드 담당 모델이 검증/완성
책임을 진다 (백엔드 셀프테스트는 이 파일들을 테스트하지 않는다).

### 노출된 백엔드 API / 시그널 계약

**FDKChewer** (`addons/flesh_dig_kit/eat/fdk_chewer.gd`) -- 손 애니메이션이
구독해야 할 시그널:
- `grab_started(target_cell: Vector3i)` -- 새 셀을 잡음 (idle -> 쥐기 시작)
- `chew_progress(ratio: float, target_cell: Vector3i)` -- 씹는 동안 매 프레임
  0..1 진행률 (쥐는 강도/변형에 사용)
- `cell_torn(world_pos: Vector3)` -- 뜯김 완료 ("tear" 이벤트)
- `released()` -- 씹기 중단 (입력 해제 또는 타겟 상실), 쥔 손을 풀어야 함
- `is_chewing() -> bool` -- 현재 씹는 중인지 폴링용 (시그널 대신 필요하면)

**FDKStomach** (`addons/flesh_dig_kit/eat/fdk_stomach.gd`) -- 위 게이지
시각화가 읽어야 할 값:
- `fill_ratio() -> float` -- 0.0 비었음, 1.0 정상 용량 꽉 참, 1.0 초과 시
  넘겨먹은 만큼 계속 커짐 (게이지가 넘칠 때 위로 자라나게 쓰면 됨)
- `overfill_ratio() -> float` -- 0.0..1.0, overfill 구간 내 위치 (0=용량,
  1=overfill_capacity까지 다 채움)
- `fill_changed(fill, capacity, overfill_capacity)` 시그널 -- 매 변화마다
  발행
- `vomited(amount)` 시그널

**FDKFirstPersonController** (`addons/flesh_dig_kit/player/fdk_first_person_controller.gd`):
- `hands_rig` (`@onready var hands_rig: Node3D`) -- 현재는 `FDKHandsRig`
  타입이지만, 프론트엔드가 완전히 새로 만들 손 리그로 이 필드의 타입/내용을
  교체해도 된다. 카메라 하위(`CameraPivot/Camera3D/HandsRig`)에 배치된
  자리만 유지하면 백엔드 연결 코드(`main.gd`, `demo/fdk_demo.gd`)가 그대로
  동작한다.
- `footstep_bob(offset: Vector3)` 시그널 -- 걸음 카메라 흔들림, 필요시 손
  흔들림에도 재사용 가능.

### 임시 표시(placeholder) 위치

- 손: `fdk_hands_rig.gd`에 관절 애니메이션 로직까지 진행됐으나 **미완성/
  미검증** 상태로 남음. 프론트엔드가 형님 결정(아래)에 맞춰 새로 만들거나
  이어서 완성.
- 위 게이지 시각: 현재 어디에도 그려지지 않음 (design-core.md 2절이 요구
  하는 "화면 가장자리의 부풀어 오르는 살 덩어리" 등은 전혀 미구현). 프론트
  엔드가 `FDKStomach.fill_ratio()`/`overfill_ratio()`/`fill_changed` 신호를
  구독해 구현.
- 화장실/변기: `main.gd`가 만드는 것은 `carve_sphere`로 파낸 빈 구체 하나뿐,
  변기·문·타일 같은 형태는 전혀 없음. 프론트엔드가 로우폴리 메시로 채움.

### 형님 결정 (2026-09-29, 손 모양) -- 프론트엔드가 반영해야 함

- 직육면체 팔/손 불합격.
- 구성: 네 손가락(검지~새끼)은 **한 덩어리로 붙은 판 하나** + 별도로
  움직이는 **엄지 하나**.
- 손가락 덩어리와 엄지 모두 **관절 3개씩** (마디 3개, 각 관절이 따로 굽음).
- 손바닥·손목도 있어야 함. Skeleton3D 또는 노드 계층으로 관절 회전.
- 동작: 대기 시 살짝 굽힘 / 잡을 때 손가락 덩어리가 3관절 순서대로 말려
  쥐고 엄지가 맞물림 / 찢을 때 당기며 떨림 / 놓을 때 펴짐.
- 관절 각도 한계를 두고 테스트로 확인.
- 캡처에 손 클로즈업 1장 추가 (기존 4장 화면 + 1장 손 클로즈업 = 5장).

### 프론트엔드가 할 일 목록

1. 위 손 모양 결정을 반영한 손 리그/메시/애니메이션 새로 작성 (또는
   `fdk_hands_rig.gd`의 미완성 상태 이어서 완성 -- 관절 계층은 이미
   손가락덩어리 3관절 + 엄지 3관절 구조로 잡혀 있었음).
2. 관절 각도 한계 자체 테스트 작성 (프론트엔드 쪽 테스트 파일로, 백엔드
   run_tests.gd는 손 관련 테스트를 포함하지 않음).
3. 위 게이지 시각 표현 (fill_ratio/overfill_ratio/fill_changed 구독).
4. 화장실·변기 로우폴리 메시.
5. 셰이딩·색 튜닝 (조직 종류별 정점색은 백엔드가 이미 채우고 있음
   `FDKChunk.TISSUE_COLORS`, 필요하면 팔레트만 조정).
6. 캡처 5장 (기존 `tools/capture.gd`의 4스테이지 + 손 클로즈업 1장 추가,
   판정은 프론트엔드가 함).

## 프론트엔드 1차 (2026-09-29, 완료분)

키트(addons/flesh_dig_kit, 0.2.0):
- 지형 메셔를 표면 그물로 다시 짬: 칸마다 정점 1개(모서리 교차점 평균 +
  고정 흔들림), 교차 모서리마다 사각형 1개, 삼각형마다 면 법선 1개 = 각진
  로우폴리. 조직 색(살/신경/지방/막) + 깊이 톤. 이웃 청크 모서리를 읽고,
  파기는 모서리를 공유하는 모든 청크에 반영 -> 이음매 없음. 재메싱 6.6ms.
- 필드: 밀도/조직 생성기(sampler), generate_region, remesh_all, 프레임당
  재메싱 한도, tissue_at/density_at/is_edible_at, inedible_tissues(기본 막=3).
- 씹기: 먹을 수 없는 조직은 잡지 않음. 뜯기는 필드 dig_at으로.
- 손 FDKHandsRig: 손목(피치/요/롤) -> 손바닥(엄지두덩·새끼두덩) -> 네 손가락
  한 덩어리 3관절 + 엄지 3관절(맞섬 회전). 대기/잡기(1->2->3 순서)/씹기
  당김·떨림/찢기 튕김+뜯긴 살점/놓기 펴짐/들고 다니기(살 더미)/걸음 흔들림.
  관절 한계 LIMITS_DEG, 테스트로 확인. 뷰모델 셰이더로 벽에 안 파묻힘.
- FDKNerveStalk: 노란 신경이 벽에서 튀어나와 꿈틀, 뿌리가 먹히면 사라짐.

main:
- 흰 화장실(restroom.gd): 베벨 타일 벽·바닥·천장, 조명 패널, 변기(물·시트·
  물탱크, 뚜껑 열림), 세면대·거울, 경첩 문(안쪽으로 열림). 문 뒤 바로 살 벽.
- 세계: 화장실 상자 밖 전부 살(무한 생성). 화장실 둘레 0.9m는 막(먹기 불가,
  문 앞 기둥만 예외). 노이즈로 신경 조직, 껍질마다 지방 띠.
- 먹기 레이: 지형 청크에 맞았을 때만, 맞은 점 + 반 칸 안쪽을 겨눔.
- 위 표현(stomach_view.gd): 화면 아래에서 부풀어 오르는 살 덩어리(맥동),
  넘겨 먹으면 더 올라오고 뜯긴 살점이 화면 아래에 쌓임. 글자 없음.
- 토하기 버튼(vomit_button.gd): 넘겨 먹기 비율 0.35 이상에서 나타남(글자
  없는 그림 버튼, V키도). 변기 앞이면 정산, 밖이면 보상 없이 비우기만.
- 변기 정산(toilet_settlement.gd): 변기 클로즈업 카메라, 왼쪽 아래 변이·돈
  (짙은 회색 기존값 + 초록 +새 값이 올라감), 오른쪽 상점 자리 6칸(? / ---).
  구매 = 동전이 변기로 날아감 + 물탱크에 임시 물건, 정산 닫으면 뚜껑 열림.
- 들고 다니기(Q): 뜯은 살이 위 대신 손 위 더미로 감, 들고 있으면
  two_handed_tools_available() = false. Q를 다시 누르면 내려놓음.
- 최소 로직(자리값, 형님 확정 전): 보상 = 살 1당 변이 0.5, 돈 12. 상점
  품목·가격 없음(구매 시 돈 차감 없음). 조작: F 문/변기, V 토하기, Q 들기.

검증(모두 종료 코드 0): import, run_tests 44/44(백엔드 27 + 표면 8 + 손 9),
run_main_tests 19/19, run_save_load 3/3, 300프레임, 재메싱 6.6ms,
공유 zip 0.2.0 빈 프로젝트 import + 데모 200프레임. 테스트 RID 누수 없음.

캡처(tools/capture.gd, 창 모드): captures/1280x720, captures/1920x1080에
01_restroom, 02_flesh_wall, 03_dug_tunnel, 04_regrowing_tunnel, 05_hand_grab,
06_overfilled, 07_toilet_settlement, 08_carry_pile. 판정은 셸 수치
(tools/capture_stats.py 평균색·색 비율)와 문자 지도(tools/capture_ascii.py)로
했음 -- 이 작업자는 그림을 직접 볼 도구가 없어 사람 눈 확인이 필요.

## 프론트엔드 2차 (2026-09-29)

- 손: 손가락 덩어리 두께 약 1.5배, 마디(관절) 볼록·마디 사이 잘록, 손등·손바닥
  양쪽에 손가락 사이 홈 3줄. 대기 자세는 엄지를 덩어리 옆에 붙이고 손가락을
  조금 더 굽혀 집게처럼 보이지 않게.
- 화장실: 방 조명 0.75->0.42 + 그림자, 실내 환경광 0.22->0.12, 줄눈 어둡게,
  타일 약간 회색. 흰 비율(1920) 76%->65%. 시작 위치를 세면대 옆
  (START_POS/START_YAW)으로 바꿔 왼쪽 변기·오른쪽 문이 한 화면에. 문 앞
  신경은 0.19m로 짧게(닫힌 문을 뚫고 방 안에 보이던 문제).
- 지형 셰이더(키트 fdk_terrain.gdshader): 젖은 살(움직이는 광택, 스페큘러,
  가장자리 반사). 씹기 눌림: FDKTerrainField.set_press(중심, 플레이어 쪽,
  0..1) -> 처음엔 안으로 눌리고, 진행될수록 손 쪽으로 늘어나며 뜯기 직전
  떨림. main이 chew_progress로 매 프레임 호출.
- 깊이 안개: 밖에서 깊이 톤에 따라 0.10->0.20.
- 살 더미 들기: has_blender(임시 플래그)일 때만 Q 동작.
- 검증: import 0, run_tests 44/44, run_main_tests 21/21, save_load 3/3,
  300프레임 0, 재메싱 7.0ms.

## 프론트엔드 3차 (2026-09-29)

- 손: 손가락 덩어리 폭 0.041->0.047, 두께 0.0175->0.0215, 마디 볼록 낮게
  (1.28->1.07), 엄지 약 1.4배 굵게, 손바닥 넓고 두툼, 피부색 중립(0.88,0.72,0.62).
- 화장실 뚫림: ROOM_MARGIN 0.25->0.65(표면 그물 정점이 칸 안쪽으로 최대
  반 칸 이상 들어오기 때문). 테스트: 화장실 상자 +5cm 안 살 정점 0개
  (0.25로 되돌리면 34개로 실패함을 확인).
- 한국식 화장실 요소: 벽 샤워 수전+봉+샤워헤드+호스, 바닥 사각 배수구,
  휴지걸이+휴지, 천장 환풍구.
- 물탱크 집기: 뚜껑 열린 상태에서 물건을 9도 안으로 바라보고 우클릭(fp_pick)
  또는 F -> inventory로. 다 집으면 뚜껑 닫힘. 테스트 추가.
- 지방층: 첫 껍질 안쪽에서는 없음, 껍질 경계 0.9m 띠(다음 껍질 신호). 테스트 추가.
- 검증: import 0, run_tests 44/44, run_main_tests 24/24, save_load 3/3,
  300프레임 0, 재메싱 6.8ms.

## 프론트엔드 4차: PS1 톤앤매너 (2026-09-29)

형님 확정: 진지한 바디 호러, PS1(참고: Revenge Of The Colon, 생김새·분위기만).
평면 셰이딩 정점 색 로우폴리를 버리고 텍스처 입힌 PS1로 전환.

키트(0.3.0) 새 부품:
- FDKPs1Settings: 전역 on/off 하나 + 세부 수치(내부 해상도, 색 단계, 그레인,
  안개 거리, 정점 스냅 정밀도). FDKPs1Settings.active로 어디서나 접근.
- FDKPs1Material: 텍스처 하나 + 수치별로 재질을 캐시해 공유(같은 조합이면
  재사용). nearest 필터, 밉맵 없음, 정점을 클립공간 격자에 스냅(PS1 흔들림),
  씹기 눌림(press_center/amount)도 이 재질에서 처리.
- FDKPs1ScreenPost: 화면 전체 후처리(SCREEN_TEXTURE로 SubViewport 없이 처리).
  낮은 내부 해상도로 픽셀화 -> 4x4 베이어 순서 디더 + 색 단계 축소 -> 약한
  그레인. main이 자동으로 하나 붙임(설정 꺼지면 안 붙임).
- FDKLowPoly.planar_uv_mesh(): 정점 색만 있던 기존 메시(손·화장실 소품)에
  평면 UV를 입혀 텍스처를 씌울 수 있게 하는 후처리 함수.
- 지형 메싱: 조직별로 메시 표면을 따로 만들어(살/신경/지방/막 4장) 각자
  텍스처를 입힘. UV는 면이 놓인 평면(월드축 2개)으로 투영, 칸 경계 이음매 없음.

텍스처: tools/bake_ps1_textures.py로 64px/128px 생성. 저장소 자기 소유의
assets\3d\textures\(shells, restroom)를 읽어 다운샘플 + 베이어 디더한 것을
우선 쓰고, 없으면 numpy로 절차 생성(fbm 노이즈 살·지방·신경, 타일 그라우트,
피부). 원본은 읽기만 하고 손대지 않음(라이선스: 이 프로젝트 자체 생성물).

손: 새 손 재질을 tex_skin_128로 교체(손가락·엄지·손바닥 메시에 평면 UV).
씹기 눌림은 FDKTerrainField.set_press가 FDKChunk.set_press_all을 거쳐
조직별 재질 전체에 반영되도록 바꿈(재질이 조직당 하나로 바뀌었기 때문).

조명 보정: PS1 재질 도입 후 터널 안이 지나치게 어두워져 손전등 격 조명
(player_lamp) 에너지 1.1->2.4, 범위 5->6, 감쇠 1.4->0.9, 실외 환경광
0.3->0.42로 올림. 기획서가 원하는 "어둡고 가까운" 느낌은 유지하되 완전
암전은 아니게. 방향광 fog_enabled는 끔(짧은 안개는 이제 재질 셰이더 자체가
처리, 이중 안개로 과하게 어두웠음).

검증: import 0, run_tests 51/51(PS1 테스트 4개 추가: 저해상도 텍스처,
조직별 다른 텍스처, 설정 끄면 스냅 사실상 꺼짐, 씹기 눌림 전달), save_load
3/3, run_main_tests 24/24, 300프레임 0, 재메싱 5.8ms. 공유 zip 0.3.0을
빈 프로젝트에 풀어 데모 200프레임 통과.

## 프론트엔드 5차: 3차 질문 답 + 형님 추가 지적 (2026-09-29)

3차 질문 답(부모 결정):
1. 한국식 요소(샤워 수전·봉·헤드·호스, 바닥 배수구, 휴지걸이)가 한 화면에
   보이는 캡처 09_korean_fixtures 추가.
2. 문을 열면 곧바로 살이어야 함: 문틀 바로 바깥(문 기둥 안쪽 폭, 문 높이
   범위)만 빈 공간을 DOOR_GAP(0.04m)로 좁혀 살이 문 앞 몇 cm까지 옴. 방
   나머지 둘레는 ROOM_MARGIN(0.65m) 그대로(뚫림 방지 테스트 유지). 테스트
   추가: 문에서 DOOR_GAP+0.03m 지점 밀도 >= 0.5.
3. 집은 물건은 그대로 inventory 배열에만 쌓임(변경 없음).

추가 지적(스티어링): 손에 든 살 더미가 너무 컸음(화면 높이 184.7%,
카메라 초근접이라 원본 스케일 그대로면 화면을 뒤덮음). 기본(carried_flesh
30, ratio 0.75) 크기를 화면 높이 18.5%로, 상한(ratio 1.0)을 20.1%로 낮춤
(PILE_SCALE_BASE 0.42->0.38, PILE_SCALE_MAX 0.62->0.56, 손 unproject 실측).
넘겨 먹기 화면 아래 쌓임(stomach_view)도 같은 기준으로 확인했더니 68%로
더 심하게 벗어나 있어 조각 반지름과 퍼짐을 줄여 개별 조각 16.1%, 전체
묶음 19.8%로 맞춤. 테스트 추가(run_main_tests: 캐리 파일 20% 이하 단언).

검증: import 0(1회 -1073741819 접근위반, 재시도 2회 모두 0 -- 일시적),
run_tests 51/51, run_main_tests 26/26, save_load 3/3, 300프레임 0,
재메싱 6.4-7.0ms.

## 프론트엔드 5차-2 (2026-09-29, 부모가 b973737 캡처 확인 후)

- 손 안 보임 원인: PS1 재질 셰이더가 render_mode world_vertex_coords와
  MODELVIEW_MATRIX를 함께 써서 모델 변환이 두 번 적용됨 -> 카메라에 붙은 손이
  공중 조각으로 흩어지고 화장실 설비도 엉뚱한 곳에 그려짐(벽 가운데 검은
  조각). world_vertex_coords 제거. 손·살점·더미에 viewmodel_squash 0.18
  (벽에 파묻히지 않게) 추가.
- 첫 장면: 카메라가 1.85m로 높아 변기가 화면 아래 끝. START_POS/YAW/PITCH
  조정 -> 변기(화면 x=182) + 문(x=929) 한 화면. 검은 픽셀 0.2%.
- 터널: 손전등 범위 6->9m, 감쇠 0.9->0.6. 03 검은 비율 68%->16%.
- 벽·바닥 텍스처 분리: 타일 메시를 윗면(바닥)/나머지로 두 표면 분리.
- 손 보임 검사(tools/check_captures.py): capture.gd를 보통/`-- nohands`로
  두 번 찍어 차이 픽셀을 셈. 01 3.7%, 03 4.5%, 05 12.4%, 08 4.2% 모두 기준 통과.
- 문 틈 0.04m, 09_korean_fixtures, 물건 목록만: 4a9e4fa에서 반영, 유지 확인.
- 검증: import 0, run_tests 51/51, run_main_tests 26/26, save_load 3/3,
  300프레임 0, 재메싱 5.6ms.

## 다음 (백엔드)

백엔드 목록(할 일 0-10 중 손·시각 관련 제외분)은 현재 완료 상태. 남는 것은
프론트엔드 작업이 진행되면서 나올 백엔드 쪽 추가 요청(예: 새 시그널, 새
depth_at 기반 biome 헬퍼 등) 대응 대기.

## 보류 / 형님께 물을 것

(현재 없음 -- 범위 변경 지시는 반영 완료)

## 소리 1차 (사운드 작업자, 2026-09-29)

- 라이선스: nkido 0.4.9는 **MIT (Copyright 2026 Moritz Laass)**, 렌더 전용 외부 도구로만 사용(샘플 뱅크 끔, 합성만). 판정·루프 도구는 형님 TINProject nkido_pipeline에서 수정 없이 복사한 우리 코드. 자세히: `tools/audio/PROVENANCE.md`. 공유 zip에는 WAV와 우리 코드만 들어간다.
- 소리 32종: 효과음 26종 × 변주 4벌 = 104 WAV, 반복음 8개(씹기 2, 넘겨먹기 신음, 화장실, 몸 드론 2, 심장 2). 목록: `audio/SOUND_LIST.md`. 생성: `tools/audio/build_audio.py`.
- 판정(`audio/REPORT.md`): 183개 전부 PASS, FAIL 0. 기준은 TINProject 값 그대로. 예외 목록은 이름 붙여 적음: 씹기 2개·넘겨먹기 신음·심장 2개는 의도된 박자(반복 티 검사 제외, TIN 드럼·amb_pulse 선례), 입·목·심장 소리는 모노 의도. 몸 드론·화장실 배경은 예외 없이 통과(불규칙한 삐걱임·소화음은 루프에 굽지 않고 키트가 무작위로 재생).
  - 변주는 후보 8개를 렌더해 레벨 차가 가장 작은 4개를 골라 싣는다(선별 후 기준 그대로 판정).
- 키트: `addons/flesh_dig_kit/audio/` FDKSoundBank(연속 중복 없는 변주 선택), FDKAudioDirector(시그널 구독, 배경 크로스페이드, 씹기 속도=1/씹기배율, 발걸음 검출, 3D 위치 재생).
- 게임 연결: `audio/fp_audio_hookup.gd`. **main.gd에 한 줄이 필요하지만** 작업 시점에 main.gd가 프론트엔드 미커밋 변경 중이라 넣지 않았다 → `audio/HOOKUP.md`.
- 검증(Godot 4.7.2 console): import 0, run_tests 51/0, run_main_tests 26/0, run_save_load 3/0, run_audio_tests 118/0(실제 main.tscn에 연결해 검사 포함), run_headless 300프레임 0, 재메싱 5.86ms(예산 8ms, 변화 없음).
- 들어 볼 파일: `audio/listen/`(23개, README.txt).

## 세션 D (조직·도구) — W10 W20 W21 W22 W23 W24 W25 W26 W28
- 조직 규칙: addons/flesh_dig_kit/terrain/fdk_tissue_rules.gd (경도 1.0/1.4/1.2/막 2.0, 재생 1.5/1.0/0.8/막 0, 수축 조직 8초 주기 +0.3, 1초 전 경고 신호 contraction_warning).
- 막: 화장실 둘레 + 껍질 경계(9 m, 18 m) 0.9 m 띠. 맨손 불가, 칼·큰 톱 가능. 경계 앞 1.8 m는 다음 조직이 섞임.
- 쉼터: 2/4/6곳, 껍질 가운데 깊이, 피보나치(부족하면 정다면체)+게임마다 무작위 회전(rest_seed 저장), 같은 껍질 90도 이상. 안에서 압사 0.
- 스프레이: 통당 6번, 반경 0.75 m, 싼 통 0.5 m / 비싼 통 1.5 m 깊이, 녹은 셀 1 m 안 재생 x2. 녹은 면은 회색 텍스처.
- 믹서기: 신경 조준 후 누르고 있으면 초당 25 충전, 1.5초 뒤·이후 1.5초마다 수축. 돌리기 1.5초 + 고개 젖혀 마시기 1.5초, 위장 60%. 옆면 불빛 10개.
- 큰 톱: 한 번에 6셀, 시간 x1.5, 바로 위장. 죽음: 마지막 위치에 붉은 등 말뚝 표지(드롭이 밀려도 제자리).
- 테스트: tests/run_tissue_tools_tests.gd. 캡처: captures/session_d/ (tools/session_d_capture.gd).
- 소리 연결 필요(소리 세션): FDKTerrainField.contraction_warning(world_pos) → 수축 조임 소리 1초 전.

## 세션 A — W01 W02 W07 W09 W13 W14 (화장실 생김새, 2026-09-30)

- W01 방: 형님 지시로 좌우(X)를 넓힘 4.5 x 2.6 x 3 m(HALF 2.25, 1.3, 1.5). 오른쪽(+X) 벽에 두 칸 서랍장(WallDrawer, DrawerTop/DrawerBottom 노드). 환풍구 위치는 FPRestroom.VENT_CENTER(변기 맞은편 벽 쪽 천장, 좌석 정면). 카나리아 구멍 FPRestroom.CANARY_HOLE: 세면대 아래 구석 벽 밑, 반치마(SinkApron, 바닥에서 0.34 m까지) 뒤라 서서는 안 보이고 쪼그려야 보임.
- W02 오프닝: FPOpening(검정 1.6초 -> 0.7초 밝아짐 -> 1.6초 일어남). main.apply_opening_at(t), 신호 opening_flush.
- W07 자막: FPSubtitles. vent.line_spoken(id) -> main/data/vent_lines.json 의 ko 문장(없으면 내장 표). 환풍구 눈은 더 크고 낮게(덕트 입구에서 보이게).
- W09 팔 털: 핵 털 색 진분홍(spec 02), 40가닥 초과 시 길고 굵은 덥수룩 모양.
- W13 손 피: FPHandBlood 오버레이(손끝부터 번짐, hand_blood 0~1). 세면대에서 씻으면 0.
- W14 문 빛: 문이 열린 만큼 DoorSpill(스포트)·DoorSpillFill 이 통로로 빛을 던짐. 돌아올 때 눈부심은 기존 _flash.
- 캡처: tools/restroom_capture.gd (창 모드 --write-movie, shots.txt에 샷별 프레임). 결과 captures/restroom_a/*.png.
## 세션 E (위험·카나리아·엔딩·조작, 2026-09-29)
- W41 엔딩: 사람 없는 밝은 낮 거리, 매끈한 생고기 경단 공 반지름 42 m(빌딩 약 26 m보다 큼), 출발 z -62 m로 당김. 착지 뒤 카메라가 거리 뒤로 물러남. 캡처 captures/ingame/ending.png
- W03 카나리아: 구멍을 보고 상호작용 -> 1.6초 엎드려 두 손을 넣고 꺼내 주머니(has_canary). begin_canary_pull(). 캡처 canary_pull.png
- W32 조작: fp_input_modes.gd (패드 스틱·트리거·A/B/X/Y, 마우스 전용: 가운데 버튼 걷기, 옆버튼 상호작용/들기, 휠 도구). 글자 없는 상호작용 링 fp_interact_ring.gd
- W27: 체력은 손의 멍(fp_danger_show.gd), 압사는 시야가 조이고 떨림. 화면 가장자리 효과 없음. 캡처 crushed.png
- W29/W40/W42: 기존 구현 확인 + 테스트(좁아지는 통로, 바깥 경계 직전 엔딩 없음, 껍질별 선율 크기)
- D03: 코드 주석 design-core 참조 -> docs/spec 경로