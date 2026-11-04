# 소리 연결

fp_audio_hookup은 게임과 키트의 신호를 받아 소리 디렉터와 manifest의 스트림을 연결한다. 게임 파일·진행·위장·지형을 수정하지 않고 상태 읽기와 신호 구독을 사용한다.

잡기·뜯기·놓기·토하기·문·정산·변이·도구 신호를 실제 발생 시점에 연결한다. 이벤트 소리를 재생하기 위해 gameplay 신호를 중복 발생시키거나 게임 tick을 대신 진행하지 않는다. 소비자가 사라질 때 연결과 루프 수명을 정리한다.

배경음악(fp_music, hookup의 자식)은 시작 화면·키 설정·Esc·환풍구·변이 화면·변기 정산의 상태만 읽어 Music 버스의 반복음을 고르고, 살 속에서는 아무것도 틀지 않는다(화장실 자체의 음악은 보류). 새로 만들거나 바꾸는 곡은 nkido 패치(`tools/audio/patches/mus_*.akkado`)로 만들고 `tools/build_music.py`가 두 바퀴 렌더해 둘째 바퀴를 루프로 접는다. 트리가 멈춘 메뉴에서도 돌도록 PROCESS_MODE_ALWAYS다.

화장실 배관 물소리(fp_pipe_water, hookup의 자식)는 화장실 배경이 재생될 때만 자기 난수로 띄엄띄엄 단발을 고르고, 음량은 배경 층을 따라간다. 게임 난수와 진행을 건드리지 않는다.

manifest 경로와 실제 스트림의 존재, 씹기 유지와 중단 시 루프, 문·토하기·정산·도구 이벤트를 실제 연결로 확인한다. FP_AUDIO_LOG=1은 재생 로그만 켜며 게임 상태와 저장을 바꾸지 않는다. 남아 있는 과거 HOOKUP 설명보다 현재 Main의 실제 연결과 신호를 확인한다.

반복음 패치만 고쳤을 때는 `py -3 -B -X utf8 tools/render_loop_patches.py <id>...`로 그 파일만 다시 만든다(manifest는 그대로). `build_audio.py` 전체 실행은 manifest를 다시 쓰므로 뒤이어 다른 빌더들을 다시 돌려야 한다.

소리 모음 페이지: `py -3 -B tools/build_sound_gallery.py`로 manifest·SOUND_LIST에서 `build/sound_gallery.html`을 다시 만들고, 그 파일을 브라우저로 바로 열면(file://, 서버 없음) 모든 소리를 들을 수 있다.
