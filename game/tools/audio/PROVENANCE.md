# tools/audio 출처와 라이선스

- 소리 엔진: nkido 0.4.9 (`C:\projects\_tools\nkido`, https://github.com/mlaass/nkido). **MIT License, Copyright (c) 2026 Moritz Laass** (LICENSE 파일로 확인). 렌더할 때만 쓰는 외부 실행 파일이며 게임·키트에는 들어가지 않는다. `--no-default-bank`로 샘플 뱅크를 끄고 합성만 한다(외부 샘플 0개).
- `analyze_audio.py`, `loopify.py`, `render_variations.py`: 형님 저장소 TINProject `tools/nkido_pipeline/tool/`에서 **수정 없이 복사**(우리 코드. TINProject에는 LICENSE 파일이 없고 외부 코드가 아님). `targets.json`의 기준값도 거기 `analysis_targets.json`에서 그대로 가져왔다.
- `build_audio.py`, `sounds.json`, `targets.json`, `patches/*.akkado`: 이 작업에서 새로 작성(우리 코드).
- 결과 WAV(`game/audio/`): 위 패치에서 합성한 우리 소유 결과물. 키트 공유 zip에는 WAV와 우리 코드만 넣는다(nkido 바이너리·소스 없음).

다시 만들기: `python -X utf8 build_audio.py` (결과와 판정은 `game/audio/REPORT.md`).

## 2차 (실제 녹음 레이어, 2026-09-29)

- 1차 커밋(1855bf1)에서 이미 받아 둔 CC0 recordings(`samples/src/<category>/fs*.mp3`, freesound.org, 각 소리 CC0 라이선스 확인됨)를 `ffmpeg`(winget Gyan.FFmpeg, 이 작업에서 설치, MIT/LGPL 빌드)로 48kHz 16bit WAV로 디코딩만 했다. ffmpeg는 렌더 도구일 뿐 게임에 들어가지 않는다.
- `build_audio.py`에 `load_real_layer()`를 추가: `sounds.json`의 `real_layer` 필드(샘플 경로, 구간, 게인, 피치, hp/lp)로 지정된 실제 녹음을 리샘플·필터링해 합성(nkido) 결과 위에 더한다. 합성은 질감 보조층, 실제 녹음이 정체성을 담당하는 방향(형님 피드백 총평).
- 카나리아 경고음(canary_warn)은 기존에 받아 둔 canary 샘플(`canary/fs85401.wav`)을 피치업(1.25x)해 재사용했다. 사람 신음(chew_strain, 10번 피드백)은 CC0 사람 발성 녹음을 구하지 못해 합성 파라미터만 조정(소울음 배음 제거, 성대 프라이 노이즈 추가)해 처리했다.
- 재현: `python -X utf8 build_audio.py` (ffmpeg가 PATH에 있어야 mp3 디코딩 단계가 필요할 때 동작; 이미 디코딩된 `.wav`가 있으면 불필요).

## 3차 (2단계 청취 피드백 반영, 2026-09-29 21:xx)

## 4차 (합성층 축소 + 신규 CC0 녹음 확보, 2026-09-29 저녁)

- 3차에서 freesound API 401로 막혔던 신규 CC0 녹음을 bigsoundbank.com(CC0, 로그인 불필요, `/UPLOAD/mp3/<번호>.mp3` 직접 다운로드 가능)에서 확보: `chew2/fs0407.wav`(씹기, "Eat a Rusk"), `chew2/fs0352.wav`(입 소리, "Mouth Noises #1"), `vomit2/fs2499.wav` `vomit2/fs2496.wav`(사람 구토, "Man vomiting #4/#1"), `nerve/fs2949.wav`(채찍 소리, "Whip crack #1"), `mud/fs0495.wav`(젖은 진창 발걸음, "Steps in the Mud"). 전부 저자 Joseph SARDIN, CC0(public domain) 명시. mp3는 ffmpeg로 48kHz mono wav로 디코딩.
- ear.py로 원본 CC0 녹음 자체를 먼저 검증(RAW_PROBE 방식 확장): 기존 `chew/fs22416.wav`는 CLAP top이 heartbeat, `vomit/fs338116.wav`는 top이 breaking으로 나와 재료 자체가 부적합했음을 확인. 위 신규 녹음들은 모두 의도한 텍스트가 CLAP top-1로 확인된 후에만 sounds.json에 채택했다.
- sounds.json의 real_layer를 신규 녹음으로 교체(tear_nerve, chew_loop_a/b, chew_strain, vomit_toilet/floor)하거나 신설(step_flesh_s1/s3에 real_layer 추가, 기존엔 순수 합성)했고, 대응하는 akkado 패치의 합성 출력 스케일을 05~0.18 수준까지 낮춰 실제 녹음이 소리 정체성을 주도하도록 했다.
- amb_body_a/b는 규칙적인 saw() 드론(0.125Hz 스웰)이 "engine idling"으로 오인되는 근본 원인이었음을 확인하고, 패치를 saw 드론 제거 + 여러 저주파(0.033~0.067Hz)로 위상이 어긋나는 noise-gate 기반 불규칙 저음 꿀렁("gurgle")으로 교체. 결과: CLAP top에서 engine idling이 사라짐(현재 top은 ocean waves/wind blowing — 청감 우선 유지 예외 영역, README_EAR.md의 CLAP 지속음 한계).
- chew_strain은 real_layer gain을 올리는 것만으로는 body_a/b 배경 대비 masking_margin_db(자기 스펙트럼 에너지 가중 마진) 게이트를 통과하지 못해(target_lufs -24가 배경보다 너무 조용한 설계), real_layer의 hp를 900~1400Hz로 올려 배경과 겹치는 저음대를 피하고 합성 groan_tone 비중을 낮춰 최종적으로 게이트 통과 + CLAP top-1(사람 그런팅) 동시 달성.
- 최종 결과: LISTEN_REPORT.md 22개 중 19개 OK. WARN 3개(19_amb_restroom, 20_amb_body_a, 21_amb_body_b)는 형님이 이미 방향을 확정한 배경음 예외(19는 손대지 말라는 지시, 20/21은 엔진 오인만 제거하면 되는 목표를 달성)로 청감 우선 유지.
- build_audio.py 전체 게이트(PASS 183 / FAIL 0, 기준·예외목록 변경 없음)와 Godot 헤드리스 오디오 테스트(118 passed, 0 failed, 종료코드 0) 모두 통과. `game/tools/audio/ear/`는 핵심 도구(ear.py, README_EAR.md, update_listen_folder.py, run_godot_test.py, probe2_extract.py, requirements.txt)만 남기고 이전 작업자가 남긴 임시 스크립트·로그·wav 폴더는 모두 정리했다.


- 1차(7ea1881) 실제 파일을 git show로 꺼내 ear.py로 형님의 1차 청취 피드백과 대조: 판정 대상 19개 중 16개 일치(84.2%). 03(tear_fat), 18(canary_warn), 22(depth_marker, 당시 파일)는 도구가 통과로 봤지만 형님은 문제로 지적한 역방향 불일치.
- 2단계 WARN 항목 개선: sounds.json의 real_layer(gain_db/hp/lp)를 조정하고 akkado 패치의 합성 출력을 최대 60%까지 줄여 CC0 실제 녹음의 비중을 높였다. depth_marker에는 ding/fs531031.wav(bicycle bell)을 새 real_layer로 추가하고 파도(res 노이즈) 볼륨을 0.18->0.07로 축소. chew_strain에는 body/fs214865.wav(chewing/biting 계열)를 새 real_layer로 추가. amb_body_a/b는 중음대(300-450Hz) 필터링 노이즈 레이어를 추가하고 target_lufs를 5~6dB 올려 가청성을 개선했다(순수 tri() 톤은 8초 루프 안에서 repetition-tick 게이트에 걸려 노이즈로 교체).
- 결과: 05_swallow, 22_depth_marker가 WARN에서 OK로 개선. 나머지 10개(01,03,07,08,09,10,11,12,13,15)는 real_layer 게인을 최대 +14dB까지 올리고 tear_nerve는 샘플 자체를 tear/fs133440->tear/fs234236으로 교체했음에도 CLAP top-1이 바뀌지 않았다. freesound.org API가 API 키 없이는 401을 반환해 신규 CC0 녹음을 추가로 확보하지 못한 것이 근본 제약이다.
- build_audio.py 판정(PASS 183 / FAIL 0)과 Godot 헤드리스 오디오 테스트(118 passed, 0 failed, 종료코드 0)는 모두 통과. game/audio/listen/과 README.txt, LISTEN_REPORT.md를 이번 결과로 갱신했다.
