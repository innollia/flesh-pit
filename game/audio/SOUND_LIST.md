# flesh-pit 소리 목록 (1차)

기준: docs/tone-and-manner.md 5절. 가깝고 축축한 몸 소리, 늘 들리는 몸, 변이는 소리가 먼저 바뀜, 화장실은 형광등·물·타일 울림, 파는 동안 음악 없음(낮은 드론만). 놀래키기·웃긴 소리 없음.
효과음(sfx)은 전부 변주 4벌(`audio/sfx/<id>_v1..4.wav`), 반복음(loop)은 `audio/loops/<id>.wav`. 만드는 법: `tools/audio/`.

| id | 종류 | 언제 | 느낌 |
|---|---|---|---|
| tear_flesh | sfx 3D | 살 칸이 뜯길 때 | 늘어나는 신음 → 축축한 찢김, 낮은 둔탁음 |
| tear_fat | sfx 3D | 지방 칸 | 미끈하게 뭉개짐, 꿀렁임 |
| tear_nerve | sfx 3D | 신경 칸 | 팽팽한 가는 소리 → 툭 끊김·튕김 |
| tear_membrane | sfx 3D | 막(화장실 둘레) | 고무 삐걱임 → 퍽 |
| gag_dry | sfx | 첫 레버 정산 전 밖에서 V(헛구역질) | 목에서 두 번 치미는 헛구역질, 숨 고르기, 아무것도 안 나옴 |
| grab_refuse | sfx 3D | 맨손으로 못 잡는 조직(막·수축)을 잡을 때, 0.7초마다 | 팽팽히 늘어나는 삐걱임 → 미끄러지는 둔한 철퍽, 찢어지지 않음 |
| nerve_twitch | sfx 3D | 신경을 뜯는 순간 같이 | 주변 살이 움찔 수축, 떨림 |
| swallow | sfx | 뜯은 뒤 0.3초 | 목 꿀꺽 |
| stomach_gurgle | sfx | 위가 1/4씩 찰 때마다 | 피부 밑 꾸르륵 |
| chew_loop_a | loop | 씹는 동안 | 입 안 바로 가까이 씹기. 넘겨 먹을수록 재생 속도 1/배율(최저 0.55)로 느리고 낮아짐 |
| chew_loop_b | loop | 변이 2단계부터 씹는 동안 | 더 큰 턱, 연골 으드득 |
| chew_strain | loop | 씹는 동안, 넘겨 먹은 만큼 커짐 | 힘겨운 콧숨, 목 신음 |
| vomit_toilet | sfx | 변기 앞에서 토하기 | 헛구역질 → 쏟음 → 물 튀김, 타일 울림 |
| vomit_floor | sfx | 화장실 밖/변기 아닌 곳 | 헛구역질 → 바닥에 철퍽, 흘러내림 |
| step_flesh_s1..s3 | sfx | 살 위 걸음, 변이 단계별 | 단계가 오를수록 낮고 길고 무거움 |
| step_tile_s1..s3 | sfx | 화장실 타일 걸음 | 딱딱한 타일 → 단계가 오를수록 뒤꿈치 무겁고 살이 묻어 철벅 |
| regen_creak | sfx 3D | 몸 속에 있는 동안 5~12초마다 주변 어딘가 | 다시 자라는 살의 느린 삐걱임 |
| door_open / door_close | sfx 3D | 문 | 걸쇠 딸깍, 경첩 삐걱 / 닫히는 둔탁음 |
| toilet_flush | sfx 3D | 정산 끝(변기 화면에서 나올 때) | 레버, 쏴아 소용돌이, 물탱크 채움 |
| coin_drop | sfx 3D | 상점 구매로 동전이 변기로 | 도자기에 두 번 팅, 퐁당 |
| tank_lid | sfx 3D | 물탱크 뚜껑 열 때 | 사각 긁힘, 둔한 도자기 쿵 |
| canary_chirp | sfx 3D | 카나리아 평소 | 짧고 밝은 두 번 짹 |
| canary_warn | sfx 3D | 카나리아 경고 | 너무 빠르고 많은 짹, 점점 높아짐. 크지 않게 |
| canary_wrong | sfx 3D | 카나리아가 이상할 때 | 늘어지고 처지는, 어긋난 음정 두 겹, 밑에 가르륵 |
| amb_restroom | loop 배경 | 화장실 안 | 형광등 60Hz 윙·지직, 환풍기, 고른 공기 쉭 소리(8초마다 차오르던 물줄기 층을 2026-11-04에 고르게 폈다) |
| amb_restroom_fan | loop 배경 16 s | 화장실 안(restroom 배경 층) | 낡은 욕실 환풍기: 덕트를 지나는 고른 바람, 날개 다섯 장의 낮은 웅(112.5Hz), 가끔 헐거운 날개창이 한 바퀴마다 달각, 오래가지 않음 |
| pipe_trickle / pipe_run / pipe_glug / pipe_tick | sfx 4종 각 4변주 | 화장실 안, 끝난 뒤 45~150초 조용하다가 하나씩(들어온 뒤 첫 번은 25~70초, `audio/fp_pipe_water.gd`) | 벽 속 배관의 물: 짧은 졸졸 / 한동안 흐르고 끝에 공기 빨리는 꾸르륵 / 꾸르륵만 / 금속 똑. 방을 나가면 배경과 같이 사라진다 |
| amb_body_a + amb_heart_a | loop 배경 | 얕은 껍질(0~1) | 낮은 압력 드론 + 느린 심장(0.75Hz 쿵-쿵, 70~250Hz의 부드러운 잡음 뭉치와 희미한 닿는 소리, 노트북 스피커에서도 들림) |
| amb_body_b + amb_heart_b | loop 배경 | 깊은 껍질(2~) | 더 낮고 빽빽한 드론 + 더 느리고 무거운 심장(0.625Hz, 둘째 박이 늦고 차다) |
| shell_transition | sfx | 더 깊은 껍질로 넘어갈 때 | 몸 전체가 뒤틀리는 낮아지는 신음, 압력 |
| depth_marker | sfx | 새 깊이 도달 | 멀리서 낮게 부풀어 오름. 급격한 시작 없음 |

