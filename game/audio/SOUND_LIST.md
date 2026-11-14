# flesh-pit 소리 목록 (1차)

기준: docs/tone-and-manner.md 5절. 가깝고 축축한 몸 소리, 늘 들리는 몸, 변이는 소리가 먼저 바뀜, 화장실은 형광등·물·타일 울림, 파는 동안 음악 없음(낮은 드론만). 놀래키기·웃긴 소리 없음.
효과음(sfx)은 전부 변주 4벌(`audio/sfx/<id>_v1..4.wav`), 반복음(loop)은 `audio/loops/<id>.wav`. 만드는 법: `tools/audio/`.

| id | 종류 | 언제 | 느낌 |
|---|---|---|---|
| tear_flesh | sfx 3D | 살 칸이 뜯길 때 | 당겨지는 섬유 → 축축하게 툭툭 갈라지는 찢김과 철벅임. 사인 쿵·톱니 신음 없음, 변주마다 다른 녹음 구간(2026-11-09) |
| tear_fat | sfx 3D | 지방 칸 | 미끈하게 뭉개짐, 꿀렁임. 사인 미끄럼 없음(2026-11-09) |
| tear_nerve | sfx 3D | 신경 칸 | 팽팽한 가는 소리 → 툭 끊김·튕김 |
| tear_membrane | sfx 3D | 막(화장실 둘레) | 고무 삐걱임 → 퍽 |
| gag_dry | sfx | 첫 레버 정산 전 밖에서 V(헛구역질) | 목에서 두 번 치미는 헛구역질, 숨 고르기, 아무것도 안 나옴 |
| grab_refuse | sfx 3D | 맨손으로 못 잡는 조직(막·수축)을 잡을 때, 0.7초마다 | 축축하게 버티며 늘어남 → 진창 녹음으로 미끄러져 빠짐, 찢어지지 않음. 사인 퍽·좁은 톱니 삐걱 없음(2026-11-09 round9) |
| nerve_twitch | sfx 3D | 신경을 뜯는 순간 같이 | 주변 살이 움찔 수축, 젖은 떨림. 삼각파 찍찍임 없음(2026-11-09) |
| swallow | sfx | 뜯은 뒤 0.3초 | 목 꿀꺽. 사인 후두 쿵과 녹음의 150 Hz 아래 가슴 쿵을 뺐다(2026-11-09 round9) |
| stomach_gurgle | sfx | 위가 1/4씩 찰 때마다 | 피부 밑 꾸르륵 |
| chew_loop_a | loop | 씹는 동안 | 입 안 바로 가까이 씹기, 머릿속처럼 먹먹하게(녹음 1.6 kHz 아래). 잡을 때마다 처음부터 나므로 조용한 틈에서 시작하고 사인 턱 딱 없음(round9). 넘겨 먹을수록 재생 속도 1/배율(최저 0.55)로 느리고 낮아짐 |
| chew_loop_b | loop | 변이 2단계부터 씹는 동안 | 더 크고 축축한 턱. 사인 턱 쿵·마른 1.8 kHz 위 바삭임 없음, 조용한 틈에서 시작(round9) |
| chew_strain | loop | 씹는 동안, 넘겨 먹은 만큼 커짐. 과식 한 뜻만 진다(끼임은 squeeze_breath) | 힘겨운 콧숨, 목 신음 |
| vomit_toilet | sfx | 변기 앞에서 토하기 | 헛구역질 → 쏟음 → 물 튀김, 타일 울림 |
| vomit_floor | sfx | 화장실 밖/변기 아닌 곳 | 헛구역질 → 바닥에 철퍽, 흘러내림 |
| step_flesh_s1..s3 | sfx | 살 위 걸음, 변이 단계별 (Room 버스, 걸음마다 높이·세기 조금씩 다름) | 단계가 오를수록 낮고 길고 무거움. 사인 쿵·PS1 질감 없음(2026-11-08) |
| step_tile_s1..s3 | sfx | 화장실 타일 걸음 (Room 버스의 타일 방) | 딱딱한 타일 → 단계가 오를수록 뒤꿈치 무겁고 살이 묻어 철벅. 메아리 대신 방 울림(2026-11-08) |
| regen_creak | sfx 3D | 살 속 어디서나(화장실·쉼터·엔딩 제외), 8 m 안에서 닫힘에 가장 가까운 열린 자리에서. 5~12초마다, 닫힘이 가까우면 1.5~3초마다 더 크게 | 다시 자라는 살의 느린 삐걱임. 재생 한 뜻만 진다. 톱니파·좁은 대역 없이 느려진 찢김·진창 녹음과 불규칙한 알갱이(2026-11-14, 아래 "한 입과 조임의 새 소리") |
| door_open / door_close | sfx 3D | 문 | 무거운 낡은 문: 걸쇠가 둔하게 빠지고 경첩이 낮게 갈리며 삐걱, 문짝의 무게(2026-11-09, 사인 딸깍·좁은 대역 삐걱 없음) / 닫히는 둔탁음 |
| toilet_flush | sfx 3D | 레버 정산, 시작 장면 | 레버 덜컥, 쏴아 쏟아지는 물, 꾸르륵, 바닥 배관으로 빠짐, 낮게 차오르는 물. 2.5 kHz 위 쉭 소리 없음(2026-11-09) |
| coin_drop | sfx 3D | 상점 구매로 동전이 변기로, 벨트 고리 교환 | 도자기에 두 번 팅, 퐁당 |
| teeth_rattle | sfx 3D | 레버 정산의 물탱크 달그락, 0.22~0.45초마다 | 이빨 몇 개가 물속 도자기에 둔하게 부딪침, 음정 없음(2026-11-09, 전에는 coin_drop의 팅) |
| tank_lid | sfx 3D | 물탱크 뚜껑 열 때 | 사각 긁힘, 둔한 도자기 쿵 |
| canary_chirp | sfx 3D | 카나리아 평소 | 짧고 밝은 두 번 짹 |
| canary_warn | sfx 3D | 카나리아 경고 | 너무 빠르고 많은 짹, 점점 높아짐. 크지 않게 |
| canary_wrong | sfx 3D | 카나리아가 이상할 때 | 늘어지고 처지는, 어긋난 음정 두 겹, 밑에 가르륵 |
| amb_restroom | loop 배경 | 화장실 안 | 형광등 60Hz 윙·지직, 환풍기, 고른 공기 쉭 소리(8초마다 차오르던 물줄기 층을 2026-11-04에 고르게 폈다) |
| amb_restroom_fan | loop 배경 16 s | 화장실 안(restroom 배경 층) | 낡은 욕실 환풍기: 덕트를 지나는 고른 바람, 날개 다섯 장의 낮은 웅(112.5Hz), 가끔 헐거운 날개창이 한 바퀴마다 달각, 오래가지 않음 |
| pipe_trickle / pipe_run / pipe_glug / pipe_tick | sfx 4종 각 4변주 | 화장실 안, 끝난 뒤 45~150초 조용하다가 하나씩(들어온 뒤 첫 번은 25~70초, `audio/fp_pipe_water.gd`) | 벽 속 배관의 물: 짧은 졸졸 / 한동안 흐르고 끝에 공기 빨리는 꾸르륵 / 꾸르륵만 / 금속 똑. 방을 나가면 배경과 같이 사라진다 |
| amb_body_a + amb_heart_a | loop 배경 29 s | 얕은 껍질(0~1) | 살이 다가왔다 물러나는 느린 부풂(6~12초, 불규칙), 입을 다문 듯한 330·760Hz 대역, 젖은 가닥이 갈라지는 소리 + 느린 심장(0.75Hz 쿵-쿵) |
| amb_body_b + amb_heart_b | loop 배경 41 s | 깊은 껍질(2~) | 위의 무게가 누르는 긴 압박(10~18초 간격), 몸 전체의 낮은 신음(170~520Hz 배음), 정점의 젖은 잔금 + 더 느리고 무거운 심장(0.625Hz) |
| amb_fat_caves + amb_heart_a | loop 배경 23 s | 지방 동굴 | 굵고 느린 기름 방울(180~620Hz)이 띄엄띄엄 오르고 터짐, 번들거리는 스밈, 2kHz 위 없음 |
| amb_rib_vault + amb_heart_a | loop 배경 37 s | 갈비 궁륭 | 뼈 틈을 부는 빈 병 음(290~1250Hz)이 각자의 돌풍(5~9초)으로 떴다 사라짐, 큰 울림 |
| amb_gut_folds + amb_heart_a | loop 배경 31 s | 창자 주름 | 4~10초마다 지나가는 쥐어짜는 파도와 빠른 물방울 연타(초당 9~13개, 300~1100Hz), 파도 사이 젖은 똑똑 |
| amb_cloth_wads + amb_heart_b | loop 배경 26 s | 옷 뭉치 | 울림 없는 죽은 공기, 천이 구겨지는 알갱이(600Hz~3.5kHz)가 몇 초씩, 푹신한 쿵 |
| amb_hair_thicket + amb_heart_b | loop 배경 34 s | 털 덤불 | 양쪽을 건너가는 성긴 마른 알갱이 파도(2.5~7kHz), 튕겨 돌아오는 가닥의 틱과 가는 노래 |
| body_glug / flesh_press / body_groan | sfx 3종 각 4변주 | 살 속, 띄엄띄엄(audio/fp_body_events.gd) | 벽 속 꿀렁임, 살이 눌렸다 끈적하게 떨어짐, 깊은 몸의 신음 한 번 |
| fat_blub / fat_slump | sfx 2종 각 4변주 | 지방 동굴 | 큰 기름 방울이 터짐, 지방 덩이가 흘러내려 털썩 |
| rib_creak / rib_knock | sfx 2종 각 4변주 | 갈비 궁륭 | 마른 뼈의 삐걱임(재생 삐걱임·수축 경고와 다른 900~2200Hz), 먼 곳의 둔한 뼈 두 번 |
| gut_squeeze / gut_trill | sfx 2종 각 4변주 | 창자 주름 | 주름이 조이며 액체가 밀려감, 가스가 도는 빠른 꾸르륵 |
| cloth_shift / cloth_snag | sfx 2종 각 4변주 | 옷 뭉치 | 천 뭉치가 처져 내림, 솔기 실밥이 툭툭 끊어짐 |
| hair_sway / hair_twang | sfx 2종 각 4변주 | 털 덤불 | 긴 털 더미가 쓸림, 굵은 한 가닥이 튕김 |
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
| scissors_snip | sfx | 칼(가위) 칸으로 뜯을 때, 뜯기 소리와 같이 | 날이 살덩이를 축축하게 자름, 금속 딸깍 없음(2026-11-09, 전에는 마른 가위 녹음) |
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
| mus_room_base | loop 음악 80 s (층) | 화장실·변기: 늘 돈다. 눈부심이 가시고 6초 뒤부터 8초에 걸쳐 아주 작게(`audio/room_music.json` 평소) | 젖은 손끝으로 도자기 테두리를 문지른 몇 음, 물탱크의 으뜸음. Bb 프리지안 54 bpm 72박 |
| mus_room_reckon | loop 음악 80 s (층) | 변기 앞 정산 화면에서 천천히 올라옴 | 낮은 현 합주의 활 소리, 둔한 나무 두드림, 변기 안 음정 있는 물방울(옛 mus_settle) |
| mus_room_dread | loop 음악 80 s (층) | 원정에 많이 파거나 겉껍질까지 갔다 돌아옴 | 반음 부딪는 낮은 활, 너무 느린 심장, 올라가는 높은 현, 내 것이 아닌 숨 |
| mus_room_linger | loop 음악 80 s (층) | 화장실에 3분 넘게 있음 | 가까워진 테두리 소리가 Bb·Cb 반음을 맴돈다 |
| mus_room_gut | loop 음악 80 s (층) | 위장이 80% 넘게 참 | 배 속 낮은 출렁임과 음정 있는 거품 |
| mus_room_cold | loop 음악 80 s (층) | 죽고 깨어남, 3분 동안 | 낮은 소리가 빠진 높고 가는 음, 찬 공기 |
| mus_room_wrong | loop 음악 80 s (층) | 이번 원정에 종양을 먹음, 돌아와 4분 동안 | 방의 선율을 반음의 1/3 낮게 반 박 늦게 따라 부르는 그림자 |
| mus_room_gold | loop 음악 80 s (층) | 한 번에 이빨 12개 이상 정산, 90초 동안 | 음정 있는 딸깍임과 이 방에서 유일한 장조 온기 |
| mus_vent | loop 음악 64 s | 환풍구 창살이 열려 있는 동안 | 이를 세듯 딱딱 부딪는 소리, 걷는 둔한 저음 현, 이 사이로 부는 반 박 늦은 휘파람(둘째·넷째 바퀴), 덕트 울림. B단조 120 bpm |
| mus_pause | loop 음악 80 s | 살 속에서 Esc 눈 감기(거기서 연 설정 포함). 끌 때까지 곡이 바뀌지 않는다 | 어택 없는 따뜻한 현악 패드, 10초마다 녹아 넘어가는 화음, 숨처럼 부풀고 가라앉음. Ab 리디안, 박 없음(심장은 눈꺼풀 그림이 보여 준다) |
| mus_pause_alt | loop 음악 87 s | 화장실 안에서 Esc 눈 감기(거기서 연 설정 포함). 끌 때까지 곡이 바뀌지 않는다 | 따뜻한 작은 방의 펠트 피아노, 화음 뒤 높은 음이 몇 초 간격으로 하나둘, 깔린 온기, 희미한 심장. Db장조 66 bpm |
| mus_mirror | loop 음악 67 s | 화장실 안에서 변이 화면(Tab)이 열린 동안. 살 속에서는 없음 | 7/8박으로 도는 부드러운 아날로그 신스 시퀀스, 좌우로 튀는 메아리, 손목시계 째깍, 멀리 긴 사인 선율. F 리디안 |
| mus_keybind | loop 음악 55 s | 키 설정 회전무대 | 손으로 돌리는 낡은 유원지 오르간 왈츠, 북과 작은북, 처지는 크랭크, 마지막 바퀴는 안 나는 파이프. G단조 130 bpm 3/4 |

