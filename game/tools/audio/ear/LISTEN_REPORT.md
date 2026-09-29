1차(STAGE1) 일치율: 형님이 1차에서 문제라고 지적한 소리(합성층이 소리 정체를 망친 WARN 10개: tear_flesh, tear_nerve, chew_loop_a, chew_loop_b, chew_strain, vomit_toilet, vomit_floor, step_flesh_s1, step_flesh_s3, step_tile_s3) 중 STAGE1 단계에서 이미 도구가 WARN을 낸 비율 = 10/10 (100.0%). 즉 형님의 청감 지적과 ear.py 판정이 1차부터 전부 일치했다.


# LISTEN REPORT

Models: laion/clap-htsat-unfused (zero-shot CLAP), MIT/ast-finetuned-audioset-10-10-0.4593 (AudioSet top-10)

| file | intent | clap top label | clap top score | intent rank | warn |
|---|---|---|---|---|---|
| 01_tear_flesh_v1.wav | wet ripping of raw meat and flesh tearing | wet ripping of raw meat and flesh tearing | 0.7096 | 1 | ok |
| 02_tear_fat_v1.wav | squelchy wet mushing sound of fat tissue being torn | squelchy wet mushing sound of fat tissue being torn | 0.466 | 1 | ok |
| 03_tear_nerve_v1.wav | a whip-like crack of a nerve or cord snapping and twanging | a whip-like crack of a nerve or cord snapping and twanging | 0.5634 | 1 | ok |
| 04_tear_membrane_v1.wav | rubbery creak followed by a wet pop of membrane bursting | rubbery creak followed by a wet pop of membrane bursting | 0.9751 | 1 | ok |
| 05_swallow_v1.wav | a person gulping and swallowing loudly | a person gulping and swallowing loudly | 0.9199 | 1 | ok |
| 06_stomach_gurgle_v1.wav | human stomach gurgling and rumbling | human stomach gurgling and rumbling | 0.9801 | 1 | ok |
| 07_chew_loop_a.wav | a person chewing wet food repeatedly | a person chewing wet food repeatedly | 0.7264 | 1 | ok |
| 08_chew_loop_b.wav | crunchy cartilage chewing with occasional clicks | crunchy cartilage chewing with occasional clicks | 0.6803 | 1 | ok |
| 09_chew_strain.wav | a person straining and grunting while swallowing with nasal breathing | a person straining and grunting while swallowing with nasal breathing | 0.6792 | 1 | ok |
| 10_vomit_toilet_v1.wav | a person vomiting into a toilet with liquid splashing | a person vomiting into a toilet with liquid splashing | 0.9185 | 1 | ok |
| 11_vomit_floor_v1.wav | a person vomiting onto a hard floor with splatter | a person vomiting onto a hard floor with splatter | 0.9994 | 1 | ok |
| 12_step_flesh_s1_v1.wav | a single wet squelchy footstep on soft flesh | a single wet squelchy footstep on soft flesh | 0.5835 | 1 | ok |
| 13_step_flesh_s3_v1.wav | a heavy wet squelchy footstep on soft flesh with more weight | a heavy wet squelchy footstep on soft flesh with more weight | 0.5073 | 1 | ok |
| 14_step_tile_s1_v1.wav | a crisp clicking footstep on hard tile floor | a crisp clicking footstep on hard tile floor | 0.5491 | 1 | ok |
| 15_step_tile_s3_v1.wav | a heavy footstep on tile with wet flesh residue splatting | a heavy footstep on tile with wet flesh residue splatting | 0.531 | 1 | ok |
| 16_toilet_flush_v1.wav | a toilet flushing with rushing water and swirling drain | a toilet flushing with rushing water and swirling drain | 0.8247 | 1 | ok |
| 17_canary_warn_v1.wav | a small bird chirping a warning call, pitched up | a small bird chirping a warning call, pitched up | 0.9448 | 1 | ok |
| 18_canary_wrong_v1.wav | a small bird making a strange distorted warble | a small bird making a strange distorted warble | 0.9997 | 1 | ok |
| 19_amb_restroom.wav | a restroom ambience with faint ventilation fan hum | white noise | 0.6021 | 3 | WARN |
| 20_amb_body_a.wav | a low deep ambient rumble inside a body cavity, shallow shell | ocean waves | 0.5603 | 4 | WARN |
| 21_amb_body_b.wav | a low deep ambient rumble inside a body cavity, deep shell | wind blowing | 0.6603 | 4 | WARN |
| 22_depth_marker_v1.wav | a soft musical chime marking depth, with faint background noise | a soft musical chime marking depth, with faint background noise | 0.9841 | 1 | ok |

## AudioSet top-10 per file

