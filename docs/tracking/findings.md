# 미해결 확인 사항

과거 기획에는 점프·휠과 이전 재생 수치가 남아 있고 소리 연결 문서 일부에는 이미 구현된 카나리아가 없다고 적혀 있다. 과거 설명만 읽으면 제거된 조작을 다시 붙이거나 완료된 연결을 중복할 수 있다. 재생 설명만 이번에 정정했고 나머지 기획·소리 문서의 전체 정리는 사용자 승인 범위 밖이므로 현 코드와 승인된 상태를 먼저 대조해야 한다.

기존 일부 headless fixture는 tree 밖 신경 노드의 global transform 경고와 종료 시 resource/ObjectDB 잔존 경고를 낸다. 해당 검사의 실제 assertion은 통과하지만 경고를 엔진 무오류 증거로 표현할 수 없다. 굴착 수리와 무관한 기존 fixture 수명 정리는 별도 범위에서 root 부착과 종료 free 순서를 확인한다.

동일 굴착 장면의 연결 수리 후 제한 해제p95는 과거의 잘못 연결된 지형보다 약27% 높다. 실제 갱신 수와 연결된 임시 면 비용이 증가했으며 지속 지연은 줄였다. 다른 장비·장시간 이동의 비용은 이번361프레임 측정으로 확인되지 않았으므로 후속 성능 시험에서 실제 거리·활성 청크·게시 대기 수를 함께 기록한다.

## 오디오 headless 종료 시 deferred route_player 변환 오류

- 재현 명령: `godot_console --headless --path game --script res://tests/run_audio_tests.gd`.
- 승인 기준 커밋 `12fc534`와 화장실 구성요소 연결 수정 커밋 `d73c017`에서 각각 174 passed, 0 failed, 프로세스 종료 코드 0이 관찰됐다. 두 실행 모두 deferred `GDScript::route_player` 호출에서 `Cannot convert argument 1 from Object to Object` 오류가 반복됐다.
- 오류는 화장실 조작·성장 복구와 분리된 오디오 종료 경로에서 재현된다. 현재 로그만으로 인자 변환 문제인지 종료 시 대상 객체 수명 문제인지 원인을 특정할 수 없어 독립된 `FPBusRouter` deferred callback 및 종료 처리 조사 없이는 안전한 수정을 정할 근거가 없다. 함께 관찰된 기존 ObjectDB/resource 경고와 이 변환 오류의 연관성도 확인되지 않았다. 이 fixture 종료 때 오류가 나므로 오디오 종료가 깨끗하다고 주장할 수 없다. 이 단일 fixture 결과만으로 전체 게임의 실제 GUI 점검이나 역사적 저장 파일 호환성 검증이 완료됐다고 볼 수 없다.
