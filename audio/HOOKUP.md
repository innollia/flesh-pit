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
