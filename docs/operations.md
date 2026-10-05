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

FP_AUDIO_LOG=1은 소리 이벤트 로그만 켠다. FP_TERRAIN_EVIDENCE는 이를 지원하는 성능·캡처 프로그램의 출력 경로이며 플레이 데이터 경로가 아니다. 엔진이 검사 시작 전에 멈추면 시간 초과를 실패로 기록하고 원인을 확인해 같은 검사를 다시 실행한다. 사용자의 editor 프로세스를 종료하지 않는다.

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
