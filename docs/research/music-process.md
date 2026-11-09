# flesh-pit 배경음악은 어떻게 만들어졌나

olmuse4 세션에 넘기는 공정 기록이다. AI로 음악을 만들고 있는데 flesh-pit에서 나온 곡만큼의 품질에 닿지 못한다고 해서 정리했다.

**표기.** **[사실]** 은 대화 기록(JSONL), 작업자 보고, 저장소 파일에서 확인한 내용이다. **[추론]** 은 이 문서를 쓴 쪽의 해석이다. 둘을 섞지 않으려고 문단마다 붙였다.

**출처.** 오케스트레이터 세션 `87b46f4f…`(2026-11-03~04)와 그 하위 작업자 `87b46f4f…/subagents/agent-*.jsonl`, 이어받은 세션 `d2778867…`(11-07~09)와 그 하위 작업자, 노트 폴더 `side-session-notes/local_34b34be7…/orchestra/`(music-lab, wire/music, wire/music2)와 `local_d1bd63dd…/round5`, `round6`, 저장소 `game/tools/audio/`, `tools/build_*.py`, `docs/design/`. `34b34be7…jsonl` 본문에는 음악 대화가 거의 없다. 실제 음악 작업은 그 인계 세션 `87b46f4f`에서 했다.

---

## 0. 한눈에 보기

### 사용자 판정 (기준점)

| 곡 | 무엇 | 사용자 말 [사실] |
|---|---|---|
| `mus_pause_alt` | 펠트 피아노, Db장조 66 bpm, 87 s. 화장실에서 Esc(눈 감기) | "되게 좋아서 유튜브에 바로 올리고 싶을 정도야" |
| `lab_emotion` | 3/4 자장가, 72 bpm, 100 s. 어긋난 음이 맞아 들어가며 지나치게 달아진다 | 위와 같은 말 |
| `lab_artstyle`, `lab_materials`, `lab_cycle` | 후보곡 | "후보로 만든 음악 초반 4개 좋아" |
| `lab_artstyle` | 타일·살 벨 주제, 85 s | "너무 신나서 바로 넣기는 좀 그렇다. 전자적이기도 하고. 유기물의 느낌보다는." |
| `lab_contrast` | 싸구려 대기음악처럼 밝은데 구조가 어긋난 곡 | "6은 트레일러에 넣기 좋은듯" |
| `mus_pause`(옛 판, 입 다문 허밍) | 처음 만든 numpy 합성곡 | "mus_pause는 특히 안어울려" |
| 첫 배경음악 5곡(numpy) | 모두 엔딩 노래 선율의 변주 | "필요한 곳마다 서로 다른 느낌으로 더 만들어줘" (서로 비슷하다는 불만) |

### 이 문서의 결론, 다섯 줄

1. **[사실]** 좋은 곡 두 개는 각각 **작업자 하나(Opus 5.5, general-purpose)가 20~25분 만에 패치를 한 번 써서** 나왔다. 사람 피드백을 받아 고친 판이 아니다. 패치를 쓴 뒤에는 측정으로 결함만 고쳤다.
2. **[사실]** 주제를 "감정만" 같은 **한 가지 축**으로 좁히고, 기존 곡을 못 보게 한 **클린룸** 작업자에게 맡겼다. **[추론]** 기존 곡의 변주를 시킨 첫 판(5곡)은 서로 닮아서 퇴짜를 맞았다.
3. **[사실]** 소리는 손으로 짠 numpy 합성이 아니라 **nkido(akkado 패치 언어)** 로 만들었다. 사용자가 numpy를 명시적으로 거절했다.
4. **[사실]** 판별 모델(CLAP)은 사용자가 가장 좋아한 펠트 피아노를 **떨어뜨렸다**(현악 패드 gentle 0.60 > 피아노 0.50). 둘 다 남겨 사람에게 들려줬기 때문에 살아남았다. CLAP은 `mus_pause_alt`를 "electronic" 0.889로 판정하기도 했다.
5. **[추론]** 품질을 만든 것은 도구보다 **작곡 설계**다. 곡 전체를 하나의 변화 과정(어긋남 → 맞음 → 과함)으로 짜고, 그 과정을 음색 변수(detune, 처짐, 틱의 박자감)에 **마디 단위 곡선**으로 묶었다.

---

## 1. 도구 사슬

### 1.1 nkido와 akkado

- **[사실]** 실행 파일은 `C:\projects\_tools\nkido\build-clang\bin\nkido.exe`, 문서는 `C:\projects\_tools\nkido\docs`, 함정 모음은 `C:\Users\fixme\Desktop\TINProject\tools\nkido_pipeline\KNOWHOW.md`다. TINProject에서 가져온 파이프라인이다.
- **[사실]** 렌더 명령의 기본형은 다음과 같다(오케스트레이터가 작업자에게 보낸 그대로).

```
nkido.exe render <patch.akkado> -o out.wav --seconds N --rate 48000 --bpm B --no-default-bank
```

  `--no-default-bank`를 쓰면 샘플 뱅크가 꺼지므로 순수 합성만 남는다(`sample()`은 무음). `lab_emotion`은 여기에 `--float32 --stems`를 붙였다. `--stems`는 `bus(n, …)`마다 `t.bus1.wav…`를 따로 써 주기 때문에 층별 레벨을 잴 수 있다.
- **[사실]** `lab_emotion` 작업자가 읽은 문서: `KNOWHOW.md`, `docs/grammar/akkado-grammar.md`, `docs/mini-notation-reference.md`, `docs/agent-guide-userspace-functions.md`, `docs/prd-timeline-curve-notation.md`, `docs/prd-beats-per-cycle.md`, `docs/prd-glide-interp.md`. **[추론]** 마디마다 값을 바꾸는 곡선(`v"…"`, `glide`)을 문서에서 익혔기 때문에 곡 전체에 걸친 변화를 패치 안에 쓸 수 있었다.

### 1.2 akkado에서 곡을 쓰는 방식

- **[사실]** 한 사이클(cycle)이 보통 한 박이다. `lab_emotion`은 `bpm = 24`로 두고 한 사이클을 3/4 한 마디(2.5 s)로 썼다. `lab_materials`는 `--bpm 24`로 7/8 한 마디를 2.5 s에 맞췄다. `mus_pause`는 `bpm = 6`으로 한 사이클을 10초로 늘렸다.
- **[사실]** 음은 미니 노테이션 `n"…"`으로 쓴다. `~`는 쉼, `_`는 이음, `!11`은 반복, `@1.5`는 가중치(박 길이), `:0.6`은 세기, `{sag:1}`은 음마다 붙이는 사용자 인자다. 음색은 `({freq, gate, vel}) -> {…}` 함수로 쓰고 `poly(@, voice, 성부 수)`로 연주한다.
- **[사실]** 곡을 성부별로 나누는 방법은 두 가지였다.
  - 한 패치 안에서 `bus(1..7, …)`로 성부를 나누고 `--stems`로 따로 받는다(`lab_emotion`: lead, keys, low, pad, ticks, air, reverb).
  - 성부마다 패치 파일을 따로 두고, Python `build.py`가 악보를 패치 텍스트로 생성해 각각 렌더한 뒤 더한다(`lab_artstyle` 7개, `lab_cycle` 6개, `lab_materials` 7개). `lab_cycle`은 한 패치에 다 넣자 곱셈 하나를 더한 순간 킥 말고 전부 무음이 됐다. 버퍼 한도(256개) 초과로 추정해 6개 스템으로 나눴다.
