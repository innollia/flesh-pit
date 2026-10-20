# 실행과 검증

Godot 4.7 Compatibility와 node:test를 실행할 Node.js가 필요하다. Windows에서는 godot_console이 PATH에서 실행되어야 한다. 저장소 루트에서 처음 가져온 프로젝트의 리소스를 먼저 가져온다.

```powershell
godot_console --headless --editor --path game --import
godot_console --path game
node --test game/tests/run_godot_checks.cjs
```

기본 Node 검사는 실제 Godot의 기존7개 검사를 호출하고 Main 저장을 별도 경로로 격리한다. FP_CHECK_SUITES는 run_으로 시작하는 검사 파일명을 쉼표로 지정하며 지정한 모든 검사의 종료 코드·실패 수·스크립트 오류를 전달한다. GUI 캡처와 저장 비교를 동시에 실행해 성능 결과를 오염시키지 않는다.

지형과 보존 검사를 포함한 실행:

```powershell
$env:FP_CHECK_SUITES='run_tests.gd,run_tissue_tools_tests.gd,run_save_load.gd,run_oct02_tests.gd,run_motion_tests.gd,run_watch_door_restore_tests.gd,run_spray_attachment_tests.gd,run_terrain_regen_regression_tests.gd,run_terrain_surface_regression_tests.gd,run_terrain_surface_patch_tests.gd,run_terrain_surface_pending_tests.gd,run_terrain_publication_epoch_tests.gd,run_terrain_dig_regression_tests.gd,run_terrain_solid_aim_tests.gd,run_terrain_solid_dig_tests.gd,run_terrain_batch_budget_tests.gd,run_terrain_density_cache_tests.gd,run_terrain_old_save_tests.gd,run_terrain_barrier_pressure_tests.gd,run_preservation_tests.gd'
node --test game/tests/run_godot_checks.cjs
```

GUI 지형 검사 전체는 node --test game/tests/run_godot_render_checks.cjs로 실행한다. GUI 지형 검사에는 실제 해상도를 지정한다. 아래처럼 각 capture_terrain_*.gd를 독립 실행하고 출력의 실패0과 종료0을 확인한다. 캡처 프로그램은 자체의 격리 경로를 사용한다.

```powershell
godot_console --path game --resolution 640x360 --fixed-fps 60 --script res://tests/capture_terrain_main_restore.gd
godot_console --path game --resolution 640x360 --fixed-fps 60 --script res://tests/capture_terrain_main_solid.gd
```

성능은 `godot_console --path game --resolution 1280x720 --script res://tests/bench_play.gd`로 잰다. 같은 플레이(화장실 둘러보기, 문에서 파고 나가기, 긴 통로 걷기, 판 동굴 둘러보기)를 수직 동기화 없이 돌린다. 구간마다 프레임·GPU·그리기 호출과 CPU 구간별 ms(FPProfile)를 한 줄씩 낸다. 다른 기계·해상도의 수치와 비교하지 않는다. 격리 사본에서 실행한다.

함수 단위 비용은 `python -X utf8 tools/perf/godot_profile.py`로 본다. Godot 자체 스크립트 프로파일러를 원격 디버그로 받아 기록하므로 엔진을 다시 빌드하지 않아도 된다(Tracy는 엔진을 따로 빌드해야 한다).
- `capture --project <격리>/game --out x.json`: `bench_play.gd`를 돌리며 단계(`bench:phase`)별로 함수마다 호출 수·self·total ms를 모으고, 단계마다 가장 느린 프레임 5개의 구성을 남긴다.
- `hotspots x.json --phase tunnel_walk [--by total]`: 비싼 함수 순위.
- `hitches x.json --phase tunnel_walk`: 끊김 프레임이 무엇으로 찼는지.
- `compare a.json b.json`: 수정 전후 함수별 차이.

수정 전후 비교는 HEAD 코드에 같은 벤치를 얹은 격리 사본과 변경한 격리 사본을 번갈아 잰다. 측정만 하는 `.claude/agents/performance-analyst.md`가 이 절차를 따른다. 구현한 쪽이 스스로 개선을 판정하지 않게 측정을 그 에이전트에 맡길 수 있다.

