# 소비자 계약

## Main 저장 호출

save_to_disk()는 현재 단일 슬롯에 저장하며 성공 여부 bool을 반환한다. 기록·이름 변경 실패는 false다. load_from_disk()는 경로가 없거나 열 수 없거나 읽은 값이 Dictionary가 아니면 false이며, 성공하면 상태와 실제 지형 표시·충돌을 복원한다. 정상 플레이 경로 대신 별도 save_path를 지정해 소비자 검사를 실행한다.

Main의 저장 version은5이고 진행의 내부 version은3이다. 지형 payload는 chunks이며 각 청크의 좌표·밀도·조직·sealed·boost를 복원한다. 단일 슬롯을 다른 저장 형식으로 대체하는 변경은 기존 파일 소비자의 호환성을 함께 검증해야 한다. 설정 version1 JSON과 키 배치 JSON은 이 슬롯 payload가 아니다.

## 조준 결과

Main._look_hit()는 맞지 않으면 빈 Dictionary, 맞으면 collider와 세계 position을 포함한 히트 사전을 반환한다. 실제 지형 collider는 fdk_terrain_chunk 메타를 가진다. 소비자는 원격 셀 좌표를 새로운 히트처럼 만들어 넣지 않는다. 도구는 같은 거리·차폐를 만족하는 히트에서 동작하며 실제 내부·임시 표면도 그 계약을 따른다.

## 먹기 신호

FDKChewer.try_start(world_pos)는 세계 위치를 받아 같은 셀을 이어 잡거나 새 셀 진행을 시작한다. 유효하지 않은 살에서는 stop으로 이어진다. process_chew(delta)는 초 단위 시간을 진행하고 stop()은 진행을 해제한다. terrain과 config가 없는 경우 진행하지 않는다.

grab_started(target_cell: Vector3i)는 셀을 새로 잡을 때, chew_progress(ratio: float,target_cell: Vector3i)는 진행0~1을, cell_torn(world_pos: Vector3)는 실제 제거 완료 세계 위치를 전달한다. released()는 잡던 상태에서 놓는 전환에 한 번 발생한다. 손과 소리는 신호를 구독하며 Chewer가 손 mesh 구조를 읽지 않는다.

## 지형 수정

FDKTerrainField.dig_at(world_pos: Vector3,amount: float)는 실제 셀과 이웃 공유 모서리 밀도를 제거하고 게시할 지형을 표시한다. 반환값은 없으며 부작용 결과는 밀도·메시·충돌에서 확인한다. serialize()/deserialize(Dictionary)는 청크 상태를 주고받는다. 소비자는 복원 뒤 실제 화면이 필요한 시점에 게시를 준비해야 하며 데이터 적용만으로 첫 화면 준비를 단정하지 않는다.

외부 HTTP API나 로그인 프로토콜은 제공하지 않는다. 키트의 Godot 호출과 신호, 로컬 파일 형식이 소비자 경계다.
