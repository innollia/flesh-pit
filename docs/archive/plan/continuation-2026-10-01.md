# 2026-10-01 작업 인수 및 수정 검증

인수 기준 HEAD: `e62bee9`. 이전 작업 기록은 Downloads의 `flesh-pit-code-structure-refactoring-plan-20261001T111157Z.kcsession.json` 디렉터리 안 같은 이름의 JSON(메시지 222개)에서 읽었다.

이 문서는 이전의 완료 보고를 대체한다. 사용자가 재검토에서 지적한 고정된 시작 살벽, 설정 팝업, 거울의 앞으로 뻗은 팔, 화장실 배치, 파이지 않는 살점은 이전 구현의 결함이었다. 아래 내용은 재수정 후 코드·입력 검사 및 실제 렌더링 캡처로 확인한 상태다. 최초 세션의 대규모 구조 리팩터링(GameRoot/RunState/전체 FSM 분리)은 이번 게임 수정 완료 범위에 포함하지 않는다.

## 최신 지적에 대한 변경

| 번호 | 변경 |
| --- | --- |
| 1 | 시작 화면의 별도 평면과 가짜 살점 셰이더를 제거했다. 실제 `FDKTerrainField`/`FDKChunk`의 로우폴리 메시 생성기, 인게임 압축 조직 텍스처, PS1 재질과 조직 운동을 사용한다. Black Han Sans 글씨를 해당 표면에 샘플링하므로 삼각형과 함께 굽고 움직인다. 변형에 맞춰 클릭 위치를 역산한다. |
| 2 | 설정의 `PanelContainer` 팝업을 제거했다. 화면 전체의 정사각형 타일 배경에 설정 항목과 값이 직접 나온다. 값 선택·키 설정·닫기도 상자 없는 글씨다. 설정 중에는 뒤의 살점 뷰포트를 렌더링하지 않는다. |
| 3 | 새 게임 확인의 긍정 버튼을 `BONG`으로 바꿨다. 새 게임 행에서 확인하고, 취소/Esc는 원래 버튼으로 돌아간다. |
| 4 | 거울의 팔을 1인칭 손 위치로 끌어올리던 IK/관절 동기화를 제거했다. 기본 몸은 원래 팔을 내린 자세로 서고, 도구는 그 손에 붙인다. 피·소지품·먹는 중 입의 살점은 유지한다. 한쪽 거울만 보일 때도 갱신한다. |
| 5 | 참고 사진의 좁은 방 비율로 재구성했다. 변기 탱크는 왼쪽 벽, 그 뒤에 벽걸이 세면대, 위에 큰 2문 거울 수납장, 욕조는 뒷벽 전체, 샤워기는 왼쪽 뒤 모서리다. 선반·수전·배수구·원형 천장등·환풍구를 재배치했다. 기존 지시대로 창문은 만들지 않았다. 충돌체, 변기에 앉는 위치와 방향, 일어나는 위치, 거울/변기 상호작용도 새 배치에 맞춘다. |
| 6 | 숨겨진 벽 이음새를 맞추는 제약에서 문 앞 살점과 파낸 면을 제외했다. 빈 셀은 씹기를 시작할 수 없고, 완성 시에도 남은 밀도를 재확인한다. 새 파기 대상을 다시 찾으므로 같은 빈 셀로 위장만 계속 찰 수 없다. 실제 손 사용 입력을 계속 누르는 검사에서 지형과 충돌 면이 안쪽으로 물러났다. |
| 7 | 위장 충전율 숫자와 막대 HUD를 추가했다. 100% 이상은 빨간색과 현재 토하기 키를 함께 표시한다. |
| 8 | 문 앞은 원래의 이진 밀도 표면과 불규칙한 로우폴리 형태를 복원했다. 숨겨진 방 벽 이음새만 붙이고, 노출된 살점에는 인게임 조직 운동을 적용한다. |
| 9 | 요청이 비어 있어 추가 변경 없음. |
| 10 | 시작 시 강제로 만들던 문 앞 신경 줄기를 제거했다. 최초 1m의 문 앞 조직은 일반 살이다. 줄기는 최소 8셀을 파고 문 뒤 깊이 0.8m를 넘긴 다음에 기존 노출 확률/실제 표면 탐색으로 나타난다. 파낸 셀 수는 저장한다. |
| 11 | 닫힌 환풍구 뒤를 검은 면으로 복구했다. 천장 위 덕트 공간은 비워 외부 살점이 구멍에 튀어나오지 않게 했다. 열면 검은 덕트 속 NPC와 거래 동작을 유지한다. |
| 12 | 내장 imagegen으로 PS1 얼굴 UV 텍스처를 생성했다. 기본 눈·눈썹·코·입/턱 장식의 3D 메시를 제거하고, 6면 단면의 낮은 폴리곤 머리에 한 장의 이미지를 적용한다. 셰이더는 64×64 픽셀로 샘플링한다. 눈 변이는 이미지 UV 확대, 특수 변이 부속물과 입 살점의 기준점은 유지한다. |
| 13 | 벽과 바닥 타일은 모두 0.3×0.3m 정사각형이다. 천장은 사진처럼 타일 없는 단색이다. |

## 저장 및 이전 요구 유지

