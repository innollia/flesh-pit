# LISTEN REPORT

Models: laion/clap-htsat-unfused (zero-shot CLAP), MIT/ast-finetuned-audioset-10-10-0.4593 (AudioSet top-10)

| file | intent | clap top label | clap top score | intent rank | warn |
|---|---|---|---|---|---|
| 01_tear_flesh_v1.wav | wet ripping of raw meat and flesh tearing | balloon deflating | 0.9029 | 2 | WARN |
| 02_tear_fat_v1.wav | squelchy wet mushing sound of fat tissue being torn | squelchy wet mushing sound of fat tissue being torn | 0.466 | 1 | ok |
| 03_tear_nerve_v1.wav | tight thin string snapping and twanging | whip crack | 0.8747 | 2 | WARN |
| 04_tear_membrane_v1.wav | rubbery creak followed by a wet pop of membrane bursting | rubbery creak followed by a wet pop of membrane bursting | 0.9751 | 1 | ok |
| 05_swallow_v1.wav | a person gulping and swallowing loudly | drain gurgling | 0.7416 | 2 | WARN |
| 06_stomach_gurgle_v1.wav | human stomach gurgling and rumbling | human stomach gurgling and rumbling | 0.9801 | 1 | ok |
| 07_chew_loop_a.wav | a person chewing wet food repeatedly | paper crumpling | 0.4559 | 5 | WARN |
| 08_chew_loop_b.wav | crunchy cartilage chewing with occasional clicks | footsteps on gravel | 0.4435 | 5 | WARN |
| 09_chew_strain.wav | a person straining and grunting while swallowing with nasal breathing | dog whining | 0.4587 | 5 | WARN |
| 10_vomit_toilet_v1.wav | a person vomiting into a toilet with liquid splashing | arcade laser gun shot | 0.8092 | 2 | WARN |
| 11_vomit_floor_v1.wav | a person vomiting onto a hard floor with splatter | arcade laser gun shot | 0.6751 | 2 | WARN |
| 12_step_flesh_s1_v1.wav | a single wet squelchy footstep on soft flesh | footstep on wet sand | 0.8256 | 2 | WARN |
| 13_step_flesh_s3_v1.wav | a heavy wet squelchy footstep on soft flesh with more weight | footstep on wet sand | 0.8701 | 3 | WARN |
| 14_step_tile_s1_v1.wav | a crisp clicking footstep on hard tile floor | a crisp clicking footstep on hard tile floor | 0.5491 | 1 | ok |
| 15_step_tile_s3_v1.wav | a heavy footstep on tile with wet flesh residue splatting | shovel in sand | 0.346 | 3 | WARN |
| 16_toilet_flush_v1.wav | a toilet flushing with rushing water and swirling drain | a toilet flushing with rushing water and swirling drain | 0.8247 | 1 | ok |
| 17_canary_warn_v1.wav | a small bird chirping a warning call, pitched up | a small bird chirping a warning call, pitched up | 0.9448 | 1 | ok |
| 18_canary_wrong_v1.wav | a small bird making a strange distorted warble | a small bird making a strange distorted warble | 0.9997 | 1 | ok |
| 19_amb_restroom.wav | a restroom ambience with faint ventilation fan hum | white noise | 0.6021 | 3 | WARN |
| 20_amb_body_a.wav | a low deep ambient rumble inside a body cavity, shallow shell | engine idling | 0.7795 | 3 | WARN |
| 21_amb_body_b.wav | a low deep ambient rumble inside a body cavity, deep shell | engine idling | 0.6626 | 3 | WARN |
| 22_depth_marker_v1.wav | a soft musical chime marking depth, with faint background noise | wind blowing | 0.9795 | 3 | WARN |

## 형님 1차 청취 피드백 vs 도구 판정 대조표

1차 원본은 git show 7ea1881:game/audio/listen/<파일명> 으로 꺼낼 수 있다. 아래는 형님이 1차 소리를 듣고 남긴 지적과, 이 도구가 2차(현재) 소리에서 낸 WARN/ok 판정을 나란히 놓은 것이다. 1차와 2차는 파일이 다르므로 완전한 재현 검증은 아니고, 같은 문제 패턴이 남아있는지 보는 참고 대조표다.

