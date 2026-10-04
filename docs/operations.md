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
