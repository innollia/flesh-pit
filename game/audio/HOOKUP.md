# 소리 연결 방법 (HOOKUP)

소리 쪽 코드는 전부 남의 파일을 고치지 않고 시그널 구독·읽기만 한다. 게임에 붙이는 데 **main.gd 한 줄**만 필요하다.
작업 시점(2026-09-29)에 `main/scripts/main.gd`가 프론트엔드 작업자의 미커밋 변경 중이라 직접 넣지 않았다.

`main/scripts/main.gd`의 `_ready()` 맨 끝에 추가:

```gdscript
    add_child(preload("res://audio/fp_audio_hookup.gd").new())
```

그 한 줄이 하는 일(`audio/fp_audio_hookup.gd`):
- 키트 `FDKAudioDirector` 생성, `res://audio/manifest.json` 로드
- `chewer`(grab_started/cell_torn/released), `stomach`(fill_changed, vomited), `player`(footstep_bob) 구독
- 화장실 안/밖으로 배경·발 표면 전환, 깊이 껍질(RESTROOM_CENTER 거리 / SHELL_THICKNESS)로 깊은 배경·이정표
- `restroom.is_door_open()`, `restroom._lid_target`, `main._coin_t`, `main.is_settling()` 변화를 읽어 문·뚜껑·동전·물 내림
- `mutation_points / 400`을 3단계로 나눠 발걸음·씹기 변화

이 연결은 `tests/run_audio_tests.gd` 끝부분에서 실제 main.tscn에 붙여 검증한다(시작 배경=화장실, 찢기 소리 발생).

카나리아: 게임에 아직 카나리아 로직이 없다(`CanaryTODO` 빈 노드). 생기면 `director.play_canary("normal"|"warn"|"wrong", 위치)`를 부르면 된다.

키트 문서: `addons/flesh_dig_kit/README.md`, `CHANGELOG.md`에 audio/ 폴더 설명 한 단락이 필요하다(그 파일들은 소유자가 따로 있어 건드리지 않음). 넣을 문장:
"audio/: FDKSoundBank (manifest-driven streams, no back-to-back repeat) and FDKAudioDirector (subscribes to FDKChewer/FDKStomach/controller signals; bed crossfades; chew speed follows stomach overfill)."

## 5차 새 소리 연결

`fp_audio_hookup.gd`가 이미 있는 신호는 스스로 구독한다: `main.died`->player_death, `main.ending_reached`->ending_roll, `mirror.mutated`->mirror_mutate, `barrier_field.barrier_broke`->barrier_break, 장벽 개수 증가->barrier_deploy, 각 장벽 `damage_step_changed`->barrier_strain, `vent.is_open` 켜짐->vent_open.
게임에 신호가 없는 것은 부를 함수만 있다(main에서 hookup 노드를 찾아 호출): `on_tumor_eaten()`, `on_spray(pos)`, `on_blender_drink()`, `on_scissors()`, `on_saw_stroke()`, `on_settle_tick()`, `on_ui_click()`, 또는 `play_event(이름, 위치)`(이름 표는 `EVENT_SOUNDS`).

## 연결 완료 (2026-09-30)

- `main.gd` `_ready()` 끝에서 `AudioHookup` 노드로 붙였다(위 한 줄).
- 신호가 없던 7개에 신호를 만들어 연결했다: `mutation_apply.tumor_eaten`->tumor_eat, `main.spray_used(pos)`->spray, `main.blender_drunk`(마시기 시작)->blender_drink, `main.scissors_snipped`/`main.saw_stroked`(칼·톱으로 뜯을 때)->scissors/saw, `main.settle_ticked(teeth)`(레버·쉼터 정산)->settle_tick, `main.ui_clicked`(main 아래 모든 버튼과 토하기 버튼)->ui_click.
- `FP_AUDIO_LOG=1` 환경변수를 켜고 실행하면 `[audio] play_event <이름>`이 로그에 찍힌다. `played_events`에 순서대로 남는다.