화장실 배경(restroom)은 amb_restroom + amb_restroom_fan 두 층이고, 배관 물소리는 그 위에 띄엄띄엄 재생되는 단발이다(2026-11-04, `tools/build_restroom_amb.py`, `audio/fp_pipe_water.gd`). 층은 같이 커지고 줄며, 물소리는 재생 중이던 것도 배경 음량을 따라 사라진다.

배경 전환: 화장실 ↔ 몸은 2초, 얕은↔깊은 몸은 3초 크로스페이드. 모든 배경 층은 계속 돌고 음량만 바뀐다(루프가 다시 시작되지 않음).

## 5차 새 소리 (전부 CC0 녹음 + PS1 질감)

| id | 종류 | 언제 | 느낌 |
|---|---|---|---|
| mirror_mutate | sfx | 거울에서 변이 살 때 | 뼈 뚝뚝 꺾이는 소리 |
| tumor_eat | sfx | 종양 먹을 때 | 물컹 깨물어 씹기 |
| barrier_deploy | sfx | 장벽 설치 | 금속 톱니 따르륵 펼침 |
| barrier_strain | sfx | 장벽이 버티다 금 갈 때(내구도 단계) | 금속 끼익 신음 |
| barrier_break | sfx | 장벽 터짐(보잉) | 큰 스프링 튕김 |
| spray_hiss | sfx | 스프레이 뿌릴 때 | 스프레이 칙 |
| blender_drink | sfx | 믹서 음료 마실 때 | 빨대로 바닥까지 후루룩 |
| vent_open | sfx | 환풍구 열릴 때 | 금속 창살 긁히며 열림 |
| scissors_snip | sfx | 가위 도구 | 가위 싹둑 |
| saw_stroke | sfx | 큰 톱 도구 | 톱질 한 번 |
| player_death | sfx | 죽을 때 | 심장 박동 |
| ending_roll | sfx | 엔딩(고기공이 굴러감) | 무거운 돌 구르는 소리 |
| settle_tick | sfx | 정산 숫자 올라갈 때 | 기계 키 딸깍 |
| ui_click | sfx | 화면 버튼 누를 때 | 작은 버튼 클릭 |
| echo_click | sfx | 반향정위(T1) 파동이 나갈 때 | 혀를 입천장에서 떼는 딸깍 |

## 배경음악 (2026-11-03, `tools/build_music.py`, `audio/fp_music.gd`)

전부 엔딩 노래 선율(`tools/build_song_layers.py`의 MELODY/HARMONY)로 만든 반복음이다. Music 버스(설정의 배경음)로 나가고, 살 속에서는 어느 것도 나오지 않는다(08-presentation 3). 곳이 바뀌면 2.5초 크로스페이드, 살로 나가면 0.8초 안에 사라진다. 엔딩 동안은 엔딩 허밍만 나온다.

