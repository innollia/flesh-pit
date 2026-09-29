flesh-pit 소리 4차 개선 (원본은 game/audio/sfx, game/audio/loops)

핵심 방향: 3차에서 CLAP top-1을 못 뒤집은 10개는 "합성층이 소리 정체를 망친다"는 진단이 맞았다. bigsoundbank.com(CC0, 로그인 불필요)에서 새 CC0 원본(씹기/구토/채찍/젖은 발걸음)을 확보해 real_layer로 교체하고, 합성 출력을 5~18% 수준까지 대폭 축소했다. 새 원본은 채택 전에 ear.py로 원본 자체가 의도한 소리로 들리는지 먼저 검증했다(기존 chew/vomit 원본은 원본 자체가 heartbeat/breaking으로 판정되는 잘못된 재고였음을 확인).

01_tear_flesh_v1.wav  살 찢기: 실제 녹음(fs530919) 게인 +12dB, 합성 0.55->0.30. WARN->OK 전환.
02_tear_fat_v1.wav  지방 찢기: 통과(OK), 변경 없음.
03_tear_nerve_v1.wav  신경 찢기: 실제 녹음을 채찍 소리(nerve/fs2949, bigsoundbank CC0)로 교체, 게인 +22dB, 합성 0.45->0.05. WARN->OK 전환. intent 문구도 "채찍처럼 짝 끊어지는" 쪽으로 갱신(ear/intents.json).
04_tear_membrane_v1.wav  막 찢기: 통과(OK), 변경 없음.
05_swallow_v1.wav  삼키기: 3차에서 이미 OK, 유지.
06_stomach_gurgle_v1.wav  위 꾸르륵: 통과(OK), 변경 없음.
07_chew_loop_a.wav  씹기(기본): 실제 녹음을 씹기 소리(chew2/fs0407, "Eat a Rusk", bigsoundbank CC0)로 교체, 원본에서 가장 강한 crunch 구간(5.0s)으로 오프셋 조정, 게인 +20dB, 합성 0.15->0.06. WARN->OK 전환.
08_chew_loop_b.wav  씹기(변이 후): 같은 원본의 다른 crunch 구간(9.5s), 같은 방식. WARN->OK 전환.
09_chew_strain.wav  넘겨 먹기: 실제 녹음을 입 소리(chew2/fs0352, "Mouth Noises #1", bigsoundbank CC0)로 교체, hp 300Hz로 배경(body_a/b)과의 masking 겹침 회피, 합성 groan_tone 비중 축소(pig grunting 오인 원인). masking 게이트와 CLAP top-1 동시 통과. WARN->OK 전환.
10_vomit_toilet_v1.wav  변기에 토하기: 실제 녹음을 사람 구토(vomit2/fs2499, "Man vomiting #4", bigsoundbank CC0)로 교체, 게인 +16dB, 합성 0.45->0.18. WARN->OK 전환.
11_vomit_floor_v1.wav  바닥에 토하기: 같은 방향, vomit2/fs2496("Man vomiting #1"). WARN->OK 전환.
12_step_flesh_s1_v1.wav  살 발걸음 1단계: 처음으로 real_layer 추가(mud/fs0495, "Steps in the Mud", bigsoundbank CC0, 젖은 진창=살 철퍽 대체재), 합성 squish 비중 축소(0.9->0.5). WARN->OK 전환.
13_step_flesh_s3_v1.wav  살 발걸음 3단계: 같은 원본의 다른 구간, 같은 조치. WARN->OK 전환.
14_step_tile_s1_v1.wav  타일 발걸음 1단계: 통과(OK), 변경 없음.
15_step_tile_s3_v1.wav  타일 발걸음 3단계: real_layer 게인 +16dB, 합성 delay 후 스케일 0.30->0.15. WARN->OK 전환.
16_toilet_flush_v1.wav  변기 물 내림: 통과(OK), 변경 없음.
17_canary_warn_v1.wav  카나리아 경고: 통과(OK), 변경 없음.
18_canary_wrong_v1.wav  카나리아 이상 울음: 형님 취향, 건드리지 않음. 통과(OK), 변경 없음.
19_amb_restroom.wav  화장실 배경: 형님 긍정 평가, 손대지 말라는 지시 유지. 도구는 배경음 한계로 여전히 WARN(white noise) - 청감 우선, 유지.
20_amb_body_a.wav  몸 속 배경(얕은 껍질): saw() 규칙적 드론(엔진처럼 들리는 근본 원인)을 제거하고 여러 저주파 위상이 어긋나는 noise-gate 기반 불규칙 저음 꿀렁으로 교체. engine idling 오인은 사라짐(현재 top=ocean waves, 지속 배경음 CLAP 한계로 WARN 유지되나 목표였던 엔진 오인은 해결).
21_amb_body_b.wav  몸 속 배경(깊은 껍질): 같은 조치. engine idling 오인 사라짐(현재 top=wind blowing).
22_depth_marker_v1.wav  깊이 이정표: 3차에서 이미 OK, 유지.

결과: 22개 중 19개 OK. 남은 WARN 3개(19,20,21)는 모두 지속 배경음이라 CLAP 자체의 알려진 한계(README_EAR.md 명시)이며, 19는 형님이 이미 좋다고 확정, 20/21은 애초 목표(엔진 오인 제거)를 달성했으므로 청감 우선으로 유지.