### 01_tear_flesh_v1.wav
- Speech: 0.1882
- Breaking: 0.1128
- Slam: 0.0596
- Crack: 0.0574
- Whack, thwack: 0.0442
- Smash, crash: 0.0403
- Tap: 0.03
- Sound effect: 0.0215
- Music: 0.0205
- Skateboard: 0.0179

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
- Whip: 0.4596
- Slap, smack: 0.165
- Clapping: 0.0501
- Sound effect: 0.034
- Whack, thwack: 0.0303
- Finger snapping: 0.016
- Speech: 0.0144
- Chop: 0.0138
- Whoosh, swoosh, swish: 0.0105
- Music: 0.0098

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
- Heart sounds, heartbeat: 0.1936
- Heart murmur: 0.1387
- Throbbing: 0.0691
- Stomach rumble: 0.0453
- Speech: 0.0413
- Sound effect: 0.0413
- Hum: 0.0398
- Explosion: 0.0364
- Music: 0.0326
- Gunshot, gunfire: 0.0188

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
- Crack: 0.7916
- Crushing: 0.073
- Crunch: 0.0411
- Crumpling, crinkling: 0.0174
- Crackle: 0.0156
- Tearing: 0.0105
- Breaking: 0.0077
- Inside, small room: 0.0061
- Speech: 0.0035
- Sound effect: 0.0034

### 08_chew_loop_b.wav
- Crunch: 0.5328
- Sound effect: 0.1235
- Speech: 0.0601
- Scrape: 0.0443
- Biting: 0.0227
- Inside, small room: 0.0183
- Tearing: 0.0172
- Crack: 0.0129
- Grunt: 0.0121
- Fart: 0.0097

### 09_chew_strain.wav
- Speech: 0.1738
- Biting: 0.1587
- Crunch: 0.1051
- Sound effect: 0.0467
- Chewing, mastication: 0.0429
- Inside, small room: 0.0424
- Stomach rumble: 0.0291
- Computer keyboard: 0.0254
- Scissors: 0.0245
- Grunt: 0.0239

### 10_vomit_toilet_v1.wav
- Fart: 0.3918
- Speech: 0.1162
- Fly, housefly: 0.0731
- Throat clearing: 0.0706
- Grunt: 0.0582
- Insect: 0.0568
- Sound effect: 0.0295
- Mosquito: 0.0199
- Bee, wasp, etc.: 0.0194
- Frog: 0.0136

### 11_vomit_floor_v1.wav
- Grunt: 0.2615
- Speech: 0.1953
- Roar: 0.1162
- Groan: 0.0501
- Fart: 0.0494
- Sound effect: 0.0448
- Animal: 0.0386
- Inside, small room: 0.0204
- Music: 0.0176
- Gasp: 0.0157

### 12_step_flesh_s1_v1.wav
- Bird: 0.0981
- Sound effect: 0.0544
- Pigeon, dove: 0.0542
- Liquid: 0.0522
- Water: 0.0481
- Speech: 0.0458
- Bird vocalization, bird call, bird song: 0.0418
- Drip: 0.039
- Gurgling: 0.0357
- Coo: 0.0356

### 13_step_flesh_s3_v1.wav
- Breaking: 0.2479
- Crack: 0.1464
- Sound effect: 0.0891
- Speech: 0.0524
- Burst, pop: 0.0292
- Vehicle: 0.0257
- Thump, thud: 0.0245
- Slam: 0.0226
- Music: 0.0224
- Explosion: 0.0221

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
- Sound effect: 0.1312
- Speech: 0.0824
- Bang: 0.0589
- Slam: 0.0412
- Tap: 0.0406
- Whack, thwack: 0.0378
- Walk, footsteps: 0.0375
- Thunk: 0.0351
- Clapping: 0.03
- Thump, thud: 0.0295

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
- Waves, surf: 0.1881
- Pink noise: 0.1281
- Ocean: 0.1262
- Waterfall: 0.0949
- Wind noise (microphone): 0.0663
- Rustling leaves: 0.0656
- Wind: 0.0564
- Stream: 0.0405
- White noise: 0.0301
- Outside, rural or natural: 0.0269

### 21_amb_body_b.wav
- Waves, surf: 0.1181
- Boat, Water vehicle: 0.1151
- Ocean: 0.099
- Waterfall: 0.0742
- Wind noise (microphone): 0.0547
- Vehicle: 0.0533
- White noise: 0.0475
- Motorboat, speedboat: 0.0468
- Pink noise: 0.0462
- Ship: 0.0371

### 22_depth_marker_v1.wav
- Bicycle bell: 0.7616
- Music: 0.0554
- Bell: 0.0399
- Sound effect: 0.0374
- Ding: 0.0269
- Speech: 0.0058
- Coin (dropping): 0.0047
- Vehicle: 0.0031
- Ping: 0.0023
- Clang: 0.0022