FP_AUDIO_LOG=1은 소리 이벤트 로그만 켠다. FP_PLAY_LOG=<CSV 경로>는 보상 척도용 플레이 기록을 남긴다(docs/spec/09-reward-scale.md 10.2). 원정 시간을 재려면 이 기록으로 몇 번 원정한 뒤 `python -X utf8 tools/economy/reward_scale.py --log <CSV 경로>`로 읽는다. 기록은 저장 슬롯과 설정을 바꾸지 않는다. 기록 장치 자체는 `run_play_log_tests.gd`로 검사한다. FP_TERRAIN_EVIDENCE는 이를 지원하는 성능·캡처 프로그램의 출력 경로이며 플레이 데이터 경로가 아니다. 엔진이 검사 시작 전에 멈추면 시간 초과를 실패로 기록하고 원인을 확인해 같은 검사를 다시 실행한다. 사용자의 editor 프로세스를 종료하지 않는다.

클린룸 플레이테스트는 코드와 문서를 모르는 플레이어 에이전트가 처음 하는 사람처럼 플레이하고, 평가자가 그 기록에 플레이어가 못 본 텔레메트리를 더해 발견을 내는 절차다(결정 0007).
1. `python -X utf8 tools/playtest/run_session.py --session <이름> --no-agent`: `game/`을 `%TEMP%/flesh-pit-playtest/<이름>/iso`로 복사하고 `config/name`을 `flesh-pit-playtest-<이름>`으로 바꿔 `user://`를 따로 둔다. 그 폴더를 비운 뒤 브리지(`game/tests/playtest_bridge.gd`)를 autoload로 넣고, 960×540·`--fixed-fps 30`으로 띄운다. 플레이어의 방(`room/`)에는 `play.py`, `manual.md`, 화면이 쌓이는 `session/`만 있다. 텔레메트리와 로그는 `evidence/`에 쌓인다.
2. 플레이어: `claude` CLI가 로그인되어 있으면 `--no-agent` 없이 실행한다. `claude -p`가 방에서 돌며 `python play.py`와 방 안 Read 말고는 거부된다. CLI를 쓸 수 없으면 방 폴더를 프로젝트로 하는 새 세션(방은 실행기가 git 저장소로 만든다)에서 같은 규칙으로 플레이시킨다. 이 세션 안의 하위 에이전트는 세션 시작 때 읽힌 `CLAUDE.md`와 메모 색인을 그대로 받으므로(파일을 숨겨도 같다) 마지막 수단이다. 하위 에이전트를 쓰면 `.claude/agents/playtester.md`의 규칙으로 띄우고, 끝난 뒤 `python -X utf8 tools/playtest/audit_player.py <대화 기록 jsonl> <방>`으로 방 밖을 본 호출이 없었는지 검사한다. 하나라도 있으면 그 회차는 버린다. 하위 에이전트는 프로젝트 `CLAUDE.md`를 문맥으로 받고 시작한다(검사 결과에 적힌다).
3. `run_session.py --session <이름> --stop [--transcript <하위 에이전트 jsonl>]`: 게임을 끝내고 `evidence/trajectory.md`(step마다 명령·메모·화면 글자·소리·텔레메트리)와 `player_report.md`를 만든다.
4. `.claude/agents/playtest-evaluator.md`의 평가자가 `evidence/evaluation.md`를 쓴다. 발견마다 step·화면·텔레메트리 증거, 관찰과 추론, 심각도와 확신도를 따로 적고, 에이전트 인식 실패와 UX 문제를 가른다.
- 게임 창은 포커스를 받지 않고 마우스를 통과시킨다. 실제 키보드·마우스는 게임에 닿지 않는다. 브리지가 커서 잡기를 매 프레임 푼다.
- 명령 사이에는 게임 시간이 멈춘다(브리지가 메인 루프를 막고 기다린다). 행동 하나는 최대 10초다.
- 소리는 끈다. 들린 소리는 소리 연결의 `played_events` 이름으로 전한다. 손으로 그린 글자는 화면에만 있다.

개발 실행 외의 배포 대상과 export preset은 이번 검증으로 확정하지 않았다. 배포 작업은 별도 대상과 결과물 확인이 필요하다.

## 복원 작업의 추가 정상 입력 및 역사 저장 검사

