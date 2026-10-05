# 소비자 계약

## Main 저장 호출

save_to_disk()는 현재 단일 슬롯에 저장하며 성공 여부 bool을 반환한다. 기록·이름 변경 실패는 false다. load_from_disk()는 경로가 없거나 열 수 없거나 읽은 값이 Dictionary가 아니면 false이며, 성공하면 상태와 실제 지형 표시·충돌을 복원한다. 정상 플레이 경로 대신 별도 save_path를 지정해 소비자 검사를 실행한다.

Main의 저장 version은5이고 진행의 내부 version은3이다. 지형 payload는 chunks이며 각 청크의 좌표·밀도·조직·sealed·boost를 복원한다. 단일 슬롯을 다른 저장 형식으로 대체하는 변경은 기존 파일 소비자의 호환성을 함께 검증해야 한다. 설정 version1 JSON과 키 배치 JSON은 이 슬롯 payload가 아니다.

진행 저장과 죽음 드롭은 `migrated_v5_hairs` 표식으로 구형 털 이전의 중복 적용을 막는다. 표식 없는 구형 `pending_hairs` 값은 이미 껍질 배율을 적용한 가중 살 단위이므로 배율을 다시 곱하지 않고, 바이옴 50단위·공통 150단위 기준과 기존 `hair_carry`로 한 번 이전한다. 새 저장은 표식을 기록하며, 구형 죽음 드롭도 첫 복구 때 이전한 뒤 표식과 빈 `pending_hairs`로 재복구 중복을 막는다. 이미 버려져 저장되지 않은 위장 살은 복원할 수 없고, 그 양을 추측해 털을 다시 만들지 않는다.

실제 섭취 이벤트는 섭취된 살 단위만 털 계산에 전달한다. 들고 있는 살은 아직 섭취량이 아니며, 믹서기는 마시는 시점에 담긴 양의 60%만 섭취로 반영한다. `FDKStomachConfig.flesh_per_cell`의 기본값은 한 셀당 4 살 단위이고 소비자는 설정된 값을 받는다. 대형 톱 한 번은 최대 여섯 셀을 먹는다. 분수 잔여량은 풀별 `hair_carry`에 보존한다.

변기 레버 정산의 `FPProgression.settle()` 결과 모양은 `{teeth, hairs, by_pool}`이며, 현재 `hairs`와 모든 `by_pool` 값은 0이다. Main의 공개 `flushed(teeth_gain, hair_gain)` 신호 모양은 유지되고 레버를 당기면 두 번째 값은 0이다. 털은 실제 먹는 순간 이미 지급되며, 변기 정산은 이빨만 지급한다.

## 플레이어 이동 경계

`FDKFirstPersonController.movement_filter`는 선택적인 Callable이다. 초 단위 물리 프레임에서 요청된 세계 이동 벡터를 받아 허용된 이동 벡터를 반환하며, 컨트롤러는 이를 속도로 환산한 뒤 기존 `move_and_slide()`를 실행한다. 콜백이 없으면 기존 독립 컨트롤러의 물리 동작을 유지한다. Main이 현재 실제 지형과 전체 캡슐의 경계를 연결하며 키트는 Main을 참조하지 않는다.

허용된 이동은 출발 캡슐에서 반환 벡터까지의 실제 직선 전체 경로와 끝점이 안전해야 한다. 여러 축으로 꺾어 검사한 경로를 합벡터의 안전성으로 대신하지 않는다. 현재 살점이 몸을 침범한 경우의 짧은 탈출은 별도의 전체 캡슐 경로 검사와 기존 물리 충돌을 통해 수행한다.

## 조준 결과

Main._look_hit()는 맞지 않으면 빈 Dictionary, 맞으면 collider와 세계 position을 포함한 히트 사전을 반환한다. 실제 지형 collider는 fdk_terrain_chunk 메타를 가진다. 소비자는 원격 셀 좌표를 새로운 히트처럼 만들어 넣지 않는다. 도구는 같은 거리·차폐를 만족하는 히트에서 동작하며 실제 내부·임시 표면도 그 계약을 따른다.

## 먹기 신호

FDKChewer.try_start(world_pos)는 세계 위치를 받아 같은 셀을 이어 잡거나 새 셀 진행을 시작한다. 유효하지 않은 살에서는 stop으로 이어진다. process_chew(delta)는 초 단위 시간을 진행하고 stop()은 진행을 해제한다. terrain과 config가 없는 경우 진행하지 않는다.

grab_started(target_cell: Vector3i)는 셀을 새로 잡을 때, chew_progress(ratio: float,target_cell: Vector3i)는 진행0~1을, cell_torn(world_pos: Vector3)는 실제 제거 완료 세계 위치를 전달한다. released()는 잡던 상태에서 놓는 전환에 한 번 발생한다. 손과 소리는 신호를 구독하며 Chewer가 손 mesh 구조를 읽지 않는다.

## 지형 수정

FDKTerrainField.dig_at(world_pos: Vector3,amount: float)는 실제 셀과 이웃 공유 모서리 밀도를 제거하고 게시할 지형을 표시한다. 반환값은 없으며 부작용 결과는 밀도·메시·충돌에서 확인한다. serialize()/deserialize(Dictionary)는 청크 상태를 주고받는다. 소비자는 복원 뒤 실제 화면이 필요한 시점에 게시를 준비해야 하며 데이터 적용만으로 첫 화면 준비를 단정하지 않는다.

외부 HTTP API나 로그인 프로토콜은 제공하지 않는다. 키트의 Godot 호출과 신호, 로컬 파일 형식이 소비자 경계다.
