# tools/audio 출처와 라이선스

- 소리 엔진: nkido 0.4.9 (`C:\projects\_tools\nkido`, https://github.com/mlaass/nkido). **MIT License, Copyright (c) 2026 Moritz Laass** (LICENSE 파일로 확인). 렌더할 때만 쓰는 외부 실행 파일이며 게임·키트에는 들어가지 않는다. `--no-default-bank`로 샘플 뱅크를 끄고 합성만 한다(외부 샘플 0개).
- `analyze_audio.py`, `loopify.py`, `render_variations.py`: 형님 저장소 TINProject `tools/nkido_pipeline/tool/`에서 **수정 없이 복사**(우리 코드. TINProject에는 LICENSE 파일이 없고 외부 코드가 아님). `targets.json`의 기준값도 거기 `analysis_targets.json`에서 그대로 가져왔다.
- `build_audio.py`, `sounds.json`, `targets.json`, `patches/*.akkado`: 이 작업에서 새로 작성(우리 코드).
- 결과 WAV(`game/audio/`): 위 패치에서 합성한 우리 소유 결과물. 키트 공유 zip에는 WAV와 우리 코드만 넣는다(nkido 바이너리·소스 없음).

다시 만들기: `python -X utf8 build_audio.py` (결과와 판정은 `game/audio/REPORT.md`).