## 신호 연결 소리 (2026-11-03, `tools/build_wire_sounds.py`)

| id | 종류 | 언제 | 느낌 |
|---|---|---|---|
| hair_rustle | sfx | M23 감각털이 수축 1.5초 전 떨기 시작할 때(`hair_shiver_started`) | 뻣뻣한 팔 털이 빠르게 떨며 바스락, 축축함 없음 |
| gulp_whole | sfx | M15 살 더미를 통째로 삼킬 때(`gulped`) | 입 안 출렁임 → 크게 한 번 꿀떡(위장 삼키기와 다른 녹음, 더 낮고 김) → 콧숨 |
| vent_spill | sfx 3D | 터무니없는 과지불에 환풍구에서 물건이 쏟아질 때(`spilled`) | 금속·플라스틱 물건이 타일에 우르르 떨어져 튀고 하나가 구름 |
| ui_deny | sfx | 털이 모자라 거울이 부위를 거절할 때(`denied`) | 낮게 내려가는 둔한 두 음 |

- M22 외계인 손의 자동 뜯기(`alien_hand_tore`)는 Chewer의 뜯기와 같은 소리(조직별 tear_*, 신경 움찔, 0.3초 뒤 swallow)를 낸다.
- 물탱크 달그락(`tank_rattle_started`)은 teeth_rattle을 0.22~0.45초마다 다시 내며 흔들림이 끝날 때(`tank_rattle_finished`)까지 이어진다. 종양을 던진 정산은 3.5초 더 길다.
- song_melody·song_hum·song_voice2·magnet_hum(`Layer_*`)은 배경음(Music) 버스로 가서 설정의 배경음 음량을 따른다.
- T1 `echo_pulsed`(파동 결과 집계)는 기획(05 T1, 08 1장)에 소리가 없어서 연결하지 않았다. 혀 차는 소리는 echo_click이 맡는다.