세이브 슬롯 하나와 자동저장, 일시정지 메뉴의 수동 저장 버튼 제거를 유지했다. 저장 버전은 4다. 이전 넓은 방에서 저장한 위치가 새 벽에 갇히지 않도록 방 부근은 새 구조에 맞추고 안전한 시작 위치로 옮긴다. 획득한 진척과 외부에서 파낸 통로는 보존하며, 자동 검사로 확인했다.

W로 일어나기, 사용한 조작 안내만 사라지기, 좌우 손별 도구 사용, Z/X 이전·다음 도구, 벨트를 바라보고 해당 손 버튼으로 스왑하기, 양팔 기본 메시 통일, 시작 시 카나리아 없음, 팬티 안 카나리아와 부풀기, 물탱크의 들고 내려놓는 뚜껑, 좁힌 문 상호작용, 고정 기준의 토하기 카메라와 아래쪽 이펙트, 큰 Tab 전신 표시를 유지했다. 평지 Space 이동은 제거하고 이전 대화에서 허용된 살점에 붙어 오르는 동작은 유지한다. 엔딩 완료는 저장 후 시작 화면으로 돌아간다.

## 얼굴 이미지 생성

내장 `image_gen.imagegen` 사용. 생성 원본은 Codex generated_images에 남겨두고 프로젝트에 복사했다.

프로젝트 자산: `game/main/art/textures/player_face_ps1.png`.

사용한 프롬프트:

> Create a GAME ASSET: a flat rectangular face texture for a low polygon PS1 adult male character. Entire image is the skin-colored rectangular UV texture, not a rendered head, not a portrait, no border, no hair, no ears, no neck, no background. Neutral tired adult man, pale warm beige pink skin, small brown eyes, dark short eyebrows, modest straight nose, closed thin neutral lips. Features compact and placed LOWER in the texture: eyebrows near 47% height, eyes 53%, nose 65%, mouth 78%. Top 40% is plain forehead skin. Left and right edges plain skin. Bottom plain skin chin. Deliberate old PlayStation 1 64x64 pixel art texture look with clearly square pixels, limited muted colors, flat ambient light, no realistic highlights or dramatic shading. Front-facing perfectly symmetrical flat UV map. One single texture, no text.

## 검사 결과

Godot 4.7.2. 전체 1,151개 통과, 실패 0개.

| 검사 | 통과 |
| --- | ---: |
| kit | 131 |
| main | 124 |
| save/load | 8 |
| audio | 174 |
| belt | 84 |
| hand motion | 42 |
| mutation | 145 |
| settlement/vent | 163 |
| tissue/tools | 95 |
| menu | 64 |
| continuation | 31 |
| dual-hand controls | 51 |
| actual window | 7 |
| latest revision | 32 |

실제 창 검사는 headless에서 생략되는 검사가 아니라 네이티브 창에서 실행했다. 새 revision 검사는 손 사용 입력 240프레임을 실제 물리 프레임과 메시 갱신 사이에 진행해, 고유한 셀만 먹고 충돌 표면이 후퇴하는 것을 확인한다. 기존 저장 호환, 두 거울의 단일 몸 공유, 두 번째 거울만 보일 때 도구 갱신, 기본 자세에서 입 살점 없음, 초기 신경 없음, 검은 환풍구, 설정 팝업 없음, 정사각형 타일도 확인한다.

일부 기존 테스트 종료 시 ObjectDB/resource 정리 경고가 남는다. menu의 잘못된 JSON 입력 오류는 해당 오류 처리를 검증하는 기존 검사다. 스크립트 구문/실행 오류는 최종 검사에서 없었다. 로그: `game/captures/continuation/logs/`의 revision/verified 파일.

UHD Graphics 770, 1280×720 네이티브 창에서 화장실 120프레임 표본은 거울 화면 밖 61.1 FPS, 거울 표시 68.5 FPS였다. 별도로 실행 중인 편집기/게임도 남아 있어 이전 실행의 약 100 FPS와 직접 비교하지 않는다. 거울은 면당 128×192로 비율을 맞추고, 화면 밖과 시작 화면에서는 렌더링을 중단한다.

## 실제 화면 캡처

`game/tools/capture_continuation.gd`로 생성. 파일은 `game/captures/continuation/`에 있다.

- `title.png`, `title_motion.png`: 실제 로우폴리 살점과 시간에 따라 움직이는 글씨.
- `confirm.png`: 같은 행의 질문/BONG/취소.
- `settings.png`: 타일 위 전체 설정 화면.
- `seated_w.png`: 앉아서 기다리는 W 안내.
- `bathroom_clean.png`: 사진을 따른 가구 배치와 정사각형 타일.
- `mirror_both_hands.png`: 팔을 내린 자세, 생성한 얼굴, 두 소지 도구.
- `mirror_cabinet_open.png`: 두 거울 수납문 열기.
- `vent_closed.png`, `vent_open.png`: 검은 환풍구와 열리는 NPC 공간.
- `door_flesh_before.png`, `door_flesh_dug.png`: 파기 전후 실제로 물러난 지형과 증가한 위장 HUD.
- `held_lid.png`, `dropped_lid.png`, `keybinds.png`: 뚜껑 및 키 설정.
