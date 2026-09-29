# ear.py - 에이전트용 로컬 청취 도구

목적: 에이전트는 소리를 직접 들을 수 없다. 이 도구는 CLAP(zero-shot 오디오-텍스트 매칭)과 AST(AudioSet 527라벨 분류)로 wav 파일이 실제로 무엇처럼 들리는지 텍스트로 알려준다. intents.json에 적은 의도 설명이 CLAP 판정에서 1위가 아니면 WARN을 낸다.

## 설치 (이미 완료됨)
.venv는 game/tools/audio/ear/.venv 에 있다. git에는 올리지 않는다(.gitignore).

## 실행 방법
`
C:\Users\<user>\Desktop\flesh-pit-main\game\tools\audio\ear\.venv\Scripts\python.exe ^
  C:\Users\<user>\Desktop\flesh-pit-main\game\tools\audio\ear\ear.py ^
  --dir <wav들이 있는 폴더> ^
  --intents C:\Users\<user>\Desktop\flesh-pit-main\game\tools\audio\ear\intents.json ^
  --out-md C:\Users\<user>\Desktop\flesh-pit-main\game\tools\audio\ear\LISTEN_REPORT.md ^
  --out-json C:\Users\<user>\Desktop\flesh-pit-main\game\tools\audio\ear\listen_report.json
`
처음 실행 시 모델(CLAP ~600MB, AST ~350MB)을 허깅페이스에서 다운로드한다. 오래 걸리므로 백그라운드로 돌리고 로그 파일을 확인하는 방식을 권장한다.

## intents.json 작성법
파일명을 키로, intent(영어로 그 소리가 의도하는 것)와 confusions(자주 오인될 만한 다른 소리들, 실제 청취 피드백에서 나온 표현 위주)를 적는다. intent가 CLAP 판정에서 confusions보다 낮은 순위면 WARN.

## 한계
- 짧은 임팩트 사운드(찢기, 씹기, 발걸음)는 잘 잡아내지만 지속적인 배경음/앰비언스는 CLAP이 약해서 청감상 괜찮아도 WARN이 뜰 수 있다(19번 화장실 배경 사례).
- 가청성(너무 작아서 안 들림) 문제는 이 도구가 측정하지 않는다. 별도 라우드니스 체크가 필요하다.
- confusions 목록에 실제로 들리는 오인이 없으면 다른 오인이 1위로 나온다. 목록을 실제 청취 피드백으로 계속 보강해야 정확도가 올라간다.