## 세션별 신호 메모 (옛 game/audio/HOOKUP.md)

## W04~W06 (세션 B)
- FPToiletSettlement.tank_rattle_started(duration, tumor): 물탱크 달그락 소리. 길이는 duration(종양이면 훨씬 김).
- FPVent.line_spoken(line_id): 환풍구 존재 음성/자막. id와 한국어 문장은 game/main/data/vent_lines.json.

- (세션 D) 수축 조직 조임 경고: FDKTerrainField.contraction_warning(world_pos: Vector3) 신호가 조이기 1초 전에 청크마다 한 번 뜬다. 여기에 조임 소리를 연결해 달라.
## 세션 C (거울·변이·종양)

- `main.mirror` 신호 `mutated(id)`: 거울에서 변이를 산 순간. 털이 팔에서 빠지는 소리 + 몸이 바뀌는 소리. id가 `T1`~`T7`이면 종양 혹이 터지듯 자라는 소리.
- `main.mirror` 신호 `denied(part)`: 털이 모자라 부위가 빨갛게 깜빡일 때 짧은 거절 소리.
- `main.mutation_apply` 신호 `tumor_eaten()`: 종양을 먹는 전용 효과음(스펙 05 4절 "종양을 먹는 효과음이 따로 있다").
- `main.mutation_apply` 신호 `alien_hand_tore()`: M22 외계인 손이 멋대로 뜯어 먹을 때.
- `main.mutation_apply` 신호 `gulped()`: M15 빠지는 턱으로 살 더미를 통째로 삼킬 때(굵은 꿀꺽).
- `main.mutation_apply` 신호 `echo_click()`: T1 반향정위 혀 딸깍(1.2초마다).
- `main.mutation_apply` 신호 `echo_pulsed(counts)`: T1 딸깍 반향이 다 퍼진 순간(약 0.3초 뒤). 신경/종양이 잡히면 되돌아오는 소리를 조금 다르게 해도 됨.
- `main.mutation_apply` 신호 `hair_shiver_started()`: M23 감각털. 수축 1.5초 전 팔 털이 떨리기 시작할 때 마른 사각거림. 세기는 `hair_shiver`(0~1).
- `main.mutation_apply.magnet_hum_level()` (0~1): M03 자기장 눈. 화장실 쪽을 볼수록 귀에서 낮게 윙.
- `main.progression.has_mutation("M02")`: 넓은 목구멍이면 삼키는 소리를 굵게. `has_mutation("M04")`: 불거진 턱이면 씹는 소리를 바꿈.

## 세션 A (화장실 생김새)
- main.gd 신호 opening_flush(): 게임 시작 직후 검은 화면(약 1.6초) 동안 변기 물 내리는 소리. _begin_opening()에서 한 번. 오프닝 전체 길이 FPOpening.TOTAL(3.9초).
- 카나리아 새소리 발원 위치: FPRestroom.CANARY_HOLE (세면대 아래 구석, 바닥 근처, 반치마 뒤).
- 문 열린 정도: restroom.door_open_amount() (0~1). 형광등 웅웅 소리가 통로로 새어 나가는 데 쓸 수 있음.

## 세션 E (카나리아·엔딩)
- 카나리아 꺼내기: `main.is_pulling_canary()`가 true인 1.6초 동안 엎드림·팔 넣기 소리, 중간에 `has_canary`가 true가 되는 순간 짧은 새 퍼덕임.
- 구멍 새소리: `has_canary`가 false일 때만 `FPRestroom.CANARY_HOLE`에서 크게.
- 압사 진행: `main.crush_progress()`(0~1) 에 맞춰 살 조이는 소리를 키워도 됨. 경고는 카나리아 `canary_chirp(urgency)`.
- 엔딩: `ending.voice_layers`(1, 도감 완성 시 2) 겹 허밍. 살 속 선율 크기 `main.melody_level()`(화장실 0, 바깥일수록 1).