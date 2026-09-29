flesh-pit 소리 5차: PS1 질감 + 새 소리 14개 (원본은 game/audio/sfx, game/audio/loops)

PS1 질감: 샘플레이트를 낮춰 계단처럼 붙잡고(aliasing), PS1 SPU식 4bit ADPCM, 비트 깎기, 짧은 금속성 울림을 입혔다(tools/audio/build_audio.py PS1_LEVELS).
기본 강도 = 중(16kHz, 10bit, ADPCM 65%, 울림 14%). 소리 정체가 흐려진 것만 한 단계 낮췄다. 괄호 안이 각 파일의 강도.

01_tear_flesh  살 찢기 (PS1 아주 약)
02_tear_fat  지방 찢기 (PS1 중)
03_tear_nerve  신경 찢기 (PS1 중)
04_tear_membrane  막 찢기 (PS1 중)
05_swallow  삼키기 (PS1 중)
06_stomach_gurgle  위 꾸르륵 (PS1 중)
07_chew_loop_a  씹기(기본) (PS1 중)
08_chew_loop_b  씹기(변이 후) (PS1 중)
09_chew_strain  넘겨 먹기 (PS1 중)
10_vomit_toilet  변기에 토하기 (PS1 약)
11_vomit_floor  바닥에 토하기 (PS1 중)
12_step_flesh_s1  살 발걸음 1단계 (PS1 중)
13_step_flesh_s3  살 발걸음 3단계 (PS1 약)
14_step_tile_s1  타일 발걸음 1단계 (PS1 중)
15_step_tile_s3  타일 발걸음 3단계 (PS1 강)
16_toilet_flush  변기 물 내림 (PS1 중)
17_canary_warn  카나리아 경고 (PS1 중)
18_canary_wrong  카나리아 이상 울음 (PS1 약)
19_amb_restroom  화장실 배경 (PS1 약)
20_amb_body_a  몸 속 배경(얕은 껍질) (PS1 중)
21_amb_body_b  몸 속 배경(깊은 껍질) (PS1 약)
22_depth_marker  깊이 이정표 (PS1 약)

새 소리 (23번부터, 전부 CC0 녹음 + 아주 작은 합성 질감층):
23_mirror_mutate  거울에서 변이 살 때 - 뼈 뚝뚝 꺾이는 소리. 녹음: Finger clashes (PS1 중)
24_tumor_eat  종양 먹을 때 - 물컹 깨물어 씹기. 녹음: freesound #214865 (1차부터 보유, CC0) (PS1 중)
25_barrier_deploy  장벽 설치 - 금속 톱니 따르륵 펼침. 녹음: Large ratchet (PS1 중)
26_barrier_strain  장벽이 버티다 금 갈 때(내구도 단계) - 금속 끼익 신음. 녹음: Creaking metallic door (PS1 중)
27_barrier_break  장벽 터짐(보잉) - 큰 스프링 튕김. 녹음: Large spring (PS1 중)
28_spray_hiss  스프레이 뿌릴 때 - 스프레이 칙. 녹음: Spray (PS1 중)
29_blender_drink  믹서 음료 마실 때 - 빨대로 바닥까지 후루룩. 녹음: Straw, end of glass (PS1 약)
30_vent_open  환풍구 열릴 때 - 금속 창살 긁히며 열림. 녹음: Grinding metal gate (PS1 중)
31_scissors_snip  가위 도구 - 가위 싹둑. 녹음: Scissors (PS1 중)
32_saw_stroke  큰 톱 도구 - 톱질 한 번. 녹음: Hacksaw (PS1 중)
33_player_death  죽을 때 - 심장 박동. 녹음: Heart Beat (PS1 중)
34_ending_roll  엔딩(고기공이 굴러감) - 무거운 돌 구르는 소리. 녹음: Fall of Stone (PS1 중)
35_settle_tick  정산 숫자 올라갈 때 - 기계 키 딸깍. 녹음: Typewriter, Key (PS1 아주 약)
36_ui_click  화면 버튼 누를 때 - 작은 버튼 클릭. 녹음: Raspberry Mouse, Single Click (PS1 중)

ear.py: 36개 중 33 OK, WARN 3개는 기존과 같은 배경음 19/20/21(CLAP 지속음 한계, 청감 우선 유지).

## 5차 창작 판단 (추천안대로 진행함, 바꾸려면 번호로 답해 주세요)

1. PS1 기본 강도를 중(16kHz/10bit)으로 했습니다. 더 뭉개진 강(11kHz/8bit)은 정체가 흐려지는 소리가 많아 뺐습니다. 이대로 둘까요?
2. 죽음 소리를 심장 박동(Heart Beat)으로 했습니다. 쓰러지는 둔탁음 쪽이 나을까요?
3. 엔딩(고기공 굴러감)을 돌 구르는 소리로 했습니다. 더 축축한 굴림이 나을까요?
4. 장벽 터짐을 큰 스프링 '보잉'으로 했습니다(코드 이름 _on_barrier_boing 기준). 금속 뚝 끊김 쪽이 나을까요?
5. 거울 변이를 손가락 관절 꺾는 소리로 했습니다(뼈가 틀어지는 느낌). 살 찢김과 섞을까요?
6. 정산 숫자 소리를 타자기 키, 화면 버튼을 작은 마우스 클릭으로 했습니다. PS1 메뉴 삑 소리 같은 합성음이 나을까요?
