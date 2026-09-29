flesh-pit 소리 2차 개선 (원본은 game/audio/sfx, game/audio/loops)

01_tear_flesh_v1.wav  살 찢기: 실제 녹음(fs530919) 게인 상향(+9dB), 합성 비중 축소. CLAP은 여전히 balloon deflating으로 오인(WARN) - 추가 CC0 재고 없이는 한계.
02_tear_fat_v1.wav  지방 찢기: 통과(OK). 좁힌 합성 + 실제 녹음.
03_tear_nerve_v1.wav  신경 찢기: 실제 녹음(fs234236, crunch 계열)로 교체, 게인 +10dB, 합성 축소. 여전히 whip crack으로 오인(WARN).
04_tear_membrane_v1.wav  막 찢기: 통과(OK).
05_swallow_v1.wav  삼키기: 실제 목 넘김 녹음 게인 +14dB, 합성 축소 -> 2단계 개선으로 WARN에서 OK로 전환.
06_stomach_gurgle_v1.wav  위 꾸르륵: 통과(OK).
07_chew_loop_a.wav  씹기(기본): 게인 +12dB, lp 낮춰 자갈질감 억제. 여전히 paper crumpling으로 오인(WARN).
08_chew_loop_b.wav  씹기(변이 후): 게인 +12dB. 여전히 footsteps on gravel로 오인(WARN).
09_chew_strain.wav  넘겨 먹기: body/fs214865(씹기/물기 성분) 레이어 추가, 게인 +12dB, 합성 축소. 여전히 cattle bellowing으로 오인(WARN) - 사람 신음 CC0 미확보.
10_vomit_toilet_v1.wav  변기에 토하기: 실제 녹음 게인 +14dB, 합성 축소. 여전히 arcade laser gun shot으로 오인(WARN) - 트랜지언트 임팩트가 CLAP 판정을 지배.
11_vomit_floor_v1.wav  바닥에 토하기: 같은 방향, 같은 한계(WARN).
12_step_flesh_s1_v1.wav  살 발걸음 1단계: 합성 대역 좁힘(420->320Hz, Q 9->12), suck 노이즈 축소. real_layer 없음(CC0 발소리 재고 부족). 여전히 footstep on wet sand로 오인(WARN, 오인 자체는 원래 지적과 방향이 가까움).
13_step_flesh_s3_v1.wav  살 발걸음 3단계: 같은 조치, 같은 한계(WARN).
14_step_tile_s1_v1.wav  타일 발걸음 1단계: 통과(OK).
15_step_tile_s3_v1.wav  타일 발걸음 3단계: 게인 +10dB, hp 250->350. 여전히 footstep on sand/shovel 계열로 오인(WARN).
16_toilet_flush_v1.wav  변기 물 내림: 통과(OK).
17_canary_warn_v1.wav  카나리아 경고: 통과(OK).
18_canary_wrong_v1.wav  카나리아 이상 울음: 형님 취향, 건드리지 않음(그대로 유지). 통과(OK).
19_amb_restroom.wav  화장실 배경: 형님 긍정 평가(19), 도구는 배경음 한계로 WARN(white noise) - 청감 우선, 유지.
20_amb_body_a.wav  몸 속 배경(얕은 껍질): 중음대 필터링 노이즈 레이어 추가 + target_lufs -24->-19(가청성). 여전히 engine idling으로 오인(WARN, 배경음 CLAP 한계).
21_amb_body_b.wav  몸 속 배경(깊은 껍질): 같은 조치, target_lufs -23->-18. 같은 한계(WARN).
22_depth_marker_v1.wav  깊이 이정표: ding/fs531031(종소리) 레이어 추가, 파도(res) noise 0.18->0.07로 축소 -> 2단계 개선으로 WARN에서 OK로 전환.

한계 정리: CLAP 순위를 완전히 뒤집지 못한 항목(01,03,07,08,09,10,11,12,13,15)은 real_layer 게인을 최대 +10~14dB까지, 합성 출력을 최대 60%까지 줄였는데도 top-1이 안 바뀜. 원인은 (a) 이 항목들에 쓸 만한 CC0 재고가 이미 소진되어 재사용/치환으로는 질적 도약이 없고, (b) freesound API가 인증 없이는 신규 다운로드를 막아 새 녹음을 못 구했기 때문. 청감상 실제로 나아졌는지는 형님 직접 확인 필요(README 유지 항목 19/18과 동일하게 도구 한계로 볼 수도 있음).
