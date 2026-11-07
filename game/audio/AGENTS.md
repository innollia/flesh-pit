# 소리 연결

fp_audio_hookup은 게임과 키트의 신호를 받아 소리 디렉터와 manifest의 스트림을 연결한다. 게임 파일·진행·위장·지형을 수정하지 않고 상태 읽기와 신호 구독을 사용한다.

잡기·뜯기·놓기·토하기·문·정산·변이·도구 신호를 실제 발생 시점에 연결한다. 이벤트 소리를 재생하기 위해 gameplay 신호를 중복 발생시키거나 게임 tick을 대신 진행하지 않는다. 소비자가 사라질 때 연결과 루프 수명을 정리한다.

배경음악(fp_music, hookup의 자식)은 시작 화면·키 설정·Esc·환풍구·변이 화면·변기 정산의 상태만 읽어 Music 버스의 반복음을 고르고, 살 속에서는 아무것도 틀지 않는다. 살 속 곡은 fp_flesh_music(hookup의 자식)이 껍질로 고른다. 한 바퀴 뒤 쉼, 마디 표시에서 교차, 쉼터·Esc·화장실에서 사라짐, 곡이 올라온 만큼 배경을 `bed_gain_db`로 낮추고 song_melody를 물린다(`flesh_music.json`, docs/design/sound-music.md "살 속 음악"). 곡은 `tools/build_flesh_music.py`가 `tools/audio/lab/` 패치로 다시 만든다. 새로 만들거나 바꾸는 곡은 nkido 패치(`tools/audio/patches/mus_*.akkado`)로 만들고 `tools/build_music.py`가 두 바퀴 렌더해 둘째 바퀴를 루프로 접는다. 트리가 멈춘 메뉴에서도 돌도록 PROCESS_MODE_ALWAYS다.

살 속 사건(fp_body_events, hookup의 자식)은 지금 배경의 표(manifest `bed_events`)에서 단발을 불규칙 간격으로 고른다. 한 번에 한 목소리, Music 버스, 음량은 그 배경의 자기 층을 따라간다. 위치가 있는 단발은 밀도를 걸어 나가 찾은 실제 벽에서 나고(단발당 밀도 읽기 32번 이하), 벽이 없으면 위치 없이 난다. 게임 상태와 난수는 건드리지 않는다. 뜻이 있는 소리(regen_creak, 수축 경고, stomach_gurgle)는 재사용하지 않는다. 배경은 자기 층 + 그 껍질의 심장이고 바이옴이 몸 층을 깔지 않는다. 고치면 `python -X utf8 tools/build_biome_beds.py [id...]`, 비교는 `tools/measure_beds.py`와 `tools/clap_beds.py`(`C:/fpear` venv). `build_audio.py`는 `bed_events`를 지우므로 그 뒤에 다시 돌린다.

화장실 배관 물소리(fp_pipe_water, hookup의 자식)는 화장실 배경이 재생될 때만 자기 난수로 띄엄띄엄 단발을 고르고, 음량은 배경 층을 따라간다. 게임 난수와 진행을 건드리지 않는다.

manifest 경로와 실제 스트림의 존재, 씹기 유지와 중단 시 루프, 문·토하기·정산·도구 이벤트를 실제 연결로 확인한다. FP_AUDIO_LOG=1은 재생 로그만 켜며 게임 상태와 저장을 바꾸지 않는다. 남아 있는 과거 HOOKUP 설명보다 현재 Main의 실제 연결과 신호를 확인한다.

반복음 패치만 고쳤을 때는 `py -3 -B -X utf8 tools/render_loop_patches.py <id>...`로 그 파일만 다시 만든다(manifest는 그대로). `build_audio.py` 전체 실행은 manifest를 다시 쓰므로 뒤이어 다른 빌더들을 다시 돌려야 한다.

소리 모음 페이지: `py -3 -B tools/build_sound_gallery.py`로 manifest·SOUND_LIST에서 `build/sound_gallery.html`을 다시 만들고, 그 파일을 브라우저로 바로 열면(file://, 서버 없음) 모든 소리를 들을 수 있다.

fp_vent_voice는 `FPVent.line_spoken`을 받아 `audio/voice/<대사 id>.ogg` 또는 `.wav`를 Voice 버스로 재생한다. 파일이 없으면 자막만 나오고, 다음 대사가 나오면 파일 유무와 상관없이 나오던 음성을 끊는다. 게임을 고치지 않고 `voice_started`·`voice_cut` 신호만 내며, Main이 이를 자막에 연결한다. 파일은 대사 id로만 찾으므로 문구를 바꿔도 연결이 끊기지 않고, 녹음한 문구와 달라진 줄은 `tools/check_voice_files.py`가 `recorded_lines.json`과 비교해 알려 준다. 폴더의 원본을 그대로 읽어 import 없이 나오며, 내보낸 게임은 import된 사본을 쓴다. Godot의 import는 EXTENSIBLE 머리말의 24비트 WAV를 거부하므로 검사가 문제로 알리고 `--fix`가 머리말을 고친다. 녹음 대본은 `tools/build_voice_sheet.py`가 `build/voice_sheet.html`로 만든다.

fp_music은 곳마다 곡을 고르고, 화장실과 변기는 한 곡이다. `mus_room_*` 여덟 층은 같은 조·템포·길이로 AudioStreamSynchronized 하나에서 함께 돌고 음량만 움직인다. 어느 층이 올라올지는 `room_music.json`의 상황 목록이 사실(굴착·체류·위장·죽음·종양·정산)로 정한다. 시선은 사실에 넣지 않는다. 층은 같은 길이로 렌더하고 wow 곡선도 같아야 서로 밀리지 않는다(`tools/build_music.py` ROOM_STEMS). Esc 곡은 눈을 감은 곳으로 고르고(화장실 mus_pause_alt, 살 속 mus_pause) 끌 때까지 바꾸지 않는다.
