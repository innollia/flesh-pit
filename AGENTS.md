# flesh-pit

TINProject의 게임 키트에서 분리된 로컬 1인칭 인디 게임이다. 화장실에서 출발해 재생하는 살을 먹고 파며 바깥으로 나간다.
Godot 4.7 Compatibility 프로젝트이며, 재사용 키트와 게임의 진행·표현을 분리한다.

## 프로젝트 구조

```text
.
├── AGENTS.md → 작업 진입점과 중요한 보존 조건
├── CLAUDE.md → 같은 내용의 작업 진입점
├── docs/
│   ├── architecture.md → 게임·키트·소리의 연결
│   ├── business-rules.md → 굴착·위장·재생·정산의 행동
│   ├── security.md → 로컬 저장과 사용자 데이터 경계
│   ├── standards.md → 구현 경계와 검사 조건
│   ├── engineering-notes.md → 면 방향·갱신·조준·복원에서 확인한 함정
│   ├── operations.md → 실행과 격리 검사 절차
│   ├── contracts.md → 키트 호출·신호·저장 소비자 계약
│   └── tracking/
│       ├── status.md → 구현·검증 상태와 남은 게임 검증
│       ├── findings.md → 현재 범위 밖의 확인된 문제
│       └── decisions/
│           ├── index.md → 결정 목록
│           ├── 0001-continuous-regeneration.md → 느린 연속 재생
│           ├── 0002-actual-terrain.md → 실제 살점 면으로 내부 표시
│           └── 0003-publication-and-restore.md → 단계 게시와 복원 시점
└── game/
    ├── main/AGENTS.md → 게임 조작·진행·표현·단일 저장
    ├── addons/flesh_dig_kit/AGENTS.md → 재사용 지형·먹기·몸·도구
    └── audio/AGENTS.md → 상태를 읽고 신호를 받는 소리 연결
```

## 중요한 조건

- 먹은 살, 제거된 밀도, 보이는 구멍과 이동 공간이 같은 굴착을 표현해야 한다. 위장 증가만으로 굴착 성공을 판단하지 않는다.
- 실제 살 내부의 누출을 배경 변경·화면 덮개·플레이어 순간이동으로 숨기지 않는다.
- 정상 플레이의 단일 저장을 검사에서 읽어 덮어쓰거나 초기화하지 않는다. 저장 호환성은 실제 과거 파일의 별도 복사본으로 확인한다.
- 키트는 게임의 Main·화장실·진행 상태를 가져오지 않는다. 소리 연결은 게임 상태를 읽거나 신호를 구독하며 진행을 변경하지 않는다.

## 작업 전 확인

기본으로 docs/standards.md, docs/engineering-notes.md와 해당 디렉터리의 AGENTS.md를 읽는다.
지형 면·조준 수정 전에는 docs/engineering-notes.md의 공유 경계·면 방향·근접 카메라 항목과 docs/contracts.md의 히트·먹기 신호를 확인한다.
재생 수치 수정 전에는 docs/business-rules.md의 보호·용해·수축·방벽 압력을 확인한다.
저장 수정 전에는 docs/security.md와 docs/engineering-notes.md의 첫 렌더링 복원 조건을 확인한다.
팔·Tab·피부 수정은 현재 파일 상태와 승인된 기준을 대조한다. B 자세에서 오른팔이 뒤로 빠지고 왼팔이 올라오는 동작, 원래 몸색과 카메라에 정렬된 인형을 다른 기능 수정에 섞어 바꾸지 않는다.

사용자 저장 손상, 먹은 양과 실제 제거의 불일치, 실제 고체 안의 외부 누출, 승인된 팔·Tab·문·피부 기능 훼손은 사용자에게 즉시 알린다. 나머지 미해결 문제는 docs/tracking/findings.md에 재현 조건과 범위를 기록한다.