- **[사실]** Python은 **악보 생성, 루프 접기, 레벨, 디더, 측정만** 한다. 소리를 만들지 않는다(`memory/music-tool-nkido.md`, 각 build.py 머리말).

### 1.3 루프 만들기 (이음매)

- **[사실]** nkido에는 루프 모드가 없다. 그래서 다음 순서로 만든다.
  1. 곡을 두세 바퀴 렌더한다(`lab_emotion`: 100 s 곡을 205 s로 렌더).
  2. **둘째 바퀴**를 쓴다. 첫머리에 이미 끝부분의 꼬리(잔향, 긴 음)가 들어 있기 때문이다.
  3. 둘째 바퀴 첫 0.6 s를 셋째 바퀴 첫머리와 등전력 크로스페이드한다. 그러면 마지막 샘플이 첫 샘플로 이어진다.

```python
# game/tools/audio/lab/emotion/build.py
def fold(x):
    y = x[N:2 * N].copy()
    c = (.5 - .5 * np.cos(np.pi * np.arange(FADE) / FADE))[:, None]
    y[:FADE] = np.sqrt(1 - c) * x[2 * N:2 * N + FADE] + np.sqrt(c) * y[:FADE]
    return y
```

  게임용 `tools/build_music.py`의 `render_nkido()`도 같다. `2*loop + fold + 0.25`초를 렌더하고 둘째 바퀴를 쓰며, 접는 길이는 `mus_pause_alt` 0.5 s, `mus_pause` 1.5 s다.
- **[사실]** 이음매 판정은 **이음매 도약 ÷ 곡 안 샘플 간 변화의 p99.9** 비율로 한다(`analyze_audio.loop_discontinuity()`의 `jump_ratio`). 1 근처면 들리지 않는다. 기록된 값은 emotion 0.59, story 0.38, `mus_pause_alt` 0.51이다. 6 kHz 위 고역이 이음매에서 튀는지도 따로 보고, 다른 마디의 첫 박과 같은 크기면 클릭이 아니라 타격음으로 판정했다.
- **[사실]** 곡 안의 느린 변조(숨, 와우)는 루프 한 바퀴에 **정수 번** 돌게 맞췄다. `mus_pause`의 숨 `sine(0.1)`은 80 s에 8번이다.

### 1.4 마스터링

| 항목 | 값 [사실] |
|---|---|
| 형식 | 48 kHz, 16-bit, 스테레오 WAV. 화장실 층 `mus_room_*`만 24 kHz로 저장 |
| 후보곡(lab) 음량 | -28.00 LUFS(적분), 피크 -5 ~ -14 dBFS |
| 게임 곡 음량 | `mus_title` -23, `mus_keybind` -25, `mus_vent` -27, `mus_pause`·`mus_pause_alt`·`mus_mirror`·`mus_room_*` -28 LUFS |
| 트루피크 | ≤ -1 dBFS. 넘으면 그만큼 내린다(`master()`). 4배 오버샘플로 잰다 |
| 로파이(게임 곡) | 샘플앤홀드로 옛 샘플레이트 흉내 + 비트 줄이기 + TPDF 디더. `mus_pause_alt` 22050 Hz / 14 bit, `mus_vent` 16000 / 10 |
| 와우(테이프 흔들림) | 읽기 지연을 루프당 정수 주기로 흔든다. `mus_pause_alt`는 깊이 2.2 ms, 1·4 주기 |
| 결정성 | 고정 시드. 두 번 빌드해 해시가 같은지 확인 |

```python
# tools/build_music.py
NKIDO_TRACKS = {  # (bpm, loop s, fold s, wow)
    "mus_pause_alt": (66.0, 96 / 1.1, 0.5, (0.0022, [1, 4], [0.0, 0.0])),
    ...
}
LOFI = {"mus_pause_alt": (22050, 14), ...}
```

- **[사실]** LUFS는 BS.1770 K-가중 필터 계수를 build.py에 직접 넣어 잰다(400 ms 창, 100 ms 간격, -70 절대 + -10 상대 게이트).
- **[사실]** 게임 안에서는 음악 버스로 나가고, 살 속 곡은 버스에서 핵·맨틀 -6 dB, 겉껍질 -3 dB를 더 내린다. 곡이 오르면 몸 배경을 6 dB 내린다(`docs/design/sound-music.md`).

### 1.5 다시 만드는 명령

```
python -X utf8 tools/build_music.py mus_pause_alt          # 게임 곡(패치: game/tools/audio/patches/)
py -3 game/tools/audio/lab/emotion/build.py                # 후보곡 하나(렌더 + 접기 + 측정 + 스펙트로그램)
python -X utf8 tools/build_flesh_music.py                  # 살 속 3곡(lab 폴더를 build/로 복사해 렌더)
python -X utf8 tools/render_loop_patches.py amb_heart_a    # 배경 루프(build_audio.py와 같은 사슬, manifest는 안 건드림)
```

---

## 2. 아이디어를 어떻게 냈나

### 2.1 첫 판: 실패한 방식

- **[사실]** 2026-11-03 사용자: "관련 툴로 배경음악도 여럿 만들어줘". 작업자 하나에게 "4~6곡, 모두 엔딩 노래 선율(MELODY/HARMONY)에서 파생, 변주·조각·재화성, 음 어긋난 오르골·허밍·오르간, 느리고 불안하게 다정한 PS1 로파이"를 지시했다. 결과로 `mus_title`, `mus_restroom`, `mus_vent`, `mus_pause`, `mus_keybind`가 나왔고, numpy로 손수 합성했다(`tools/build_music.py`의 옛 부분, `mus_title`은 지금도 numpy다).
- **[사실]** CLAP은 다섯 곡 모두 의도 문구를 1위로 맞췄다. 사람의 판정은 반대였다. 11-04 사용자: "필요한 곳마다 서로 다른 느낌으로 더 만들어줘. mus_pause는 특히 안어울려." 오케스트레이터의 진단은 "다섯 곡이 모두 엔딩 노래의 선율에서 나오고 음색이 비슷하게 낡아서 닮았다"였다.
- **[추론]** 같은 재료에서 변주를 뽑으라는 지시가 단조로움을 만들었다. CLAP이 "의도대로 들린다"고 한 것은 품질 보증이 아니었다.

### 2.2 `mus_pause_alt`의 지시문

- **[사실]** 11-04 07:51 작업자 하나(`agent-ae66b0f98b1fa57dc`, Opus 5.5)에게 배경음악 재작업을 맡겼다. Esc 부분은 다음과 같다.

