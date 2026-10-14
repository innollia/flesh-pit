# flesh-pit

구체 한가운데 화장실에서 시작해, 다시 자라는 살을 먹으며 바깥으로 파고 나가 도시 길바닥으로 떨어지는 1인칭 작은 인디 게임.

## 문서 지도

작업 진입점은 `CLAUDE.md`(= `AGENTS.md`)다. 기준 문서는 아래뿐이다.

- `CONTEXT.md`: 용어집. 기획서는 이 용어만 쓴다.
- `docs/spec/`: 기획서. `00-overview.md`가 목록과 핵심 루프다. 09는 보상 경제 척도.
- `docs/content/vent-lines.md`, `docs/tone-and-manner.md`, `docs/asset-list.md`: 대사, 톤앤매너, 그림·모델 목록
- `docs/` 바로 아래 7개(architecture, business-rules, contracts, engineering-notes, operations, security, standards): 구현 규칙
- `docs/tracking/`: 현재 상태(`status.md`), 남은 문제(`findings.md`), 결정(`decisions/`)
- `docs/whiteboard/`: 기획·시스템 화이트보드

기준이 아닌 것
- `docs/research/`: 참고 게임과 조사 자료
- `docs/archive/`: 끝난 작업 계획, 옛 진행 기록, 옛 목록. 고치지 않는다.
- `tools/artgen/`, `tools/economy/`: 그림 생성기, 경제 척도 계산기
