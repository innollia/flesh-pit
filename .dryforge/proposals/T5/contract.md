# T5 제안 계약: 변기·탱크·NPC·문·카나리아 상호작용 및 정산 복구

## 1. 개요 및 복구 배경
- **범위**: R01, R02, R03, R04, R05, R16
- **의존 관계**: T1 (욕조 형상 및 방 경계), T2 (실제 웅크리기 자세), T4 (즉시 털 성장, 정산 털 0 / 이빨만 지급)
- **책임 분리**:
  - T5 전용 구현 모듈: `game/main/scripts/fp_interactions.gd` (신규), `game/main/scripts/fp_tank_lid.gd`, `game/main/scripts/fp_input_modes.gd`, `game/main/scripts/fp_vent.gd`, `game/main/scripts/fp_interact_ring.gd`, `game/main/scripts/fp_hand_actions.gd`.
  - 공유 소유 파일인 `main.gd`, `restroom.gd` 등은 직접 수정하지 않고 본 계약과 `patch.diff`로 제안하여 T9(단일 작성자)가 통합 적용한다.

---

## 2. 규칙별 복구 상세 내용

### R01: 변기 그릇(toilet bowl) F 안내 및 토하기/앉기 상호작용
- **원인 분석**:
  - `toilet_point()`는 `Vector3(0, 0.45, 0.3)`으로 변기 그릇 내부 수면을 가리킨다.
  - 변기 그릇을 조준하면 `interact_ring` 안내가 뜨고, F 누름 시 내용물(위장 살점, 운반 종양, 이미 변기에 들어간 내용물) 여부에 따라 `start_settlement()`(구토 정산 시점) 또는 `sit_down()`(앉기)으로 명확히 분기한다.
- **경계 조건**:
  - 안내(`interact_target()`)와 실행(`_interact()`)이 동일한 후보 좌표(`toilet_point()`), 동일 각도(12.0도), 동일 도달 거리(1.35m)를 사용한다.
  - 변기 그릇(`toilet`), 플러시 레버(`lever`), 물탱크 뚜껑(`tank_lid`), 물탱크 내부 이빨(`tank_teeth`)을 명확한 별도 표적으로 분리한다.

### R02 & R04: 물탱크 뚜껑, 이빨 퍼기, 레버 물내림 및 환풍구 NPC 첫 만남 / 거래
- **뚜껑 조작 (경첩 금지, 완전 분리 loose lid)**:
  - `FPTankLid`는 경첩이 아니며 물탱크, 손(오른손), 바닥 중 하나의 소유자만을 갖는다.
  - 양손 도구 규칙 유지: 오른손에 도구가 들려있지 않고 살점을 들고 있지 않을 때(`can_pick()`) F로 집을 수 있다.
  - 집은 상태(`held == true`)에서 물탱크 위(`is_aiming_tank()`)를 바라보고 F를 누르면 다시 물탱크 위로 덮이고(`replace_on_tank()`), 물탱크가 닫힌다(`main.restroom.set_tank_open(false, true)`). 환풍구에 `lid_close`가 통지된다.
  - 물탱크가 아닌 바닥이나 임의 장소를 바라보고 F를 누르면 레이캐스트 착지 지점 바닥에 평평하게 놓인다(`drop()`). 바닥에 놓인 뚜껑도 F로 다시 집을 수 있다.
- **열린 탱크에서 이빨 퍼기 및 도로 넣기**:
  - 뚜껑이 열려있고(`not tank_lid.on_tank` 또는 `_lid_target != 0.0`), 탱크에 이빨이 있는 경우(`progression.teeth > 0`):
    - 바라볼 때 `tank_teeth` 상호작용 안내가 뜬다.
    - F 누름: 손에 든 이빨이 없으면 한 움큼 퍼기(`scoop_teeth()`), 손에 이미 이빨이 있으면 도로 탱크에 넣기(`put_teeth_back()`).
    - 우클릭 / R / 패드 LT (`_pick()`): 한 움큼씩 연속으로 퍼서 손에 누적(`scoop_handful()` -> 4개씩 누적).
    - 환풍구에 `lid_open`, `grab` 등이 전달되어 대사가 반응한다.