## 한 입과 조임의 새 소리 (2026-11-14)

열 개 모두 `manifest.json`에 있고 게임에 연결돼 있다(연결 방식은 docs/design/sound-music.md "한 입과 조임의 새 소리", 신호는 docs/contracts.md "소리 디렉터"). 전부 PS1 질감 없음, 톱니파·사인파 없음. 만드는 법은 다른 효과음과 같다(`tools/audio/patches/<id>.akkado`, `tools/audio/sounds.json`, 단발은 `tools/build_sfx_only.py`, 반복음은 `tools/render_loop_patches.py`).

| id | 종류 | 파일 | 길이 | 쓰일 곳 | 느낌 |
|---|---|---|---|---|---|
| contract_warn | sfx 3D, 4변주 | `audio/sfx/contract_warn_v1..4.wav` | 0.95 s (소리는 0.86 s에 끝남) | 수축 조직의 조임 예고. regen_creak 대신 | 근육이 숨을 들이쉬듯 낮게 차오르다 꼭대기에서 멈춤. 150~500 Hz에 무게, 급한 시작 없음 |
| regen_creak | sfx 3D, 4변주 | `audio/sfx/regen_creak_v1..4.wav` (바꿈) | 1.10 s | 재생 삐걱임만. 1.5~3초 간격으로 되풀이돼도 네 변주가 서로 다른 녹음 구간 | 젖은 살이 느리게 맞물리는 불규칙한 알갱이. rib_creak(900~2200 Hz)보다 아래 |
| squeeze_breath | sfx, 4변주 | `audio/sfx/squeeze_breath_v1..4.wav` | 0.75 s | 끼임(`squeeze` 이벤트). chew_strain 대신 | 갈비가 눌려 코로 짧게 밀려 나오는 날숨, 살이 몸에 쓸림. 목 신음 없음 |
| crush_breath | loop, 스테레오 | `audio/loops/crush_breath.wav` | 6.0 s | 압사가 차오르는 동안의 상시 층 | 채울 틈 없이 얕고 빠른 숨, 6초에 아홉 번, 박이 고르지 않음. 반복음 안에서는 빨라지지 않는다(이음에서 되돌아가므로). 빨라짐은 연결 쪽의 재생 속도로 낸다 |
| full_refuse | sfx, 4변주 | `audio/sfx/full_refuse_v1..4.wav` | 0.70 s | 위장이 가득 차 못 먹을 때 | 다문 입 안에서 치밀다 끊기는 "읍", 짧고 마른 트림. gag_dry(벌린 입의 헛구역질 두 번)와 다른 소리 |
| tear_muscle | sfx 3D, 4변주 | `audio/sfx/tear_muscle_v1..4.wav` | 0.95 s | 수축 조직(4) 뜯김 | 질긴 결이 0.4초 버티며 점점 팽팽해지다 굵고 낮게 끊김 |
| tear_cartilage | sfx 3D, 4변주 | `audio/sfx/tear_cartilage_v1..4.wav` | 0.70 s | 연골(6) 뜯김 | 둔한 우둑 한 번, 이어서 젖은 찢김. 150 Hz 아래 쿵 없음 |
| tear_cloth | sfx 3D, 4변주 | `audio/sfx/tear_cloth_v1..4.wav` | 0.75 s | 옷(7) 뜯김 | 젖은 천의 실밥이 점점 빠르게 터지고 올이 풀림. 배경의 cloth_snag은 마른 쪽 |
| tear_hair | sfx 3D, 4변주 | `audio/sfx/tear_hair_v1..4.wav` | 0.80 s | 털(8) 뜯김 | 마른 털이 당겨지다 뿌리째, 두피째 젖게 뽑힘 |
| pull_stretch | loop, 스테레오 | `audio/loops/pull_stretch.wav` | 2.0 s | 한 입의 당김. chew_progress로 음량과 높이를 움직이는 상시 층 | 젖은 섬유가 팽팽한 고른 결. 삐걱임·음정·박 없음. 음량 변화는 넣지 않았다(연결 쪽이 만든다) |

