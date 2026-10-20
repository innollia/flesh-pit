# flesh-pit — 플레이어 안내

스토어 소개 문구: 1인칭 인디 호러 게임. 화장실에서 출발해, 다시 자라는 살을 먹고 파며 바깥으로 나간다.

## 조작 (게임 안 설정 → 키 설정에도 나온다)

| 키 | 하는 일 |
|---|---|
| W A S D | 이동 |
| 마우스 / 방향키 | 시점 |
| Ctrl | 웅크리기 |
| Space | 점프 |
| 마우스 왼쪽 (또는 E) | 왼손 도구 사용 |
| 마우스 오른쪽 (또는 R) | 오른손 도구 사용 |
| F | 상호작용 (레버·문·거울 등) |
| V | 토하기 |
| Q | 들기 |
| G | 방벽 |
| T | 종양 먹기 |
| X / Z | 다음 / 이전 도구 |
| Tab | 변이 (팔뚝 인형) |
| Esc | 메뉴 |

## 이 테스트에서 조작하는 법

게임 창은 직접 만질 수 없다. `play.py`로만 조작한다. 행동 하나가 끝나면 게임이 멈추고 화면을 저장한다. 네가 생각하는 동안 게임 시간은 흐르지 않는다.

```
python play.py look                지금 화면을 다시 본다
python play.py act "W 1.5"         W를 1.5초 누른다
python play.py act "W+Shift 2"     여러 키를 함께 누른다
python play.py act "LMB 2"         마우스 왼쪽을 2초 누르고 있는다 (RMB, MMB)
python play.py act "W+LMB 3"       키와 마우스 버튼을 함께
python play.py act "turn 30 -10"   시점을 오른쪽 30도, 아래 10도 돌린다
python play.py act "W 2 turn 20 0" 걸으면서 돈다
python play.py act "tap F"         키를 한 번 누른다 (tap Esc, tap V ...)
python play.py act "click 480 300" 화면 이미지의 x,y를 왼쪽 클릭 (메뉴용)
python play.py act "wait 3"        3초 동안 아무것도 안 한다
python play.py note "..."          지금 드는 생각을 적는다
```

- 행동 하나는 최대 10초다.
- 행동마다 `screen: session/obs_NNNN.png`가 나온다. 그 이미지를 Read로 열어 본다. 긴 행동이면 중간 화면도 나온다.
- 화면은 960×540이다. click 좌표는 그 이미지 기준이다.
- 소리는 들리지 않는다. 대신 그 행동 동안 난 소리의 이름이 `heard:`에 나온다.
- 화면의 글자 중 일부는 `text on screen:`에 글로도 나온다. 손으로 그린 글자는 이미지에만 있다.
