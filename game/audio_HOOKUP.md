
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