# T3 제안 계약: 내려다보기 머리·목 위치 및 몸 정렬, 거울 반사 보행 및 웅크리기 복원

## 1. 개요 및 목적
- **범위**: 규칙 R07, R08
- **의존 관계**: T2 (발 위치 고정 캡슐 웅크리기 `get_feet_position()`, `eye_pivot_y` 연속성, `_bob_time`/`_bob_weight`)
- **책임 분리**:
  - T3 소유 파일:
    - `game/main/scripts/fp_hand_motions.gd`
    - `game/main/scripts/fp_art_hookup.gd`
    - `game/main/art/fp_mirror_body.gd`
    - `game/main/scripts/fp_mirror_reflection.gd`
    - `game/main/art/fp_belt.gd` (기존 완성 상태 보존)
  - 공용 파일(`main.gd`, `restroom.gd`, `fdk_first_person_controller.gd` 등)은 직접 수정하지 않으며, 본 계약과 `patch.diff`로 통합 제안한다.

---

## 2. 규칙별 원인 분석 및 복구 상세

### R07: 내려다볼 때 실제 머리/목 위치 이동, 배 화면 하단 배치, 화면 중앙 몸통 차폐 방지, 상태 간 공간 연속성
- **원인 분석**:
  - 기존에는 카메라 피벗(CameraPivot)을 아래로 회전(`pitch < 0`)할 때 경추 굴곡(cervical flexion)에 따른 실제 머리/목 중심의 전방 및 하방 이동이 반영되지 않았음.
  - 플레이어 몸체(배·벨트)가 시야 중앙에 과도하게 침범하여 내려다보았을 때 발 앞쪽 지면이나 조준점이 가려지는 현상이 발생했음.
  - 지형 충돌 가드(`_guard_terrain_eye`)로 인한 카메라 보정 또는 세이브 복원 시 카메라 위치 변경이 몸체 변환에 잘못 전파되면 순간이동(teleport) 현상이 일어날 위험이 있었음.
- **복구 내용**:
  1. **경추 굴곡 머리/목 변위 (`fp_hand_motions.gd`)**:
     - `_cam_rest_offset()` 구현: 피벗의 하향 각도(`pitch_down`)와 신장 비율(`h_scale = (eye_h) / 1.60`)에 따라 부드러운 곡선(`bow = sin(down_t * PI * 0.5)`)으로 전방(`dz = -0.17 * bow * h_scale`) 및 하방(`dy = -0.08 * bow * h_scale`) 머리/목 변위를 계산.
     - `_apply_cam_rest()`: 평상시(`not busy()`)에 카메라의 로컬 변환을 `_cam_rest_offset()`으로 자연스럽게 유지.
     - `_save_cams()` 및 `_finish()`: 토하기/시계 보기/손 씻기 등의 손동작 애니메이션 진입 및 복귀 시 기준 카메라 위치를 `_cam_rest_offset()`과 연속적으로 합성.
  2. **화면 하단 배/벨트 정렬 및 시야 중앙 확보 (`fp_art_hookup.gd`)**:
     - `_sync_belt_posture(_delta)` 추가: 플레이어의 `get_feet_position()`과 `CameraPivot.position.y`를 기준으로 벨트의 기본 높이(`base_waist_y`) 및 신장 비율(`h_scale`)을 산출.
     - 내려다볼 때 벨트를 약간 뒤쪽(`waist_z = 0.02 + 0.04 * bow * h_scale`) 및 하방으로 보정하고 전방 틸트(`rotation.x = -0.12 * bow`)를 주어, 배와 벨트가 화면 최하단에 안정적으로 걸치고 화면 중앙부는 완전히 비워져 발 앞 지형을 명확히 볼 수 있도록 함.
  3. **상태 간 공간 관계 연속성 (서기 / 웅크리기 / 걷기 / Tab / 구토 / 근접 지형 가드)**:
     - 벨트 및 몸체 변환 산출에 `player.camera.position`(지형 충돌 가드로 변동될 수 있는 값)을 직접 사용하지 않고, 불변 골격 기준인 `player.get_feet_position()`과 `CameraPivot` 높이만을 참조.
     - 지형 벽면/천장 접촉으로 `_guard_terrain_eye()`가 카메라를 밀어내거나 세이브를 복원하더라도 몸체가 튀거나 순간이동하지 않는 완전한 기하학적 격리를 달성.
     - 보행 바운스/스웨이(`_pivot_base_y` 기반 bob)도 부드럽게 0.5~0.6 배율로 추종하여 보행 중 상하 흔들림이 자연스럽게 이어짐.

### R08: 거울 반사 실제 보행 보폭(walk gait) 및 웅크리기/발/눈 자세, 정지 시 복귀, 소지품 유지, 정지 시 전방 손 뻗기 방지
- **원인 분석**:
  - 거울 속 플레이어 몸체(`FPMirrorBody`)가 정적 자세로 렌더링되거나 단순 높이만 변경되어, 실제 플레이어의 웅크리기 신체 압축, 양발 위치, 보행 위상(arm swing, hip sway, pelvic bounce)이 거울에 생동감 있게 반영되지 못했음.
  - 보행 정지 시 이전 보행 스윙 각도가 그대로 남거나 손이 앞으로 불필요하게 뻗어 어색한 자세가 형성되는 문제 방지가 필요했음.