측정(`tools/audio/targets.json`의 기준 그대로, 사람이 들은 것이 아니다):

| id | 음량 LUFS | 최대치 dB | 변주 음량 차 LU | 살 배경 위 여유 dB (가장 나쁜 곳) | 그 밖 |
|---|---|---|---|---|---|
| contract_warn | −21.0 | −3.2 | 0.05 | −0.6 (body_b) | 가장 날카로운 딸깍 6.8 dB, 150 Hz 아래 쿵 −16 dB 이하 |
| regen_creak | −26.0 | −8.9 | 0.50 | 1.8 (body_b) | 소리 높이 뚜렷함 0.54 → 0.2~0.4, 900 Hz 위 몫 −14 dB |
| squeeze_breath | −21.0 | −2.4 | 0.10 | 5.6 (옷 뭉치) | chew_strain과의 스펙트럼 거리 10.9 dB |
| crush_breath | −22.0 | −9.9 | 반복음 | 4.5 (body_a) | 이음 도약 0.00, 좌우 상관 0.96, 짧은 반복 −6.0 dB |
| full_refuse | −20.0 | −1.5 | 0.49 | 4.2 (body_b) | gag_dry와의 스펙트럼 거리 16.7 dB |
| tear_muscle | −18.3~−19.7 | −1.5 | 0.70 | 8.5 (옷 뭉치) | tear_flesh와의 거리 7.3 dB |
| tear_cartilage | −18.2~−20.2 | −1.5 | 0.29 | 7.7 (창자 주름) | 150 Hz 아래 쿵 −16.6 dB 이하, tear_flesh와의 거리 7.6 dB |
| tear_cloth | −18.0 | −1.5 | 0.40 | 11.9 (옷 뭉치) | tear_flesh와의 거리 11.6 dB |
| tear_hair | −18.0~−21.3 | −1.5 | 0.75 | 12.1 (털 덤불) | tear_flesh와의 거리 30.3 dB |
| pull_stretch | −20.0 | −8.2 | 반복음 | 6.3 (옷 뭉치) | 이음 도약 0.13, 좌우 상관 0.39, 짧은 반복 −9.2 dB |