> Replace mus_pause. Esc is closing your eyes: red light through lids, heartbeat, a rest from the horror while the player reads a menu. The closed-lip hum with blood rush doesn't suit it. Make it calm and warm, sparse, unobtrusive under menu reading, clearly unlike the other tracks. Make 2 candidates, install the one you judge best as mus_pause and keep the other as mus_pause_alt …

  곳마다 "tempo, mode, instrument and texture"를 달리하라고 했고, 엔딩 노래는 "loosely or as a mere interval"로만 써도 된다고 풀어 줬다.
- **[사실]** 08:01 사용자: "파이썬으로? tinproject에서 따온 음악 툴 말한거 맞지?" 오케스트레이터는 곧바로 이 작업자에게 "새 곡과 교체 곡은 nkido로 렌더한다"는 메시지를 보냈다.
- **[사실]** 작업자는 `mus_pause_alt.akkado`를 **한 번 써서(Write 1회)** 끝냈다. 두 후보 가운데 CLAP 점수가 높은 현악 패드를 `mus_pause`로 깔고, 펠트 피아노를 `mus_pause_alt`로 manifest에만 남겼다. 작업 시간은 07:51~08:59였고, 그동안 다른 곡 5개도 함께 만들었다.
- **[사실]** 11-07 사용자는 두 Esc 곡이 "둘 다 좋아. 둘 다 넣고싶어"라고 했다. 그래서 눈을 감은 곳으로 고르는 규칙이 생겼다. 화장실 안은 `mus_pause_alt`(방 크기에 맞는 가까운 피아노), 살 속은 `mus_pause`(어택 없는 피난처)다.

### 2.3 후보 6곡의 지시문 (가장 중요한 부분)

- **[사실]** 11-04 07:59 사용자: "게임에 어울릴 아무 음악이나 더 만들면 좋겠어. 게임의 감정만 추출해서 주제로 주기, 게임의 아트스타일만 추출해서 주제로 주기 등 다양한 시도를 해줘. 기존음악을 모르는 서브에이전트가 하자"
- **[사실]** 오케스트레이터는 작업자 6개를 동시에 띄웠다. 모두 general-purpose, 모델 `claude-opus-5-5`이고, 각자 주제 **하나**만 받았다. 지시문은 주제 문단만 다르고 나머지는 같다.

| 후보 | 주제 문단(요약, 원문 영어) | 결과 |
|---|---|---|
| emotion | **감정만**: disgust slowly turning into appetite. Being comforted by something that should horrify you. A tenderness toward your own body as it stops being yours. Small shame, then relief, then wanting more. Not scary-loud; intimate and a little sweet in the wrong way. | 3/4 자장가, 사용자 최애 |
| artstyle | **아트 스타일만**: 90년대 말 로우폴리, 원근 보정 없는 텍스처의 출렁임, 격자에 붙는 꼭짓점, 디더, 흰 타일·회색 줄눈·젖은 분홍·검붉음·이빨색 상아, "cheap shiny" | 좋음, 그러나 신나고 전자적 |
| materials | **재료만**: 도자기, 타일, 똑똑 떨어지는 수도꼭지, 파이프, 이빨, 젖은 고기, 콧숨. 관습적 악기 금지, 각 재료를 모델링해서 리듬과 음정을 연주 | 좋음 |
| cycle | **놀이 반복 구조만**: 뜯기·씹기·삼키기·게우기의 순환, 바퀴마다 조금 더 길고 낯설게, "Driving rather than ambient" | 좋음 |
| story | **이야기만**: 작은 밝은 방이 거대한 생물의 한가운데, 바깥으로 층층이, 창살 뒤에서 너무 친절하게 듣는 무언가 | 언급 없음 |
| contrast | **의도된 모순만**: 싸구려 가게 대기음악처럼 밝고 귀여운데 이름 붙일 수 없게 어긋남. 호러 상투(음 어긋난 자장가, 불협화 찌르기) 금지, 어긋남은 구조로 | 트레일러용 |

  공통 규칙은 다음과 같았다(원문 요지).
  - **클린룸**: 저장소·노트 폴더의 다른 파일, 오디오, 다른 음악을 읽지 않는다. "Your ignorance of what exists is the point."
  - 가사·말 금지. 기존 곡·작곡가·게임을 흉내 내지 않는다.
  - WAV 48 kHz/16-bit/스테레오, 60~120 s, 꼬리가 감기는 이음매 없는 루프, 피크 ≤ -1 dBFS, 약 -28 LUFS.
  - "You can't hear, so check by measurement": 대역별 스펙트럼, 시간에 따른 레벨, 이음매 클릭, 스펙트로그램 PNG를 **직접 보고** 앨리어싱, 노트북 스피커에서 안 들리는 저역만의 내용, 단조로움을 고친다.
  - **"It must have real musical interest: a shape over time, not a texture alone."**
  - 마지막 보고는 2~3문장으로, 어떤 소리이고 무엇을 골랐는지 쉬운 말로.
- **[사실]** 처음에는 "numpy, scipy로 처음부터 합성"이라고 썼다. 2분 뒤 사용자 지적을 받고 6개 작업자 모두에게 SendMessage로 도구를 바꿨다(아래 원문). KNOWHOW와 nkido docs만 클린룸 예외로 읽게 했다.

> Tool change: render with nkido, not hand-written numpy synthesis. Keep your theme and every other rule. … Learn the language from C:\projects\_tools\nkido\docs and …\KNOWHOW.md (traps: filters duplicate mono, so widen once at the end in out(); a constant cutoff folds away; saw() is zero-mean; euclid() in a multiplication renders near silence). … Python stays allowed only for post-processing and measuring … If you already made a numpy version, discard it.

- **[사실]** 소요 시간(첫 기록 ~ 마지막 기록): emotion 25분, artstyle 19분, materials 24분, cycle 26분, story 34분, contrast 24분. 렌더 횟수: emotion 13(probe 포함), materials 14, cycle 12, artstyle 7, story 7, contrast 5.
- **[사실]** `lab_emotion`의 작업 흐름: nkido 문서 7개를 읽고(08:04) → probe 패치를 8초씩 렌더해 음색과 처짐을 확인 → `emotion.akkado`를 **한 번 Write** → build.py로 렌더·측정 → 스펙트로그램 PNG를 네 번 봄 → `sed`로 이름 충돌 세 군데 수정(`bend`→`droop`, `len`→`ntime`, `ramp`→`sweep`) → 완료(08:24). 사람 청취에 따른 수정은 없다.

### 2.4 그 뒤의 곡들

