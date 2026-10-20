# 보상 척도 계산기

`reward_scale.py`는 docs/spec/09-reward-scale.md 11장의 현재 수치 감사 표를 만드는 계산기다. 게임 상수를 `params.json`에서 읽고, 실행할 때마다 같은 이름을 코드에서 다시 찾아 값과 줄을 대조한다. 코드는 읽기만 하고, 저장 파일과 user:// 경로는 열지 않으며, Godot를 실행하지 않는다. 값은 게임 안 보상 사건과 위협 사건의 간격·크기를 코드 상수로 계산한 것이고, 플레이어의 반응은 가설이다. Python 3.10 이상의 표준 라이브러리만 쓴다(f-string 식 안에 역슬래시나 같은 따옴표를 넣지 않는다).

## 표 만들기

저장소 루트에서 `python -X utf8 tools/economy/reward_scale.py`로 표를 출력한다. `--check`는 대역 밖 항목이나 코드와 다른 params 값이 있으면 목록을 내고 1로 끝난다. 지금 코드에서도 대역 밖 항목이 있어 1로 끝나므로, 새 숫자가 만든 퇴행은 기본 출력과 비교해서 본다. `--json`은 지표와 행을 JSON으로 출력하고, `--selftest`는 고정 입력으로 공식과 파서를 검사한다. 가정값은 `--te`, `--aim`, `--ritual`, `--escape`, `--door-depth`, `--u`로 바꾸고, 옵션이 없는 가정(통로 u/m, 일회성 도구, 껍질별 종양 수, 소모품 이빨 수요)은 `params.json`의 `assumptions`에서 바꾼다. 실측 기록 CSV는 `--log`로 넣는다. `--layout spec`은 7열 표를 낸다. 문서 표는 `--write docs/spec/09-reward-scale.md`로 갱신한다. 표 머리의 날짜는 실행일이 아니라 `params.json`의 `as_of`다.

## 코드가 바뀌었을 때

코드 상수가 바뀌면 `params.json`의 해당 항목에서 `value`와 `source`(파일:줄)를 함께 고친다. 값이 다르면 "값이 다르다" 경고가 나오고 `--check`가 실패하며, 표 머리에 "가상 값"이 찍혀 `--write`가 거부된다. 줄만 옮겨졌으면 "줄이 바뀌었다" 경고가 표준 오류에 나온다. 상수를 찾지 못하면 2로 끝난다. 예외로 M06_CRUSH_BONUS, M17_DAMAGE_FACTOR, GURGLE_BANDS는 못 찾으면 경고를 낸 뒤 params 값으로 계속하고 그 행에 재확인을 적는다. 코드에서 파싱한 변이 목록이 29개(공통 6, 압축 6, 수축 7, 신경 7, 조합 3)가 아니면 2로 끝난다. 고친 뒤 `--selftest`와 기본 실행을 다시 돌린다. selftest가 실패하면 기대값이 바뀐 것인지 공식이 틀린 것인지 확인하고, 의도한 변경이면 selftest 기대값을 함께 고친다.

## 새 숫자 시험

코드를 고치기 전에 `params.json`을 복사해 후보 값을 넣고 `python -X utf8 tools/economy/reward_scale.py --no-verify --params <사본> > new.md`로 돌린 뒤 기본 출력과 diff한다. 새로 대역 밖이 된 행만 판정한다. 이 출력은 머리에 "가상 값"과 코드와 다른 키가 찍히고 `--write`에 쓸 수 없다. 새 물건은 `PRICE_UNITS`·`UNLOCK_SHELL`에 넣고, 일회성 도구면 `assumptions.oneoff_tools`에도 더한다. 새 변이는 `MUTATIONS`에 더한다. 이때 29개 검사는 경고로만 나온다. 껍질별 종양 수는 `assumptions.tumors_by_shell`(예: `[4, 5, 4]`)로 시험한다. 코드에 반영한 뒤에 기본 실행과 `--write`로 문서 표를 갱신한다.

## 스프레이 회차 시뮬레이션

`spray_sim.py`는 원정 단위로 회차를 돌려 스프레이 통 상한이 몇 번 걸리는지와 회차 끝 영구 통로망 비율, 남는 이빨을 통당 횟수·쉼터 통 유무별로 낸다(결정 0005, 0006). 껍질별 원정 수·종양 수·도구 값·통로망 길이는 표(D08·D17·D18)의 값을 옮겨 적은 것이라, 그 값이 바뀌면 함께 고친다.