- **레버 물내림 (진짜 flush)**:
  - 플러시 레버(`lever_point()`)를 바라보고 F 또는 RMB/R(`_pick()`) 입력 시 `pull_lever()`가 호출된다.
  - 변기 내용물(`bowl_flesh`, `bowl_tumors`)이 정산되어 이빨이 탱크로 들어가고(`progression.teeth`), 흔들림 효과음(`rattle`)이 발생한다. (T4 계약에 따라 털 획득은 0).
  - 서 있는 상태의 빈 변기 물내림도 정상 동작하며 환풍구 NPC가 물내림 소리를 듣는다.
- **환풍구 NPC 첫 만남 및 거래 복구**:
  - 첫 물내림 시 환풍구의 존재가 즉시 `first.heard` 대사("나 똑똑히 들었다? 거기 누구 있어?")를 발화하고 자막과 음성 신호로 출력된다.
  - 플레이어가 즉시 환풍구를 열지 않으면 `NAG_INTERVAL`(6초)마다 `first.nobody`, `first.hello`, `first.tsk`로 닥달이 이어진다.
  - 환풍구를 열면 `first.open`("좋아... 저기 물통 뚜껑 열어봐. 거기 봉 있지. 봉. 응?") 또는 늦게 열었을 때 `first.open_late`가 출력된다.
  - 토하기 자체에는 새로운 대사를 붙이지 않고 기존 침묵과 BONG(이빨) 세계관 표현을 엄격히 유지한다.
  - 퍼낸 이빨을 환풍구에 올리면(`place_teeth_at_vent()`) 첫 거래에서 작업 벨트(`prog.has_belt = true`)가 지급되고 물건이 제시된다.

### R03: 토한 뒤 다중 일어서기 입력 및 중복 방지
- **자연스러운 일어서기(exit) 다중 입력 지원**:
  - 변기에 구토 중(`_settling == true`):
    - `fp_vomit` (V / 패드 Y)
    - `fdk_move_forward`, `fdk_move_back`, `fdk_move_left`, `fdk_move_right` (W/A/S/D 및 패드 좌측 스틱)
    - `fdk_jump` (Space / 패드 A)
    - `ui_cancel` (Esc / 패드 Start / B)
    - `fdk_eat` (LMB)
    - `fp_interact` (F / 패드 X - 레버를 조준하지 않았을 때)
    - `fp_pick` (RMB / R / 패드 LT - 레버를 조준하지 않았을 때)
    - 키 재설정 액션 및 게임패드 이동/취소 모두 즉시 `leave_settlement()`를 호출하여 자연스럽게 일어선다.
- **동일 진입 press 즉시 탈출 방지 (중복 방지) & Hold 토하기 반복 없음**:
  - `start_settlement()` 진입 프레임(`_settle_entry_frame`)과 진입을 유발한 액션(`_settle_entry_action`)을 기록한다.
  - 진입과 동일한 프레임에서는 탈출 입력을 판정하지 않는다.
  - 진입 시 누르고 있던 키(예: V를 길게 누름)를 떼기 전까지는 탈출로 판정하지 않아, 홀드 중 토하기/일어서기가 진동처럼 반복되지 않는다. 뗀 후 새로 누를 때 탈출한다.
- **레버 조준 시 물내림 우선**:
  - `_settling` 중 카메라/마우스/크로스헤어가 유효하게 플러시 레버(`lever_point()`)를 가리키고 있을 때는, F 또는 `fp_pick`(R/RMB) 입력 시 탈출하지 않고 `flush()`(물내림)를 우선 실행한다.
- **내용물 보존 및 일반 점프 부활 없음**:
  - 레버 물내림이 아닌 모든 탈출 경로는 자동 물내림을 하지 않으며, 변기 그릇 내용물(`bowl_flesh`, `bowl_tumors`)을 그대로 유지한다.
  - Space는 일어서기 입력으로만 소비되며, 일반 점프 기능을 게임 이동에 부활시키지 않는다.

### R05: 세면대 아래 카나리아 구멍 (Undersink Canary Hole)
- **원인 분석**:
  - 세면대 충돌체(`RoomBody` Shape 9: `Vector3(0.60, 0.9, 0.65)`)가 y=0부터 0.9까지 통짜 직육면체로 생성되어 있어, 에이프런 아래 빈 공간(y < 0.34)을 통해 카나리아 구멍(y=0.09)으로 향하는 레이캐스트를 세면대 전체가 차폐(0.6m 거리)로 오판단하고 있었다.