- **[사실]** 화장실 음악(11-07, round5-music): 사용자가 "변기 바라본다고 음악이 달라지는건 이상함 … npc 대사처럼 동적이고 가변적이고 여러 상황을 대응하는 배경음악"을 요구했다. 결과는 같은 템포·조·길이(Bb 프리지안, 54 bpm, 72박 = 80 s)의 nkido 층 8개 `mus_room_*`다. `AudioStreamSynchronized` 하나에서 함께 돌고, 게임 상태(`game/audio/room_music.json`)에 따라 음량만 움직인다. 오름은 초당 1/8, 내림은 초당 1/12이고, 시선은 판정에 쓰지 않는다.
- **[사실]** 살 속 음악(11-07, round6): 사용자가 "살 팔때도 음악 들리기"라고 했다. 좋아한 후보 셋을 껍질마다 하나씩 넣었다(핵 emotion, 맨틀 materials, 겉껍질 cycle). 곡은 한 바퀴 돌고 75 s 쉰다. 껍질이 바뀌면 다음 프레이즈 표시에서 3 s 크로스페이드한다.
- **[사실]** `lab_artstyle_organic`(11-07, round6-artstyle): 피드백 "유기물의 느낌보다는"에 대한 새 판이다. 벨 주제와 반음 붕괴는 유지하고 북·아르페지오 격자·전자 리드를 뺐다. 도자기 사발 벨, 펠트 피아노(`mus_pause_alt`의 felt 음색을 그대로 옮김), 활 첼로·분홍 리드, 콧숨, 물방울로 바꿨다. 사람이 아직 듣지 않았다.

---

## 3. 좋아한 두 곡의 작곡 기법

### 3.1 `lab_emotion` (`game/tools/audio/lab/emotion/emotion.akkado`)

**형식 [사실]** 3/4, 72 bpm, 40마디 = 100 s. 패치 머리말을 그대로 옮긴다.

```
//  A  bars  0-7   sour. Harmony sinks F E Eb Db, notes sag flat, ticks fall anywhere.
//  B  bars  8-15  shame. A shy lullaby in Db; ticks start finding the beat.
//  C  bars 16-25  relief. The tune whole; the sag now slides UP into the note.
//  D  bars 26-33  sweet. Same tune higher, in thirds, too much sugar; ticks are a melody.
//  E  bars 34-39  more. Hungry grabs climbing to F; F major's third sags over the seam.
```

구간 레벨은 A -36.6 → B -34.7 → C -31.2 → D -27.8 → E -28.5 dB로, 곡 전체가 한 번 부풀었다가 돌아온다.

**핵심 장치: 마디 단위 제어 곡선 [사실]** 40개 값짜리 곡선 다섯 개가 곡의 "감정"을 운반한다.

```
s  = glide(v"1 1 1 1 1 1 .85 .75  .55 .5 .4 … 0 0 …  0 .1 .2 .35 .55 .8", 1.5)   // 어긋남(sour)
sw = glide(v"0 0 … .05 .1 … 1 1 1 … .9 .6 .4 .2", 1.5)                            // 단맛(sweet)
wetn = glide(v"1 1 … .1 .1 .05 0 … .2 .4 .7 .9", 1.5)                              // 젖은 정도
```

- `s`(sour)는 detune 양(`twin = f * (1 + 0.0105 * s)`, 건반 `d = 0.0006 + 0.0042 * s`, 패드 `pdet = 0.003 + 0.0095 * s`)과 비브라토 깊이를 정한다. 처음에는 음이 맥놀이를 내며 어긋나 있다가 C에서 0이 되며 **음정으로 잠긴다**. E에서 다시 오르고, 이음매를 넘어 처음의 시큼함으로 돌아간다.
- `sw`(sweet)는 리드의 톱니 섞임과 필터 밝기(`lp(@, f * (1.9 + 3.2 * sw) + 260)`)를 올린다. 단맛이 음색의 밝기로 들리게 했다.
- 작업자 보고: "기계 소리와 작곡을 나누기보다 '맥놀이가 음정으로 잠기는 과정' 하나를 곡의 형식으로 삼았습니다."

**음정 처짐과 올려 미끄러짐 [사실]** 리드 음마다 `{sag:x}`(끝이 아래로 처짐)와 `{pre:1}`(아래에서 올라와 잡힘)을 붙였다.

```
droop = pow(sweep, 2.5) * 1.5 * sag            // 음이 길어질수록 가속하며 처진다
lift  = (1 - adsr(gate, 0.2, 0.01, 1, 0.2)) * pre   // 0.2 s 동안 아래에서 올라온다
shake = sine(4.7) * (0.09 + 0.17 * s) * adsr(gate, 0.4, 0.1, 1, 0.3)  // 늦게 피는 비브라토
f = freq * pow(2, (shake - droop - lift) / 12)
```

A에서는 `sag`로 음이 가라앉고, C부터는 `pre`로 음이 아래에서 위로 미끄러져 들어온다. 사용자가 말한 "wrong notes sliding into too-sweet"이 이것이다.

**화성 [사실]** A는 F-E-Eb-Db로 반음씩 가라앉는 베이스와 Ab/C 위의 Gb·F·E·Eb이다. B·C는 Db장조 자장가다. D는 같은 선율을 높이 3도 화음으로(`under` 성부가 3도 아래를 같이 부름) 반복하고 Eb/Bb 쪽으로 올라간다. E는 Ab·B·E(이명동음의 E장조 색)를 거쳐 F장조(A·C·F)로 기어오르고, 마지막 A가 이음매에서 Ab으로 처져 첫 화음으로 돌아간다.

**악기 [사실]**
- 리드: `sine + saw*(0.28+0.34*sw) + 2배음`, 160 Hz 하이패스. 사람 목소리 같은 덩어리다.
- 건반(오르골·첼레스타 계열): 사인 두 개를 ±d로 벌려 맥놀이를 만들고, 2·3·4배음을 짧은 엔벨로프로 둔다. 배음 비율도 `2 + 0.018*s`, `3 + 0.07*s`로 어긋남에 따라 비조화가 된다.
- 베이스: 사인 1~6배음. 노트북 스피커에서 들리도록 배음을 쌓았다(80 Hz 미만은 약 -20 dB).
- 심장(`heart_v`): 62 Hz에서 46 Hz만큼 내려오는 짧은 피치 스윕과 배음. B에서 들어와 D·E에서 빨라진다.
- 틱(`tick_v`): 젖은 똑똑 소리. A에서는 박 밖 아무 데나 떨어지고(`[~@.7 a5@.2 ~@2.1]`) B에서 박을 찾으며 D에서는 선율이 된다. 젖은 정도(`wetn`)에 따라 길이가 바뀐다.
- 꿀꺽(`gulp_v`): 150→450 Hz 스윕. 구간 끝마다 한 번씩만 넣었다.
- 숨: 시드가 다른 노이즈 두 개를 340~1500 Hz로 걸러 좌우에 따로 두고, 느린 사인으로 부풀린다.

**공간과 스테레오 [사실]** 패드에 11 ms Haas 지연, `dattorro` 리버브를 썼다. 리버브 보냄은 `0.2 + 0.5 * wd`로 곡이 진행할수록 커진다. 좌우 폭은 마지막에만 만든다(`fn pair(l, r) -> stereo(mono(l), mono(r))`). 최종 L/R 상관은 0.91이다.

### 3.2 `mus_pause_alt` (`game/tools/audio/patches/mus_pause_alt.akkado`, 39줄 전체)

