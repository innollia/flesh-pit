
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