- **복구 내용**:
  1. **실제 신체 웅크리기 압축 (`fp_mirror_body.gd`, `fp_mirror_reflection.gd`)**:
     - `FPMirrorBody.build()` 및 `_part()` 시 각 신체 부위(`legs`, `_belt`, `belly`, `chest`, `arms`, `neck`, `face`, `upper_r/l`, `hand_r/l`)의 기본 로컬 변환을 메타데이터(`base_pos`, `base_rot`, `base_scale`)로 보존.
     - `set_posture(crouch, walk_phase, walk_weight, pitch)`:
       - 웅크리기 비율(`crouch`: 0.0~1.0)에 따라 다리(`legs`)의 `scale.y`를 1.0 -> 0.50으로 압축하고, 벨트/배/가슴/팔/목/얼굴의 높이를 비례적으로 연속 하강.
       - 목과 얼굴에 피치 회전(`pitch * 0.25`, `pitch * 0.65`)을 연동하여 거울 속 캐릭터가 고개를 숙이거나 드는 시선이 거울면에 일치.
  2. **실제 보행 보폭(Actual Walk Gait) 및 부드러운 정지 복귀**:
     - `player`의 `_bob_time`과 `_bob_weight`를 전달받아:
       - 골반 바운스(`bounce = sin(walk_phase) * 0.02 * walk_weight`) 및 좌우 스웨이(`sway = sin(walk_phase * 0.5) * 0.015 * walk_weight`).
       - 벨트 회전(`pelvis_rot = sin(walk_phase * 0.5) * 0.06 * walk_weight`).
       - 양팔의 교차 스윙(`ur.rotation.x = b_ur.x + arm_swing`, `ul.rotation.x = b_ul.x - arm_swing`, 진폭 0.28 rad).
       - 손목 보조 흔들림(진폭 0.10 rad).
     - 보행 정지 시 `walk_weight`가 0으로 수렴함에 따라 모든 스윙과 흔들림이 자동으로 0이 되어, 원래의 자연스러운 기립/웅크림 정지 자세로 부드럽게 복귀.
     - 손이 전방으로 뻗는 인위적 자세를 일절 생성하지 않고 기본 메타 회전(`base_rot`) 축에만 앞뒤 자연 스윙을 가산.
  3. **소지품 및 기존 승인 기준 보존**:
     - 거울 몸체의 벨트 스프레이 캔, 카나리아, 3개 툴 링(`_belt.call("set_hung", ...)`) 및 종양 가방 소지품 표시 유지.
     - B 자세 시계 애니메이션 상수(`WATCH_ARM_BASIS`, `WATCH_WRIST_POS`, `WATCH_RIGHT_POS`, `watch_shoulder_drop = 0.14`, 인형 스케일 0.20) 및 고유 피부색/의복 색상 100% 보존.

---

## 3. Main 호출 순서 및 카메라 합성 계약

### 호출 순서 보장
`main.gd`의 매 프레임 실행 순서는 아래와 같이 구성되어야 한다:
1. `_restore_terrain_eye()`:
   - 직전 프레임 또는 `frame_pre_draw`에서 지형 충돌 방지로 임시 적용되었던 `_terrain_eye_delta`를 카메라의 로컬 위치에서 제거.
2. `hand_motions.check_cancel()` 및 `hand_motions.tick(delta)`:
   - 손동작이 없을 때(`not busy()`): `_apply_cam_rest()`가 호출되어 경추 굴곡 머리/목 오프셋(`_cam_rest_offset()`)을 카메라 로컬 위치로 적용.
   - 손동작 수행 중(`busy()`): 손동작(구토, 시계 등)의 카메라 보간 위치 적용.
3. `_guard_terrain_eye()`:
   - 최종 결정된 카메라 로컬 위치를 기준으로 `terrain.constrain_eye(...)`를 실행하여 실제 살점 지형 내부 침투를 방지.
   - 충돌이 발생한 경우에만 보정 벡터 `_terrain_eye_delta`를 기록하고 `camera.force_update_transform()` 수행.
4. `RenderingServer.frame_pre_draw`:
   - 렌더링 직전 지형 갱신 등으로 인한 추가 침투를 방지하기 위해 `_guard_terrain_eye()`를 2차 안전장치로 호출.

### 세이브 복원 시 카메라 및 신체 안정성 보장
- `main.gd`의 `deserialize(data: Dictionary)`에서 세이브된 플레이어 위치(`player_position`)를 복원할 때, 이전 세션의 지형 보정 잔여 벡터가 오작동하지 않도록 `_terrain_eye_delta = Vector3.ZERO` 및 `_terrain_eye_pose = Vector3.ZERO`를 초기화한다.

---

## 4. Main 통합 제안 패치 (patch.diff)
아래 패치를 `main.gd`에 적용한다:
```diff
--- a/game/main/scripts/main.gd
+++ b/game/main/scripts/main.gd
@@ -2243,6 +2243,8 @@ func deserialize(data: Dictionary) -> void:
 	for t in tumor_nodes:
 		t.visible = not taken_tumor_spots.has(int(t.get_meta("spot")))
 	_tank_teeth_shown = -1
+	_terrain_eye_delta = Vector3.ZERO
+	_terrain_eye_pose = Vector3.ZERO
 	var pos: Array = data.get("player_position", [])
 	if pos.size() == 3:
 		player.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
```