**설계 [사실]** "a felted piano in a small warm room, a chord, then one or two high notes seconds apart over a held warmth, and a faint heart. Everything sits in the warm mids: low notes and sub read as dread, whatever the key." Db장조(게임 노래의 조를 반음 내림), 66 bpm(Esc 눈꺼풀 셰이더의 심장 1.1박/초에 맞춤), 96박 = 87 s.

**펠트 피아노 음색 [사실]** 패치 전체가 짧아 핵심을 그대로 옮긴다.

```
felt = ({freq, gate, vel}) -> {
    body = (sine(freq * 0.9993) + sine(freq * 1.0007)) * 0.5 * ar(gate, 0.024, 7.0)
    second = sine(freq * 2.002) * 0.3 * ar(gate, 0.024, 3.5)
    third = sine(freq * 3.006) * 0.08 * ar(gate, 0.03, 1.6)
    (body + second + third) * vel
}
```

- 줄 두 개를 ±0.07% 어긋나게 해서 느린 맥놀이를 만든다(실제 피아노의 두 줄 합창).
- 해머가 24 ms로 느리다. 펠트라서 딱 소리가 없다.
- 배음이 셋뿐이고 위로 갈수록 짧다(7 s / 3.5 s / 1.6 s). 배음도 조금씩 늘어나 있어(2.002, 3.006) 쇠줄의 비조화성을 낸다.
- 출력 단에 `lp(@, 2200)`, `freeverb`(방 0.7), `hp(@, 90)`. 저역과 고역을 다 깎아 "따뜻한 중역"만 남긴다.

**편곡 [사실]**
- 왼손: 12박마다 낮은 화음 하나(`[db3,ab3,f4] ~!11 …`). Db-Gb-Ab-F(m)-Db-Gb-Ab-Db.
- 오른손: 게임 노래의 윤곽 F Ab Bb Ab F Eb Db를 처음 48박 동안 **몇 초 간격으로 한 음씩** 낸다(`~!4 f5 ~!2 ab5 ~!7 bb5 …`). 뒤 48박에는 그 조각만 낸다.
- 온기: 같은 화음을 삼각파 두 개(±0.15%)로 길게 깔고 1 kHz 로우패스, 음량 0.05. "hardly there".
- 심장: 58 Hz 짧은 사인과 0.27 s 뒤 메아리(lub-dub), 30~170 Hz, 음량 0.05. 주석: "Keep it this low: at twice the level the CLAP ear heard this as scary (0.30 to 0.47)".
- 후처리: 와우 2.2 ms, 22050 Hz / 14 bit 로파이, -28 LUFS.

**[추론]** 이 곡이 좋게 들리는 이유는 음이 적기 때문이다. 화음 하나 뒤에 몇 초 동안 잔향만 남고, 그 사이로 선율 음이 하나씩 떨어진다. 사람이 친 듯한 느낌은 타이밍을 흔들어서가 아니라(이 패치에는 타이밍·세기 흔들림이 없다) 맥놀이, 느린 해머, 짧아지는 배음, 테이프 와우, 넓은 간격에서 나온다.

### 3.3 두 곡의 공통점 [추론]

| 요소 | `lab_emotion` | `mus_pause_alt` |
|---|---|---|
| 박자·빠르기 | 3/4, 72 bpm | 66 bpm, 12박마다 화음, 선율 음 간격 수 초라 박이 거의 안 느껴짐 |
| 조 | Db장조 중심, A에서 반음 하강, 끝에 F장조 | Db장조 |
| 길이 | 100 s, 형식 있는 루프 | 87 s, 앞 절반 선율 / 뒤 절반 조각 |
| 따뜻함 | 리드·건반 모두 사인 중심, 고역은 필터로 제한 | 사인 3배음, 2.2 kHz 로우패스 |
| 사람 손 | 음마다 처짐·올림 인자, 늦게 피는 비브라토 | 두 줄 맥놀이, 느린 해머, 와우 |
| 몸 | 심장, 꿀꺽, 숨, 젖은 틱 | 아주 희미한 심장 |
| 저역 | 배음으로 들리게, 서브 억제 | 90 Hz 하이패스 |
| 변화 | 곡 전체가 하나의 과정(어긋남 → 맞음 → 과함) | 정지에 가까움 |

- 둘 다 **Db장조**이고 **중역 중심**이며, 몸의 소리(심장)를 "느껴지는 정도"로만 둔다.
- 둘 다 게임의 공포를 직접 그리지 않는다. emotion은 "역겨움이 식욕으로 미끄러진다"는 **역설적 감정**을, pause_alt는 **쉼**을 그린다.

### 3.4 덜 좋았던 곡과의 차이 [사실 + 추론]

- **[사실]** `lab_artstyle`은 32단 웨이브테이블을 `floor(y * 12) / 12`로 계단화하고 30 fps로 끊은 음색 변화(`frame = phasor(30) < 0.02`)를 썼다. 킥 드럼과 그리드 위의 아르페지오도 있었다. 사용자: "신나서 … 전자적 … 유기물의 느낌보다는".
- **[추론]** 시각 스타일(PS1의 끊김·계단)을 소리로 직역하면 칩튠·전자 음색이 된다. 이 게임에서 "유기물"은 사인 중심 음색, 느린 엔벨로프, 맥놀이, 음정 처짐에서 나왔다.

---

## 4. 평가 고리

### 4.1 측정 (작업자가 들을 수 없으므로)

**[사실]** 모든 곡에서 확인한 항목은 다음과 같다.

| 확인 | 방법 | 예시 값 |
|---|---|---|
| 음량 | 적분 LUFS, 4배 오버샘플 트루피크 | -28.00 LUFS, TP ≤ -1 |
| 구간 형태 | 구간·5초별 레벨 | emotion A -36.6 … D -27.8 |
| 대역 | 20-80/80-200/200-800/800-3k/3-8k/8-16k/16k+ 비중 | 200-800 Hz 중심, 80 Hz 미만 -20 dB |
| 층 생존 | `--stems` 버스별 레벨 대 믹스 | 틱 약 -20, 숨 약 -26 dB, 죽은 층 없음 |
| 이음매 | `jump_ratio`, 6 kHz 위 이음매 에너지 대 주변 | 0.59 |
| 앨리어싱 | 스펙트로그램에서 거꾸로 움직이는 선 | 없음 |
| 음정 | 자기상관으로 음 높이 추적 | contrast 리드 216음 중 214 통과 |
| 결정성 | 두 번 빌드한 WAV 해시 | 같음 |
| 스테레오 | L/R 상관 | 0.68~0.93 |

- **[사실]** 스펙트로그램은 matplotlib이 없어서 build.py가 numpy와 zlib으로 PNG를 직접 쓴다. 구간 경계선과 레벨 곡선을 함께 그리고, 작업자가 이미지를 **직접 열어 본다**(emotion 4회).
- **[사실]** probe 렌더: 8초짜리 짧은 패치를 렌더해 250 ms 단위 레벨, 좌우 상관, DC를 찍어 음색 함수가 의도대로 움직이는지 먼저 확인했다.

### 4.2 CLAP 판별 모델 ("귀")