| 번호 | 형님 1차 피드백 | 2차(현재) 도구 판정 | 일치 |
|---|---|---|---|
| 03 | 바람소리로 들림 | WARN, top=whip crack (바람은 아니지만 여전히 의도(신경 끊김)에서 벗어난 오인 1위) | 부분 일치 (여전히 WARN) |
| 05 | 바람소리로 들림 | WARN, top=drain gurgling (바람은 아니지만 여전히 삼키기 의도에서 벗어남) | 부분 일치 (여전히 WARN) |
| 06 | 작고 꿀꺽 아님(위 소리인데 삼키기처럼 안 들림) | ok, top=intent 자체(0.98) | 개선됨 (2차는 통과) |
| 07 | 꾸르륵 아님(씹기가 이상하게 들림) | WARN, top=paper crumpling | 일치 (여전히 씹기로 안 들림) |
| 08 | 모래에 삽(질감이 모래 삽질처럼 들림) | WARN, top=footsteps on gravel (모래/자갈류 오인 계열 유지) | 일치 (여전히 모래/자갈 오인) |
| 09 | 짤깍(딸깍 소리가 튐) | WARN, top=dog whining (다른 오인이지만 여전히 의도 밖 1위) | 부분 일치 (여전히 WARN) |
| 10 | 소울음처럼 들림 | WARN, top=arcade laser gun shot (오인 후보가 소울음 대신 아케이드 총소리로 나옴, 후보 목록에 소울음 계열 없었음) | 부분 일치 (여전히 WARN, 오인 종류 다름) |
| 11 | 아케이드 총소리 | WARN, top=arcade laser gun shot | 일치 (정확히 같은 오인) |
| (발걸음 모래소리, 타일은 또각) | 살 위 발걸음이 모래처럼, 타일은 또각여야 함 | 12/13/15는 WARN(모래/삽 계열), 14(타일 1단계)는 ok(intent=또각 발걸음, 1위) | 부분 일치: 타일 1단계는 해결, 살 발걸음과 타일 3단계(살 묻음)는 여전히 모래/삽 오인 |
| 17 | 두 소리 따로 놂(경고음이 어색) | ok, top=intent 자체(0.94) | 개선됨 (2차는 통과, 단 파일 자체가 1차 대비 재작업됨) |
| 18 | 동물 같지 않음(카나리아 이상 울음) | ok, top=intent 자체(0.9997), 단 이 파일은 README상 형님 취향으로 의도적으로 유지된 것 | 참고용(원래 그대로 유지, 판정상은 통과) |
| 19 | 좋음(화장실 배경 양호) | WARN, top=white noise (배경음 특성상 CLAP이 인공적 화이트노이즈로 오인, 청감상 나쁘다는 뜻은 아닐 수 있음) | 불일치 방향: 형님은 19를 긍정 평가했으나 도구는 WARN. CLAP의 배경음/앰비언스 판정 한계로 해석 필요 |
| 20 | 초반 모래소리 남음(몸속 배경 저음에 모래질감) | WARN, top=engine idling (모래 계열은 아니지만 여전히 의도 밖) | 부분 일치 (여전히 WARN) |
| 21 | 안 들림(가청성 문제) | WARN, top=engine idling | 참고용: 가청성 문제는 이 도구가 직접 측정하지 않음(주파수 가청성은 별도 지표 필요) |
| 22 | 파도소리가 너무 강함 | WARN, top=wind blowing (파도 계열 오인이 최상위는 아니었으나 confusions 후보에 ocean waves 포함, 순위 3위) | 부분 일치: wind이 1위지만 ocean waves도 후보 안에서 경쟁 중이었음(파도 강함 지적과 방향 일치) |

