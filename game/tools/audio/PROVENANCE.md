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