- **[사실]** venv `C:\fpear`, 모델 `laion/clap-htsat-unfused`. 첫 판에는 `MIT/ast-finetuned-audioset-10-10-0.4593`(AudioSet 분류)도 함께 썼다. 실행 예: `C:/fpear/Scripts/python.exe -B -X utf8 clap_compare.py <music-lab dir> <pause_alt wav> [out.json]`.
- **[사실]** 방법: 곡을 10초 창 8개로 자르고 창별 임베딩을 평균한다. 프롬프트 집합과의 코사인 또는 softmax 점수를 구한다. 프롬프트는 "의도 문구 + 헷갈릴 만한 일반 문구 12개"(a music box lullaby, closed lip humming, a horror movie drone, an ice cream truck jingle, elevator music, a grand piano …)로 짜고, 의도 문구의 순위를 본다. 곡끼리의 임베딩 코사인으로 "서로 닮았나"도 본다.
- **[사실]** 쓴 곳과 결과:
  - 첫 5곡: 모두 의도 1위. 그런데 사용자는 닮았다고 퇴짜를 놓았다.
  - 재작업: 재생 곡끼리 최대 코사인 0.91 → 0.74. `mus_mirror`의 비브라폰을 CLAP이 오르골로 들어 신스로 바꿨다. Esc 심장을 키우자 "scary"가 0.25 → 0.53으로 올라 뺐다.
  - Esc 두 후보: 패드 gentle 0.60 / scary 0.25, 피아노 0.50 / 0.30. **CLAP 기준으로 패드를 깔았다.** 사용자는 피아노를 최애로 꼽았다.
  - organic 재작업: electronic 0.361 → 0.71로 오히려 올랐다. 그러나 사용자가 사랑한 곡도 electronic이 높다(`lab_emotion` 0.546, **`mus_pause_alt` 0.889**). 좋아한 곡과의 임베딩 유사도는 올랐다(pause_alt 0.54 → 0.729).
  - 엔딩 노래: 허밍과 오르골 틴을 겹치자 "siren"으로 판정됐다. 틴을 빼고 허밍과 둘째 목소리만 두자 1위로 돌아왔다.
- **[사실 → 해석]** CLAP이 할 수 있는 것과 없는 것:

| 쓸 만함 | 못 믿음 |
|---|---|
| 곡끼리 닮았는지(임베딩 코사인) | "좋은가", "아름다운가" |
| 큰 오판 잡기: 사이렌, 오르골 혼동, 백색소음 비중, "scary" 급등 | 합성음 전반의 "electronic" 판정. nkido 합성은 다 전자로 잡힌다 |
| 좋아한 곡과의 거리(기준점 임베딩 대비) | 의도 문구 1위 = 성공. 첫 5곡이 반례 |
| 엔진 녹음이 원본과 같은 성격인지 | 두 후보 중 무엇이 나은지. Esc 판정이 반례 |

### 4.3 게임 엔진 녹음 (movie writer)

- **[사실]** Godot movie writer로 실제 게임 장면을 돌리며 오디오를 녹음했다(`game/tests/capture_music.gd`, `capture_room_music.gd`, `capture_flesh_music.gd`, `capture_song_layers.gd`). 녹음으로 다음을 확인한다: 곡이 그 자리에서 실제로 나는지(원본과의 상관: 핵 0.37, 맨틀 0.22, 겉껍질 0.50, 곡 넣기 전 0.04~0.09), 섞인 음량(LUFS), 바뀌는 순간의 100 ms 최대 변화(3.9~5.1 dB), 효과음이 곡 위로 읽히는지(자기 대역 여유 dB, `tools/measure_beds.py`).
- **[사실]** 녹음으로만 찾은 결함: `mus_room_cold` 앞 약 16초가 무음이었다(아래 5장). 게임 기본 설정에서 층이 지시값의 0.64배로 나왔다(master·music 슬라이더 0.8이 곱해짐).

### 4.4 사람 청취