화장실·몸·성장 복원을 포함한 최종 CPU 검사는 기존 20개를 유지하고 다음 13개를 더한 33개 묶음이다. 지정 목록 전체를 한 실행에서 확인하며 검사 생략은 통과로 취급하지 않는다.

```powershell
$env:FP_CHECK_SUITES='run_tests.gd,run_tissue_tools_tests.gd,run_save_load.gd,run_oct02_tests.gd,run_motion_tests.gd,run_watch_door_restore_tests.gd,run_spray_attachment_tests.gd,run_terrain_regen_regression_tests.gd,run_terrain_surface_regression_tests.gd,run_terrain_surface_patch_tests.gd,run_terrain_surface_pending_tests.gd,run_terrain_publication_epoch_tests.gd,run_terrain_dig_regression_tests.gd,run_terrain_solid_aim_tests.gd,run_terrain_solid_dig_tests.gd,run_terrain_batch_budget_tests.gd,run_terrain_density_cache_tests.gd,run_terrain_old_save_tests.gd,run_terrain_barrier_pressure_tests.gd,run_preservation_tests.gd,run_restroom_t1_tests.gd,run_motion_t2_tests.gd,run_body_posture_t3_tests.gd,run_progression_t4_tests.gd,run_interaction_component_tests.gd,run_glare_t6_tests.gd,run_nerve_t7_tests.gd,run_crush_t8_tests.gd,run_restoration_t9_tests.gd,run_movement_regression_fix_tests.gd,run_restoration_old_v5_t10_tests.gd,run_restoration_historical_progress_t10_tests.gd,run_hand_controls_tests.gd'
node --test game/tests/run_godot_checks.cjs
```

다음 프로그램은 정상 Main/플레이어 process와 physics를 유지한다. 플레이 행동은 실제 입력으로 확인하고, 공유 섭취 소비자·타이틀·저장 계약을 직접 호출하는 검사는 별도로 구분한다. GUI는 640×360, fixed60에서 따로 실행하고 서로 동시에 실행하지 않는다. 첫 번째 명령의 핵 75셀 섭취는 몇 분이 걸리므로 짧은 일반 검사 시간 제한을 그대로 적용하지 않는다.

```powershell
godot_console --path game --resolution 640x360 --fixed-fps 60 --script res://tests/capture_restoration_core_t10.gd
godot_console --path game --resolution 640x360 --fixed-fps 60 --script res://tests/capture_restoration_play_t10.gd
godot_console --path game --resolution 640x360 --fixed-fps 60 --script res://tests/capture_restoration_connected_t10.gd
$env:FP_CHECK_SUITES='run_restoration_old_v5_t10_tests.gd,run_restoration_historical_progress_t10_tests.gd'
node --test game/tests/run_godot_checks.cjs
```

추가 프로그램은 userdata가 flesh-pit-restoration- 이름의 격리 환경인지 확인하며, Main을 트리에 넣기 전에 별도 저장 경로를 지정한다. 역사 파일 복사본은 runner의 Main 초기 설정 뒤 실제 복원 직전에 경로를 다시 지정한다. 정상 사용자 저장이나 settings를 읽지 않는다. 자료 출처·바이트 수·SHA-256은 tests/fixtures/restoration_historical_progress_provenance.json에 있다.

카메라 가드의 headless 검사는 process_frame 신호 직후가 아닌 정상 Main/손 노드 이후의 읽기 전용 관찰로 판정한다. 관찰 노드는 가드를 추가 호출하거나 카메라를 쓰지 않는다. 혼합 셀의 max8 밀도는 실제 점의 고체 판정이 아니므로, 통로 검사는 실제 현재 면의 안팎과 전체 캡슐을 확인하고 독립 8모서리 보간값을 진단 기록에 남긴다.

기본 `run_godot_checks.cjs`에는 `run_live_interactions_tests.gd`의 실제 키 입력 회귀가 포함된다. 단독 원본 스크립트 실행은 restoration userdata를 요구한다. runner가 생성한 격리 사본은 Main을 추가하기 전에 별도 저장 경로를 지정하므로 일반 프로젝트에서 CPU 검사할 때도 정상 슬롯을 사용하지 않는다. GUI에서 같은 사본을 실행하면 `.dryforge/evidence/live-interactions/`에 V 안내·NPC 지급·카나리아 단계와 실제 엎드린 몸을 캡처한다.