| id | 종류 | 언제 | 느낌 |
|---|---|---|---|
| mus_title | loop 음악 87 s | 시작 화면(거기서 연 설정 포함) | 음 어긋난 오르골 자장가와 낡은 리드 오르간, 둘째 바퀴에 허밍, 셋째 바퀴는 단조 화음, 넷째는 조각만. D장조 44 bpm |
| mus_restroom | loop 음악 96 s | **보류(2026-11-04)**: 화장실에서 나오지 않는다. 화장실에는 환풍기·배관 배경만(`fp_music.gd` RESTROOM_ON_HOLD). 파일과 빌더는 남겨 둠. 원래 자리: 눈부심이 가시고 6초 뒤부터 8초에 걸쳐 | 젖은 손끝으로 도자기 테두리를 문지른 듯한 몇 음, 타일 울림, 대부분 고요 |
| mus_vent | loop 음악 64 s | 환풍구 창살이 열려 있는 동안 | 이를 세듯 딱딱 부딪는 소리, 걷는 둔한 저음 현, 이 사이로 부는 반 박 늦은 휘파람(둘째·넷째 바퀴), 덕트 울림. B단조 120 bpm |
| mus_pause | loop 음악 80 s | Esc 눈 감기(거기서 연 설정 포함) | 어택 없는 따뜻한 현악 패드, 10초마다 녹아 넘어가는 화음, 숨처럼 부풀고 가라앉음. Ab 리디안, 박 없음(심장은 눈꺼풀 그림이 보여 준다) |
| mus_pause_alt | loop 음악 87 s | **재생 안 함**: mus_pause의 다른 후보, 소리 모음에서 비교용 | 따뜻한 작은 방의 펠트 피아노, 화음 뒤 높은 음이 몇 초 간격으로 하나둘, 깔린 온기, 희미한 심장. Db장조 66 bpm |
| mus_mirror | loop 음악 67 s | 화장실 안에서 변이 화면(Tab)이 열린 동안. 살 속에서는 없음 | 7/8박으로 도는 부드러운 아날로그 신스 시퀀스, 좌우로 튀는 메아리, 손목시계 째깍, 멀리 긴 사인 선율. F 리디안 |
| mus_settle | loop 음악 27 s | 변기 정산 화면(0.6초에 올라옴) | 낮은 현 합주의 활 소리, 둔한 나무 두드림, 변기 안 음정 있는 물방울. Bb 프리지안 54 bpm |
| mus_keybind | loop 음악 55 s | 키 설정 회전무대 | 손으로 돌리는 낡은 유원지 오르간 왈츠, 북과 작은북, 처지는 크랭크, 마지막 바퀴는 안 나는 파이프. G단조 130 bpm 3/4 |

## 신호 연결 소리 (2026-11-03, `tools/build_wire_sounds.py`)

| id | 종류 | 언제 | 느낌 |
|---|---|---|---|
| hair_rustle | sfx | M23 감각털이 수축 1.5초 전 떨기 시작할 때(`hair_shiver_started`) | 뻣뻣한 팔 털이 빠르게 떨며 바스락, 축축함 없음 |
| gulp_whole | sfx | M15 살 더미를 통째로 삼킬 때(`gulped`) | 입 안 출렁임 → 크게 한 번 꿀떡(위장 삼키기와 다른 녹음, 더 낮고 김) → 콧숨 |
| vent_spill | sfx 3D | 터무니없는 과지불에 환풍구에서 물건이 쏟아질 때(`spilled`) | 금속·플라스틱 물건이 타일에 우르르 떨어져 튀고 하나가 구름 |
| ui_deny | sfx | 털이 모자라 거울이 부위를 거절할 때(`denied`) | 낮게 내려가는 둔한 두 음 |

- M22 외계인 손의 자동 뜯기(`alien_hand_tore`)는 Chewer의 뜯기와 같은 소리(조직별 tear_*, 신경 움찔, 0.3초 뒤 swallow)를 낸다.
- 물탱크 달그락(`tank_rattle_started`)은 coin_drop을 0.22~0.45초마다 다시 내며 흔들림이 끝날 때(`tank_rattle_finished`)까지 이어진다. 종양을 던진 정산은 3.5초 더 길다.
- song_melody·song_hum·song_voice2·magnet_hum(`Layer_*`)은 배경음(Music) 버스로 가서 설정의 배경음 음량을 따른다.
- T1 `echo_pulsed`(파동 결과 집계)는 기획(05 T1, 08 1장)에 소리가 없어서 연결하지 않았다. 혀 차는 소리는 echo_click이 맡는다.