- 기준 실패는 없다. crush_breath의 짧은 반복(−6.0 dB, 기준 −8)은 숨이라는 의도된 박이라 `targets.json`의 `rhythmic_ok`에 chew_strain과 같은 이유로 이름을 올렸다. 박을 고르지 않게 한 뒤의 값이다.
- 뜯김 넷은 tear_flesh처럼 최대치에 걸려 목표 음량(−16~−18)보다 낮게 나온 변주가 있다. 지금 tear_flesh도 −16.6~−20.9다.
- contract_warn과 regen_creak는 긴 시간 스펙트럼이 가깝다(거리 5.6 dB, 둘 다 500 Hz 근처). 구별은 모양(한 번 차오르다 멈춤 대 불규칙한 알갱이)과 음량(−21 대 −26)에 있다.
- pull_stretch는 합성 잡음이 이끌고 찢김 녹음은 8 dB 아래에 깔았다. 녹음을 앞세우면 찢김의 툭툭거림이 짧은 반복 기준에 걸린다.
- 숨 녹음은 받아 둔 CC0에 없어서 숨 셋(squeeze_breath, crush_breath, full_refuse)은 잡음 합성이다. full_refuse에만 입 소리 녹음이 조금 들어간다.
- CLAP 판별(`tools/clap_arcade.py`)은 이 PC에 `C:/fpear`가 없어 돌리지 않았다. regen_creak의 아케이드 몫 1.0이 내려갔는지는 재지 않았다.