- **정밀 차폐 판정 (FPInteractions.check_aim)**:
  - 1. **시선 높이 판정**: 카메라에서 구멍으로 향하는 광선이 세면대 앞단(`x = -HALF.x + 0.34`)을 통과할 때의 높이가 `FPRestroom.APRON_BOTTOM`(0.34m)보다 높으면, 서 있는 시선으로 세면대 상판/에이프런을 꿰뚫어 보는 것이므로 즉시 차폐(FALSE) 처리한다.
  - 2. **낮은 시점 공간 통과**: 레이캐스트가 `RoomBody` Shape 9(세면대 박스)에 닿았더라도 충돌 위치가 y < 0.34(실제로는 에이프런 아래 개방 공간)라면, 세면대 상판 차폐가 아니므로 통과시키고 2차 레이캐스트로 배후 장애물 유무를 검증한다.
  - 3. **정상 차폐 보존**: 방 밖 벽(Shape 3)이나 별도의 가구/장애물이 가로막고 있으면 엄격히 차폐(FALSE) 처리된다. 세면대 전체나 벽 차폐를 끄지 않는다.
- **결과**:
  - 서 있는 상태에서는 세면대에 가려 발견/조준 불가.
  - T2의 실제 웅크리기(Ctrl) 또는 낮은 시점에서는 에이프런 아래 좁은 공간 사이로 카나리아 구멍이 발견되고 F 안내가 뜸.
  - F를 누르면 `begin_canary_pull()`로 엎드려 꺼내 팬티 허리밴드 안에 꽂는 기존 표현 유지(`has_canary = true`).

### R16: 열린 문 재상호작용 (Actual Door Geometry Interaction)
- **원인 분석**:
  - 기존 `interact_target()` 후보군에 닫힌 문의 고정 좌표 `Vector3(0, 1, FPRestroom.HALF.z)`가 하드코딩되어 있어, 문이 열려 회전한 뒤에도 열린 문짝/손잡이를 겨누면 무시되고 닫혀 있던 허공을 봐야만 닫히는 문제가 발생함.
- **실제 형상 및 손잡이 추적 (FPInteractions.get_candidates)**:
  - 문의 손잡이 노드는 geometry 오프셋이 적용되어 있으므로 `door_pivot.to_global(Vector3(w - 0.095, 0.995, 0.0))`로 실제 회전된 손잡이 월드 좌표를 산출한다.
  - 문짝 중심 역시 `door_pivot.to_global(Vector3(w * 0.5, DOOR_H * 0.5, 0.0))`로 실제 열린 문짝 면을 산출한다.
  - 문이 닫혀 있을 때나 열려 있을 때나 현재 `door_pivot`의 회전각에 따라 실제 문 손잡이와 문짝 면이 후보군으로 등록된다.
- **차폐 및 각도 한계**:
  - 문 자체의 콜라이더(`DoorBody`)에 레이가 닿은 것은 문의 표면에 도달한 것이므로 유효 표적으로 인식한다.
  - 문 앞에 별도의 장애물(테스트의 obstruction 박스 등)이 가로막고 있으면 차폐(FALSE) 처리한다.
  - 30도 원뿔각과 1.6m 거리 제한을 엄격히 준수한다.
  - 닫힌 문 열기 -> 열린 문 닫기 -> 다시 열기 반복이 완벽히 동작한다.

---

## 3. T9 (Main 단일 작성자) 통합 패치 계약

T9 담당자는 `main.gd`에 아래 사항을 연결한다 (`.dryforge/proposals/T5/patch.diff` 참조):

1. **상호작용 표적 후보군 위임**:
   `interact_target()` 내 후보군 배열 생성을 `FPInteractions.get_candidates(self)`로 교체한다.
2. **조준 차폐 검사 위임**:
   `_interaction_aim(point, degrees, reach, target_name = "")`에서 `FPInteractions.check_aim(self, point, target_name)`을 호출한다.
3. **토하기 정산 프레임 가드**:
   `start_settlement()` 시 `_settle_entry_frame = Engine.get_process_frames()`, `_settle_entry_action`을 기록한다.
4. **정산 중 다중 입력 처리**:
   `_process(delta)`의 `if _settling:` 블록에서 `FPInteractions.handle_settling_input(self, _settle_entry_frame, _settle_entry_action)`을 호출한다.
5. **열린 탱크 이빨 퍼기 / 넣기 및 우클릭(RMB) 레버**:
   - `_interact()`의 `"tank_teeth"`에서 손에 이빨이 있으면 `put_teeth_back()`, 없으면 `scoop_teeth()`를 호출한다.
   - `_pick()`에서 레버 조준 시 `pull_lever()`, 열린 탱크 조준 시 `scoop_teeth()`를 호출한다.