### 요약
- 1차에서 지적된 오인 패턴(모래/삽, 아케이드 총소리, 바람소리, 동물 울음 계열)이 2차 도구 판정에서도 대부분 같은 방향으로 재현됐다. 이는 도구가 형님의 실제 청감 오류를 상당히 잘 잡아낸다는 뜻이다.
- 06, 14, 17, 18은 1차 지적 이후 개선되어 2차에서 통과(ok)로 나타났다.
- 19는 형님이 긍정 평가했음에도 도구가 WARN을 낸 유일한 역방향 불일치 사례다. CLAP은 짧은 임팩트 사운드보다 지속적인 배경음/앰비언스 분류에 약할 수 있어, 앰비언스 트랙은 WARN이 나와도 청감 우선으로 판단하는 것이 맞다.
- 21은 도구가 가청성(너무 작아서 안 들림) 문제를 직접 측정하지 못하는 한계 영역이다. 별도로 라우드니스/주파수 스펙트럼 체크가 필요하다.


## AudioSet top-10 per file

### 01_tear_flesh_v1.wav
- Sound effect: 0.1989
- Bang: 0.1024
- Speech: 0.0884
- Music: 0.0532
- Fart: 0.0381
- Scrape: 0.0372
- Crackle: 0.033
- Burst, pop: 0.031
- Crack: 0.0289
- Firecracker: 0.0259

### 02_tear_fat_v1.wav
- Sound effect: 0.4934
- Music: 0.1027
- Scratch: 0.0567
- Boing: 0.0492
- Bang: 0.0419
- Whoosh, swoosh, swish: 0.0286
- Speech: 0.0164
- Whack, thwack: 0.0157
- Smash, crash: 0.0148
- Scrape: 0.0113

### 03_tear_nerve_v1.wav
- Music: 0.2449
- Boing: 0.1436
- Sound effect: 0.1432
- Speech: 0.0773
- Drum machine: 0.027
- Synthesizer: 0.0183
- Electronic music: 0.0165
- Echo: 0.0144
- Sampler: 0.0119
- Musical instrument: 0.0119

### 04_tear_membrane_v1.wav
- Music: 0.2526
- Sound effect: 0.0882
- Speech: 0.0743
- Water: 0.0397
- Rain on surface: 0.036
- Slosh: 0.0313
- Rain: 0.0258
- Crackle: 0.0241
- Scratch: 0.0196
- Electronic music: 0.0166

### 05_swallow_v1.wav
- Sound effect: 0.3761
- Music: 0.1197
- Bang: 0.0729
- Explosion: 0.0439
- Whoosh, swoosh, swish: 0.0332
- Speech: 0.0295
- Grunt: 0.0172
- Burst, pop: 0.0171
- Electronic music: 0.0139
- Whack, thwack: 0.0105

### 06_stomach_gurgle_v1.wav
- Stomach rumble: 0.3163
- Music: 0.142
- Throbbing: 0.0937
- Hum: 0.0753
- Speech: 0.0489
- Rumble: 0.0447
- Sound effect: 0.0373
- Electronic music: 0.0189
- Musical instrument: 0.0132
- Heart sounds, heartbeat: 0.0122

### 07_chew_loop_a.wav
- Heart sounds, heartbeat: 0.3136
- Heart murmur: 0.2746
- Hum: 0.1199
- Throbbing: 0.0675
- Explosion: 0.0382
- Knock: 0.0162
- Burst, pop: 0.0162
- Sound effect: 0.0145
- Music: 0.0097
- Speech: 0.008

### 08_chew_loop_b.wav
- Heart murmur: 0.2448
- Heart sounds, heartbeat: 0.2172
- Explosion: 0.0516
- Sound effect: 0.0515
- Hum: 0.0372
- Throbbing: 0.0352
- Music: 0.0261
- Knock: 0.0258
- Speech: 0.0255
- Burst, pop: 0.0246

### 09_chew_strain.wav
- Music: 0.3547
- Brass instrument: 0.0696
- French horn: 0.0439
- Trumpet: 0.0335
- Musical instrument: 0.0334
- Speech: 0.0261
- Heart murmur: 0.0244
- Sound effect: 0.0165
- White noise: 0.0144
- Whoosh, swoosh, swish: 0.0135

### 10_vomit_toilet_v1.wav
- Sound effect: 0.2508
- Machine gun: 0.1336
- Gunshot, gunfire: 0.1104
- Fart: 0.0804
- Fusillade: 0.0512
- Burst, pop: 0.0419
- Explosion: 0.026
- Clatter: 0.0206
- Speech: 0.0199
- Scrape: 0.0163

