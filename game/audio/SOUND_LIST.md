# flesh-pit 소리 목록 (1차)

기준: docs/tone-and-manner.md 5절. 가깝고 축축한 몸 소리, 늘 들리는 몸, 변이는 소리가 먼저 바뀜, 화장실은 형광등·물·타일 울림, 파는 동안 음악 없음(낮은 드론만). 놀래키기·웃긴 소리 없음.
효과음(sfx)은 전부 변주 4벌(`audio/sfx/<id>_v1..4.wav`), 반복음(loop)은 `audio/loops/<id>.wav`. 만드는 법: `tools/audio/`.

| id | 종류 | 언제 | 느낌 |
|---|---|---|---|
| tear_flesh | sfx 3D | 살 칸이 뜯길 때 | 늘어나는 신음 → 축축한 찢김, 낮은 둔탁음 |
| tear_fat | sfx 3D | 지방 칸 | 미끈하게 뭉개짐, 꿀렁임 |
| tear_nerve | sfx 3D | 신경 칸 | 팽팽한 가는 소리 → 툭 끊김·튕김 |
| tear_membrane | sfx 3D | 막(화장실 둘레) | 고무 삐걱임 → 퍽 |
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
| amb_restroom | loop 배경 | 화장실 안 | 형광등 60Hz 윙·지직, 환풍기, 물 새는 소리 |
| amb_body_a + amb_heart_a | loop 배경 | 얕은 껍질(0~1) | 낮은 압력 드론 + 느린 심장(0.75Hz 쿵-쿵) |
| amb_body_b + amb_heart_b | loop 배경 | 깊은 껍질(2~) | 더 낮고 빽빽한 드론 + 더 느리고 무거운 심장 |
| shell_transition | sfx | 더 깊은 껍질로 넘어갈 때 | 몸 전체가 뒤틀리는 낮아지는 신음, 압력 |
| depth_marker | sfx | 새 깊이 도달 | 멀리서 낮게 부풀어 오름. 급격한 시작 없음 |

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