- **[사실]** 사람 귀로 들은 사람은 사용자 혼자다. 모아 듣기 페이지를 통해 들었다: `build/sound_gallery.html`(`py -3 -B tools/build_sound_gallery.py`, file://로 바로 재생, "후보곡" 묶음 포함), `build/music_lab.html`(후보 7곡).
- **[사실]** 피드백과 바뀐 것:

| 날짜 | 사용자 | 바뀐 것 |
|---|---|---|
| 11-04 | "필요한 곳마다 서로 다른 느낌으로 … mus_pause는 특히 안어울려" | 곳마다 악기·빠르기·조를 달리한 재작업, Esc 후보 2개 |
| 11-04 | "파이썬으로? tinproject에서 따온 음악 툴 말한거 맞지?" | 전 작업자 nkido로 전환, numpy 판 폐기 |
| 11-04 | "감정만 추출해서 … 기존음악을 모르는 서브에이전트가 하자" | 클린룸 후보 6곡 |
| 11-07 | Esc 두 곡 "둘 다 좋아. 둘 다 넣고싶어" | 눈 감은 곳으로 고르는 규칙 |
| 11-07 | "초반 4개 좋아 … 6은 트레일러 … artstyle 신나고 전자적" | 기준점 기록, organic 판 제작 |
| 11-07 | "mus_pause_alt, lab_emotion … 유튜브에 바로 올리고 싶을 정도" | 두 곡을 새 곡의 기준점으로(`docs/design/decisions-log.md`) |
| 11-07 | "살 팔때도 음악 들리기" | 좋아한 후보 3곡을 껍질별로 배치 |
| 11-08 | "발소리 등 … 아케이드같아졌음" | 효과음 재작업(음악 아님, 6장 참고) |

- **[사실]** 보고 규칙: 작업자는 "들어 보지 못했고 측정과 스펙트로그램으로만 확인했다"고 매번 밝혔다. `docs/design/sound-music.md`에도 "수치, 스펙트로그램, 판별 모델의 판정은 사람이 들어 본 것이 아니다"라고 적혀 있다.

---

## 5. 실패와 해결

| 실패 | 원인 | 해결 [사실] |
|---|---|---|
| numpy 손수 합성 | 사용자가 "TIN에서 가져온 음악 툴"을 뜻했음 | 모든 곡을 nkido 패치로. Python은 접기·믹스·측정만. `mus_title`은 옛 numpy로 남음 |
| 첫 배경음악 5곡이 서로 닮음 | 전부 엔딩 노래 선율의 변주, 비슷한 낡은 음색 | 곳마다 빠르기·조·악기·질감을 다르게. CLAP 곡간 코사인 0.91 → 0.74 |
| 옛 `mus_pause`(입 다문 허밍 + 피 흐름) 안 어울림 | Esc는 쉼인데 몸의 공포를 그렸음 | 따뜻하고 성긴 곡 2개, 중역 위주. "low notes and sub read as dread, whatever the key" |
| 엔딩에서 허밍과 틴이 "사이렌" | 미끄러지는 허밍 위에 틴이 겹침 | 엔딩에서는 틴을 빼고 허밍이 선율을 맡음 |
| `mus_room_cold` 앞 약 16 s 무음, 죽고 돌아온 뒤 음악이 안 들림 | 패치의 긴 `_` 이음이 끊김 | 긴 화음을 12박마다 다시 치게 고침. 재녹음으로 확인 |
| eb5가 계속 울림(emotion) | 빈 마디로 넘치는 `{dur:x}` 음은 게이트가 안 내려감 | 긴 선율을 `[...]/40` 그룹 하나로 쓰고 `@` 가중치로 박을 줌 |
| L과 R이 똑같이 나옴 | `poly()`나 필터 출력을 `bus(n, l, r)`에 넣으면 복제 모노가 됨 | `stereo(mono(l), mono(r))`로 마지막에 한 번 묶음 |
| 패치가 안 돌아감 | `bend`, `len`, `ramp`, `wt`, `rev` 같은 이름이 예약됨. 지역 변수도 패치 전체에서 겹치면 안 됨 | 이름 바꿈(`droop`, `ntime`, `sweep`) |
| `ar()`가 타이머로 안 맞음 | 어택이 선형이 아니고 최고치가 약 0.67 | 음정 처짐에 `phasor` 사용 |
| `e.trig`가 16사이클마다 트리거를 잃음(킥 250타 중 37타 누락) | nkido 동작 | 값 패턴 `[v 0]` 펄스를 `gateup()`과 `sah()`로 읽음 |
| 한 패치에 전곡을 넣자 킥 말고 무음 | 버퍼 한도 256 초과 추정, arena 소진으로 `delay`가 드라이 통과 | 성부별 6개 패치로 분리 |
| 필터 출력을 곱하면 `[CEDAR BUG]` 경로 무음 | nkido 버그 | `left()`와 좌우 두 인자 클로저로 우회 |
| `tanh`가 필터 뒤 신호를 거부 | 필터 뒤는 스테레오 취급 | `mono()`를 끼움 |
| 버스 스템 클리핑 | 16-bit 렌더 | `--float32` |
| nkido 리버브가 거의 모노(상관 0.94) | 엔진 특성 | 사이드 신호를 2.4배 넓힘 |
| 이 빌드에 `modal`, `drip`, `resonator` 없음 | 버전 | 사인 모드, `ar`, `bp`, 노이즈 임계 펄스로 직접 모델링 |
| 패치가 bpm을 다르게 해석: `[...]/N`의 N이 박 단위로 동작 | nkido 동작 | 곡 전체를 한 패턴(188박)으로 |
| artstyle 전자적 | 계단 웨이브테이블, 30 fps 끊김, 드럼 격자 | 펠트·활·숨·물로 다시. CLAP electronic은 오히려 0.71로 오름(5.2 참고), 사람 판정 대기 |
| CLAP이 최애 곡을 떨어뜨림 | 모델이 "gentle" 문구에 패드를 더 높게 봄 | 두 후보를 다 남겨 사람이 고름 |
| 엔진에서 층이 0.64배로 작음 | 설정 슬라이더 0.8 × 0.8 | 측정 시 기본 설정값을 감안 |
| 화장실 층이 늘 곡 처음부터 시작 | 구현 한계 | 남은 일로 기록(돌아올 때마다 앞 30초를 들음) |

**[사실]** KNOWHOW에 이미 있던 함정: 필터는 모노를 복제하므로 폭은 `out()`에서 한 번만 넓힌다. 상수 컷오프는 접혀 사라진다. `saw()`는 평균 0이다. 곱셈 안의 `euclid()`는 거의 무음으로 렌더된다.

---

## 6. 같은 품질에 닿는 순서 (olmuse4용)

아래는 **[추론]** 이다. 위의 사실에서 재현 가능한 부분만 골라 순서로 묶었다.

### 6.1 준비

1. **도구를 고정한다.** 소리는 nkido(akkado)로만 만든다. Python은 악보 생성, 루프 접기, 레벨, 디더, 측정만 한다. 손으로 짠 numpy 합성을 쓰지 않는다.
2. **문서를 먼저 읽힌다.** 작곡 작업자에게 `KNOWHOW.md`와 nkido `docs`의 문법·미니 노테이션·사용자 함수·곡선(`v"…"`, `glide`)·beats-per-cycle 문서를 읽게 한다. 마디 단위 곡선을 모르면 "시간에 따른 변화"를 패치 안에 쓸 수 없다.
3. **기준점을 들려주지 말고 설명한다.** 클린룸 작업자에게는 기존 곡을 주지 않는다. 기준(따뜻함, 손으로 친 느낌, 어긋남이 맞아 들어가는 단맛)은 말로만 준다. 다만 이 문서 3장의 패치 발췌는 재작업 작업자에게 직접 줘도 된다(organic 판은 felt 음색을 그대로 가져왔다).

### 6.2 지시문

4. **주제를 한 축으로 좁힌다.** "감정만", "재료만", "놀이 반복만", "모순만"처럼 하나만 준다. 같은 곡의 변주를 시키지 않는다. 주제 문단은 이렇게 쓴다: 감정의 **변화**(A가 B로 바뀐다), 몸의 감각, 금지할 상투("Not scary-loud", "no detuned-lullaby shtick").
5. **후보를 여러 개, 병렬로 만든다.** 서로 모르는 작업자 4~6개, Opus급 모델, 작업자당 곡 하나. 이번에는 6개 중 4개가 "좋다", 1개가 "트레일러용"이었다.
6. **규격과 자기 검사를 지시문에 넣는다.** 48 kHz/16-bit/스테레오, 60~120 s, 이음매 없는 루프, -28 LUFS, TP ≤ -1 dBFS, "You can't hear, so check by measurement", 스펙트로그램을 직접 볼 것, 노트북 스피커에서 들리는 대역, **"a shape over time, not a texture alone"**, 결정성.
7. **보고를 짧게 받는다.** "2~3문장: 어떤 소리이고 무엇을 골랐는지". 들어 보지 않았다는 사실을 같이 적게 한다.

### 6.3 작곡 (작업자가 할 일)

8. **곡을 하나의 과정으로 설계한다.** 구간 A~E와 각 구간의 감정, 마디 수, 구간 레벨 목표를 패치 머리말에 먼저 쓴다(`emotion.akkado` 머리말이 본보기).
9. **과정을 음색 변수에 묶는다.** 마디 단위 곡선(`v"…" |> glide`)으로 detune, 비브라토 깊이, 필터 밝기, 리버브 양, 타악의 박자감을 함께 움직인다. "어긋남 → 맞음 → 과함"이 화성과 음색에서 동시에 일어나게 한다.
10. **유기적인 음색 규칙**
    - 사인 중심에 배음은 적게, 위 배음일수록 짧게, 배음비는 조금 늘려서(2.002, 3.006) 쓴다.
    - 두 줄을 ±0.05~0.1% 벌려 느린 맥놀이를 만든다.
    - 어택은 20 ms 이상(펠트), 긴 감쇠를 쓴다.
    - 음마다 처짐과 올림(sag/pre), 늦게 피는 4.5~5.5 Hz 비브라토를 넣는다.
    - 몸의 소리(심장, 숨, 젖은 틱, 꿀꺽)는 "느껴지는 정도"로 둔다.
    - 저역은 배음으로 들리게 하고 서브는 깎는다. 따뜻함은 중역(200~800 Hz)에 둔다.
    - 계단식 웨이브테이블, 프레임 단위 끊김, 그리드 아르페지오, 킥 드럼, 톱니 리드는 "전자적"으로 들린다.
11. **덜어낸다.** 조용한 곡은 화음 하나 뒤에 몇 초를 비우고, 선율 음을 하나씩 떨어뜨린다(`mus_pause_alt`).
12. **probe부터 렌더한다.** 음색 함수 하나를 8초짜리 패치로 렌더해 250 ms 레벨과 음정 움직임을 잰 다음 전곡을 쓴다.
13. **전곡 패치는 한 번에 쓴다.** 좋은 두 곡 모두 Write 1회였다. 그 뒤로는 측정으로 결함만 고친다(이름 충돌, 매달린 음, 무음 층, 앨리어싱, 이음매).
14. **성부를 버스로 나눠 렌더한다**(`bus(n,…)` + `--stems`). 층마다 믹스 대비 레벨을 재서 죽은 층이 없게 한다. 패치가 커지면 성부별 패치로 나눈다.

### 6.4 마무리

15. **루프:** 2~3바퀴 렌더 → 둘째 바퀴 사용 → 첫 0.5~1.5 s를 셋째 바퀴 머리와 등전력 크로스페이드 → `jump_ratio` < 1 확인. 느린 변조는 루프당 정수 주기로.
16. **마스터:** DC 제거 → (게임용이면 로파이와 와우) → 목표 LUFS → TP ≤ -1 dBFS → TPDF 디더 → 16-bit. 두 번 빌드해 해시를 비교한다.
17. **측정표를 남긴다:** 구간 레벨, 대역, 층 레벨, 이음매, L/R 상관, 스펙트로그램 PNG(구간선 포함).

### 6.5 판정

18. **CLAP은 거름망으로만 쓴다.** 사이렌·오르골 혼동·공포 급등 같은 큰 오판과 곡끼리 닮음을 잡는 데 쓴다. 고르는 데는 쓰지 않는다. "electronic" 점수는 nkido 합성 전체에서 높게 나오므로 무시한다. 기준점 곡과의 임베딩 거리는 참고할 수 있다.
19. **후보를 버리지 않는다.** 두 개 이상 만든 곡은 모두 모아 듣기 페이지에 올려 사람이 고르게 한다. CLAP으로 1등만 남겼다면 `mus_pause_alt`는 사라졌다.
20. **사람 말을 기록하고 다음 지시문에 원문으로 넣는다.** "유기물의 느낌보다는", "유튜브에 바로 올리고 싶을 정도" 같은 말을 그대로 옮긴다. 들어 보지 않은 곡은 보고에 "측정만"이라고 쓴다.

### 6.6 지시문 틀 (복사해서 쓰기)

```
You are a composer. Compose one original instrumental piece from the theme below. Reply in Korean.

THEME (<한 축>만; nothing else about the project is yours to know): <감정의 변화 A → B, 몸의 감각,
금지할 상투 한두 개>

Rules:
- Clean room: read nothing but your output folder, C:\projects\_tools\nkido\docs and
  C:\Users\fixme\Desktop\TINProject\tools\nkido_pipeline\KNOWHOW.md. No other music.
- No words, lyrics, or speech. Nothing imitating an existing song, composer or game.
- Sound comes only from nkido: nkido.exe render <patch.akkado> -o out.wav --seconds N --rate 48000
  --bpm B --no-default-bank [--float32 --stems]. Python only writes scores, folds the loop, sets
  level, dithers and measures. Deterministic.
- Output folder: <dir>: .akkado patches, build.py, <name>.wav. No git.
- WAV: 48 kHz, 16-bit, stereo, 60-120 s, seamless loop (render 2-3 passes, keep the second),
  true peak <= -1 dBFS, -28 LUFS.
- You can't hear, so check by measurement: band spectrum, level over time per section, per-stem
  level, seam jump vs p99.9 step, and render a spectrogram PNG and look at it. Fix aliasing,
  sub-only content (it must read on laptop speakers), dead layers, monotony.
- It must have real musical interest: a shape over time, not a texture alone. Write the form
  (sections, bars, what changes) at the top of the patch first, and drive timbre (detune, vibrato,
  brightness, reverb, how on-beat the percussion is) with per-bar curves that follow that form.
- Warm and hand-played, not electronic: sine-based voices with few, short, slightly stretched
  partials, paired strings a hair apart, soft attacks (>= 20 ms), per-note pitch sag/scoop, late
  vibrato; low end through harmonics, not sub. Avoid stepped wavetables, frame-rate stepping,
  grid arpeggios, kick drums and saw leads.
Final message: 2-3 sentences of what it sounds like and what you chose, in plain words, the file
path, and that nobody has listened to it.
```

---

## 부록: 파일 위치

| 무엇 | 경로 |
|---|---|
| 좋아한 곡 패치 | `game/tools/audio/patches/mus_pause_alt.akkado`, `game/tools/audio/lab/emotion/emotion.akkado` |
| 후보곡 패치와 build.py | `game/tools/audio/lab/{emotion,artstyle,artstyle_organic,materials,cycle,story,contrast}/` |
| 후보곡 렌더(git 무시) | `build/music-lab/lab_*.wav`, 페이지 `build/music_lab.html` |
| 게임 곡 빌더 | `tools/build_music.py`(nkido 렌더 `render_nkido`, `master`, `LOFI`, `TARGET_LUFS`) |
| 살 속 곡 빌더 | `tools/build_flesh_music.py` |
| 배경 루프 빌더 | `tools/render_loop_patches.py`, `game/tools/audio/build_audio.py` |
| 측정 함수 | `game/tools/audio/analyze_audio.py`(`integrated_lufs`, `true_peak_dbfs`, `loop_discontinuity`, `masking_margin_db`) |
| CLAP 스크립트 | `game/tools/audio/lab/artstyle_organic/clap_compare.py`, 노트 `orchestra/wire/music2/clap_music.py`, `tools/clap_beds.py` |
| 음악 기준과 배치 | `docs/design/sound-music.md`, `docs/design/decisions-log.md`, `game/audio/SOUND_LIST.md` |
| 작업자 보고 전문 | `C:\Users\fixme\.claude\projects\C--Users-fixme-Desktop-flesh-pit-main\87b46f4f-69ce-404d-9876-677aa5f332a0\subagents\agent-ae66b0f98b1fa57dc-report-*.md`(Esc 2곡 포함 재작업), 같은 폴더 `agent-a83f8ce56bc2afd41.jsonl`(emotion) |
| 증거(측정·CLAP·엔진 녹음) | `side-session-notes\local_34b34be7…\orchestra\wire\music\`, `…\wire\music2\`, `side-session-notes\local_d1bd63dd…\round5\round5-music\`, `…\round6\round6-flesh-music\`, `…\round6\round6-artstyle\` |