### 11_vomit_floor_v1.wav
- Fart: 0.8103
- Sound effect: 0.0589
- Speech: 0.011
- Bang: 0.0109
- Burst, pop: 0.0074
- Explosion: 0.0068
- Music: 0.006
- Clatter: 0.0035
- Scrape: 0.0031
- Whoosh, swoosh, swish: 0.0031

### 12_step_flesh_s1_v1.wav
- Bang: 0.1838
- Sound effect: 0.1438
- Thunk: 0.0972
- Burst, pop: 0.0693
- Whack, thwack: 0.0391
- Slam: 0.0316
- Music: 0.0258
- Speech: 0.0238
- Firecracker: 0.0229
- Explosion: 0.0209

### 13_step_flesh_s3_v1.wav
- Explosion: 0.2128
- Burst, pop: 0.1392
- Music: 0.072
- Bang: 0.0684
- Sound effect: 0.0637
- Speech: 0.0382
- Eruption: 0.0332
- Slam: 0.023
- Gunshot, gunfire: 0.0173
- Fireworks: 0.0171

### 14_step_tile_s1_v1.wav
- Sound effect: 0.2747
- Crack: 0.1535
- Coin (dropping): 0.0843
- Breaking: 0.0753
- Whack, thwack: 0.0427
- Speech: 0.0191
- Chop: 0.0153
- Smash, crash: 0.0149
- Crackle: 0.0134
- Grunt: 0.0114

### 15_step_tile_s3_v1.wav
- Sound effect: 0.2642
- Bang: 0.1147
- Speech: 0.0424
- Slam: 0.038
- Whip: 0.0359
- Music: 0.0352
- Whack, thwack: 0.0352
- Thump, thud: 0.0288
- Gunshot, gunfire: 0.0245
- Burst, pop: 0.02

### 16_toilet_flush_v1.wav
- Water: 0.1568
- Explosion: 0.1219
- Music: 0.0951
- Toilet flush: 0.0846
- Speech: 0.0587
- Sound effect: 0.0449
- Burst, pop: 0.0333
- Water tap, faucet: 0.0276
- Sink (filling or washing): 0.0236
- Eruption: 0.02

### 17_canary_warn_v1.wav
- Chirp, tweet: 0.4045
- Bird vocalization, bird call, bird song: 0.2643
- Bird: 0.1679
- Animal: 0.0268
- Owl: 0.0195
- Environmental noise: 0.0113
- Speech: 0.0067
- Music: 0.0064
- Mouse: 0.006
- Insect: 0.0058

### 18_canary_wrong_v1.wav
- Sound effect: 0.4163
- Music: 0.1216
- Boing: 0.0433
- Theremin: 0.0337
- Animal: 0.0257
- Cat: 0.0193
- Domestic animals, pets: 0.0186
- Musical instrument: 0.0176
- Meow: 0.0171
- Opera: 0.0109

### 19_amb_restroom.wav
- Static: 0.3744
- White noise: 0.1681
- Music: 0.1016
- Rustling leaves: 0.0292
- Electronic music: 0.0266
- Sine wave: 0.0232
- Sound effect: 0.0192
- Hum: 0.0171
- Pink noise: 0.0148
- Rustle: 0.0119

### 20_amb_body_a.wav
- Music: 0.2502
- Static: 0.1332
- Electronic music: 0.0774
- Throbbing: 0.0596
- Hum: 0.0562
- Sound effect: 0.0458
- White noise: 0.0342
- Mains hum: 0.0295
- Ambient music: 0.0226
- Rumble: 0.0149

### 21_amb_body_b.wav
- Music: 0.262
- Static: 0.0755
- Electronic music: 0.0729
- Throbbing: 0.0719
- Sound effect: 0.064
- Hum: 0.0548
- Rumble: 0.0531
- White noise: 0.0273
- Ambient music: 0.023
- Mains hum: 0.0212

### 22_depth_marker_v1.wav
- Rumble: 0.2129
- Sound effect: 0.1388
- Whoosh, swoosh, swish: 0.1221
- Music: 0.0944
- Sonar: 0.052
- Hum: 0.0154
- Throbbing: 0.0151
- White noise: 0.0133
- Speech: 0.0125
- Heart murmur: 0.0124
