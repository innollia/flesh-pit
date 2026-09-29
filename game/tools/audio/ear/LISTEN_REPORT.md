# LISTEN REPORT

Models: laion/clap-htsat-unfused (zero-shot CLAP), MIT/ast-finetuned-audioset-10-10-0.4593 (AudioSet top-10)

| file | intent | clap top label | clap top score | intent rank | warn |
|---|---|---|---|---|---|
| 01_tear_flesh_v1.wav | wet ripping of raw meat and flesh tearing | wet ripping of raw meat and flesh tearing | 0.5702 | 1 | ok |
| 02_tear_fat_v1.wav | squelchy wet mushing sound of fat tissue being torn | squelchy wet mushing sound of fat tissue being torn | 0.3999 | 1 | ok |
| 03_tear_nerve_v1.wav | a whip-like crack of a nerve or cord snapping and twanging | a whip-like crack of a nerve or cord snapping and twanging | 0.5446 | 1 | ok |
| 04_tear_membrane_v1.wav | rubbery creak followed by a wet pop of membrane bursting | rubbery creak followed by a wet pop of membrane bursting | 0.9205 | 1 | ok |
| 05_swallow_v1.wav | a person gulping and swallowing loudly | a person gulping and swallowing loudly | 0.8431 | 1 | ok |
| 06_stomach_gurgle_v1.wav | human stomach gurgling and rumbling | human stomach gurgling and rumbling | 0.9858 | 1 | ok |
| 07_chew_loop_a.wav | a person chewing wet food repeatedly | a person chewing wet food repeatedly | 0.665 | 1 | ok |
| 08_chew_loop_b.wav | crunchy cartilage chewing with occasional clicks | crunchy cartilage chewing with occasional clicks | 0.7395 | 1 | ok |
| 09_chew_strain.wav | a person straining and grunting while swallowing with nasal breathing | a person straining and grunting while swallowing with nasal breathing | 0.6392 | 1 | ok |
| 10_vomit_toilet_v1.wav | a person vomiting into a toilet with liquid splashing | a person vomiting into a toilet with liquid splashing | 0.6442 | 1 | ok |
| 11_vomit_floor_v1.wav | a person vomiting onto a hard floor with splatter | a person vomiting onto a hard floor with splatter | 0.9926 | 1 | ok |
| 12_step_flesh_s1_v1.wav | a single wet squelchy footstep on soft flesh | a single wet squelchy footstep on soft flesh | 0.6289 | 1 | ok |
| 13_step_flesh_s3_v1.wav | a heavy wet squelchy footstep on soft flesh with more weight | a heavy wet squelchy footstep on soft flesh with more weight | 0.4356 | 1 | ok |
| 14_step_tile_s1_v1.wav | a crisp clicking footstep on hard tile floor | a crisp clicking footstep on hard tile floor | 0.5217 | 1 | ok |
| 15_step_tile_s3_v1.wav | a heavy footstep on tile with wet flesh residue splatting | a heavy footstep on tile with wet flesh residue splatting | 0.6836 | 1 | ok |
| 16_toilet_flush_v1.wav | a toilet flushing with rushing water and swirling drain | a toilet flushing with rushing water and swirling drain | 0.5553 | 1 | ok |
| 17_canary_warn_v1.wav | a small bird chirping a warning call, pitched up | a small bird chirping a warning call, pitched up | 0.9622 | 1 | ok |
| 18_canary_wrong_v1.wav | a small bird making a strange distorted warble | a small bird making a strange distorted warble | 0.9975 | 1 | ok |
| 19_amb_restroom.wav | a restroom ambience with faint ventilation fan hum | air conditioner hum | 0.7593 | 3 | WARN |
| 20_amb_body_a.wav | a low deep ambient rumble inside a body cavity, shallow shell | wind blowing | 0.5113 | 4 | WARN |
| 21_amb_body_b.wav | a low deep ambient rumble inside a body cavity, deep shell | wind blowing | 0.5135 | 4 | WARN |
| 22_depth_marker_v1.wav | a soft musical chime marking depth, with faint background noise | a soft musical chime marking depth, with faint background noise | 0.6532 | 1 | ok |
| 23_mirror_mutate_v1.wav | bones cracking and snapping | bones cracking and snapping | 0.9954 | 1 | ok |
| 24_tumor_eat_v1.wav | a person biting and chewing food with wet mouth sounds | a person biting and chewing food with wet mouth sounds | 0.8977 | 1 | ok |
| 25_barrier_deploy_v1.wav | a metal ratchet mechanism clicking | a metal ratchet mechanism clicking | 0.9979 | 1 | ok |
| 26_barrier_strain_v1.wav | metal creaking and groaning under heavy load | metal creaking and groaning under heavy load | 0.8644 | 1 | ok |
| 27_barrier_break_v1.wav | a large metal spring boinging | a large metal spring boinging | 0.9985 | 1 | ok |
| 28_spray_hiss_v1.wav | an aerosol spray can hissing | an aerosol spray can hissing | 0.7741 | 1 | ok |
| 29_blender_drink_v1.wav | slurping a drink through a straw | slurping a drink through a straw | 0.5231 | 1 | ok |
| 30_vent_open_v1.wav | a metal gate grinding and scraping | a metal gate grinding and scraping | 0.4472 | 1 | ok |
| 31_scissors_snip_v1.wav | scissors snipping | scissors snipping | 0.9042 | 1 | ok |
| 32_saw_stroke_v1.wav | a hand saw cutting wood | a hand saw cutting wood | 0.8442 | 1 | ok |
| 33_player_death_v1.wav | a heartbeat | a heartbeat | 0.9953 | 1 | ok |
| 34_ending_roll_v1.wav | a heavy stone rolling and tumbling | a heavy stone rolling and tumbling | 0.9996 | 1 | ok |
| 35_settle_tick_v1.wav | a mechanical key click | a mechanical key click | 0.7987 | 1 | ok |
| 36_ui_click_v1.wav | a small button click | a small button click | 0.9594 | 1 | ok |

## AudioSet top-10 per file

### 01_tear_flesh_v1.wav
- Speech: 0.1981
- Breaking: 0.1007
- Slam: 0.0648
- Whack, thwack: 0.0462
- Crack: 0.0412
- Tap: 0.0372
- Smash, crash: 0.036
- Music: 0.0226
- Animal: 0.022
- Sound effect: 0.0193

### 02_tear_fat_v1.wav
- Sound effect: 0.4921
- Music: 0.0987
- Boing: 0.0505
- Bang: 0.0446
- Scratch: 0.0442
- Whoosh, swoosh, swish: 0.031
- Speech: 0.0174
- Smash, crash: 0.0164
- Whack, thwack: 0.0159
- Scrape: 0.0142

### 03_tear_nerve_v1.wav
- Whip: 0.5568
- Slap, smack: 0.0862
- Clapping: 0.0719
- Speech: 0.0297
- Chop: 0.02
- Whack, thwack: 0.0129
- Music: 0.0118
- Ping: 0.0115
- Tap: 0.0113
- Sound effect: 0.0107

### 04_tear_membrane_v1.wav
- Music: 0.2206
- Speech: 0.0667
- Sound effect: 0.0659
- Water: 0.0581
- Rain on surface: 0.0535
- Rain: 0.0443
- Slosh: 0.0322
- Gush: 0.025
- Raindrop: 0.0222
- Crackle: 0.016

### 05_swallow_v1.wav
- Heart sounds, heartbeat: 0.1914
- Heart murmur: 0.1147
- Throbbing: 0.066
- Stomach rumble: 0.052
- Speech: 0.0484
- Hum: 0.0407
- Sound effect: 0.0359
- Music: 0.0353
- Explosion: 0.0285
- Gunshot, gunfire: 0.0214

### 06_stomach_gurgle_v1.wav
- Stomach rumble: 0.2572
- Music: 0.2192
- Throbbing: 0.072
- Rumble: 0.049
- Speech: 0.0448
- Sound effect: 0.037
- Hum: 0.0363
- Electronic music: 0.0222
- Musical instrument: 0.0168
- Explosion: 0.0131

### 07_chew_loop_a.wav
- Crack: 0.8273
- Crushing: 0.0559
- Crackle: 0.0272
- Crunch: 0.0223
- Crumpling, crinkling: 0.0105
- Breaking: 0.0078
- Tearing: 0.0049
- Scrape: 0.0047
- Inside, small room: 0.0036
- Sound effect: 0.0031

### 08_chew_loop_b.wav
- Sound effect: 0.1353
- Crunch: 0.113
- Speech: 0.1027
- Snort: 0.0597
- Grunt: 0.0569
- Oink: 0.0525
- Animal: 0.0515
- Fart: 0.0298
- Scrape: 0.0297
- Burping, eructation: 0.0283

### 09_chew_strain.wav
- Biting: 0.1606
- Speech: 0.1121
- Crunch: 0.0824
- Inside, small room: 0.0462
- Oink: 0.042
- Chewing, mastication: 0.0363
- Stomach rumble: 0.032
- Mechanisms: 0.031
- Sound effect: 0.0282
- Scissors: 0.0269

### 10_vomit_toilet_v1.wav
- Fart: 0.4448
- Throat clearing: 0.1137
- Speech: 0.0894
- Fly, housefly: 0.0549
- Insect: 0.0496
- Grunt: 0.0423
- Sound effect: 0.0216
- Mosquito: 0.0188
- Bee, wasp, etc.: 0.0159
- Frog: 0.0138

### 11_vomit_floor_v1.wav
- Grunt: 0.399
- Roar: 0.1674
- Speech: 0.0613
- Animal: 0.0562
- Sound effect: 0.0562
- Groan: 0.0492
- Fart: 0.035
- Roaring cats (lions, tigers): 0.0177
- Music: 0.0114
- Inside, small room: 0.0091

### 12_step_flesh_s1_v1.wav
- Bird: 0.1263
- Pigeon, dove: 0.0819
- Sound effect: 0.0708
- Speech: 0.0633
- Coo: 0.0456
- Bird vocalization, bird call, bird song: 0.0453
- Inside, small room: 0.0437
- Water: 0.0246
- Animal: 0.0239
- Liquid: 0.0189

### 13_step_flesh_s3_v1.wav
- Breaking: 0.1826
- Crack: 0.1438
- Sound effect: 0.1204
- Speech: 0.0506
- Burst, pop: 0.0404
- Explosion: 0.0348
- Thump, thud: 0.0288
- Slam: 0.026
- Music: 0.0235
- Whack, thwack: 0.0191

### 14_step_tile_s1_v1.wav
- Crack: 0.2989
- Sound effect: 0.184
- Breaking: 0.0757
- Coin (dropping): 0.0475
- Whack, thwack: 0.0459
- Chop: 0.0201
- Thunk: 0.018
- Smash, crash: 0.016
- Speech: 0.015
- Crackle: 0.0119

### 15_step_tile_s3_v1.wav
- Bang: 0.1422
- Sound effect: 0.1348
- Burst, pop: 0.076
- Explosion: 0.0543
- Firecracker: 0.0471
- Speech: 0.0469
- Knock: 0.0342
- Whack, thwack: 0.0331
- Gunshot, gunfire: 0.0269
- Fireworks: 0.0226

### 16_toilet_flush_v1.wav
- Explosion: 0.1418
- Water: 0.1396
- Music: 0.1026
- Toilet flush: 0.0712
- Speech: 0.062
- Sound effect: 0.0409
- Burst, pop: 0.0335
- Eruption: 0.0237
- Vehicle: 0.0226
- Water tap, faucet: 0.0206

### 17_canary_warn_v1.wav
- Chirp, tweet: 0.3623
- Bird vocalization, bird call, bird song: 0.2055
- Bird: 0.1583
- Owl: 0.0754
- Animal: 0.0298
- Cricket: 0.0244
- Insect: 0.0208
- Sound effect: 0.0105
- Music: 0.009
- Environmental noise: 0.0082

### 18_canary_wrong_v1.wav
- Sound effect: 0.4058
- Music: 0.0911
- Boing: 0.087
- Animal: 0.0288
- Theremin: 0.0279
- Domestic animals, pets: 0.0199
- Cat: 0.0135
- Inside, small room: 0.0116
- Whistling: 0.0098
- Meow: 0.0097

### 19_amb_restroom.wav
- Static: 0.331
- White noise: 0.19
- Music: 0.0908
- Rustling leaves: 0.0426
- Pink noise: 0.0272
- Sine wave: 0.0226
- Electronic music: 0.0224
- Sound effect: 0.0197
- Hum: 0.0169
- Rustle: 0.0166

### 20_amb_body_a.wav
- Waves, surf: 0.2532
- Ocean: 0.1626
- Wind noise (microphone): 0.0959
- Wind: 0.0777
- Waterfall: 0.0556
- Rustling leaves: 0.0523
- White noise: 0.0327
- Pink noise: 0.0269
- Eruption: 0.0264
- Stream: 0.0218

### 21_amb_body_b.wav
- Waves, surf: 0.118
- Boat, Water vehicle: 0.1151
- Ocean: 0.0996
- Waterfall: 0.0682
- Wind noise (microphone): 0.0568
- Vehicle: 0.0538
- Motorboat, speedboat: 0.0509
- White noise: 0.0464
- Ship: 0.043
- Pink noise: 0.0394

### 22_depth_marker_v1.wav
- Bicycle bell: 0.6773
- Bell: 0.1102
- Ding: 0.0602
- Music: 0.0424
- Sound effect: 0.0205
- Clang: 0.0149
- Speech: 0.008
- Ping: 0.0037
- Bicycle: 0.0036
- Jingle bell: 0.0036

### 23_mirror_mutate_v1.wav
- Finger snapping: 0.7639
- Slap, smack: 0.0831
- Clapping: 0.0498
- Ping: 0.0197
- Speech: 0.0064
- Sound effect: 0.0064
- Music: 0.0062
- Plop: 0.004
- Whip: 0.004
- Tap: 0.0033

### 24_tumor_eat_v1.wav
- Speech: 0.1284
- Clapping: 0.0685
- Vehicle: 0.0658
- Tap: 0.054
- Run: 0.0364
- Crack: 0.0318
- Music: 0.0316
- Animal: 0.0311
- Sound effect: 0.0274
- Clip-clop: 0.0225

### 25_barrier_deploy_v1.wav
- Mechanisms: 0.1923
- Scrape: 0.1599
- Speech: 0.0753
- Ratchet, pawl: 0.04
- Rattle: 0.0342
- Inside, small room: 0.0279
- Gears: 0.0273
- Zipper (clothing): 0.0271
- Oink: 0.0252
- Sound effect: 0.0237

### 26_barrier_strain_v1.wav
- Vehicle horn, car horn, honking: 0.482
- Vehicle: 0.0691
- Toot: 0.0449
- Music: 0.0324
- Speech: 0.0313
- Outside, urban or manmade: 0.0262
- Domestic animals, pets: 0.0262
- Animal: 0.024
- Car: 0.0182
- Fowl: 0.0165

### 27_barrier_break_v1.wav
- Music: 0.2617
- Musical instrument: 0.1782
- Timpani: 0.0689
- Bowed string instrument: 0.0331
- Sound effect: 0.0285
- Plucked string instrument: 0.0248
- Guitar: 0.0232
- Cello: 0.0172
- Double bass: 0.0149
- Speech: 0.0134

### 28_spray_hiss_v1.wav
- Spray: 0.0822
- Rub: 0.0748
- Steam: 0.0693
- Mechanisms: 0.069
- Sanding: 0.0626
- Static: 0.0559
- Scrape: 0.0443
- Hiss: 0.0441
- Drill: 0.0356
- Ratchet, pawl: 0.0292

### 29_blender_drink_v1.wav
- Crunch: 0.3098
- Sound effect: 0.157
- Snort: 0.0447
- Inside, small room: 0.0377
- Scrape: 0.0315
- Biting: 0.0279
- Scratch: 0.0224
- Rattle: 0.0207
- Coin (dropping): 0.0183
- Crackle: 0.0159

### 30_vent_open_v1.wav
- Bicycle bell: 0.3941
- Bell: 0.1063
- Speech: 0.0655
- Beep, bleep: 0.0614
- Sound effect: 0.0375
- Doorbell: 0.0362
- Ding: 0.0333
- Burst, pop: 0.0177
- Buzzer: 0.011
- Music: 0.0106

### 31_scissors_snip_v1.wav
- Creak: 0.3906
- Scrape: 0.1206
- Sound effect: 0.072
- Zipper (clothing): 0.0639
- Coin (dropping): 0.0332
- Crackle: 0.0315
- Mechanisms: 0.0212
- Rattle: 0.017
- Crunch: 0.0154
- Speech: 0.0145

### 32_saw_stroke_v1.wav
- Squawk: 0.1837
- Squeal: 0.1329
- Rub: 0.0683
- Sound effect: 0.0448
- Wood: 0.0411
- Speech: 0.0366
- Squeak: 0.0356
- Scrape: 0.0335
- Tools: 0.0321
- Sawing: 0.0277

### 33_player_death_v1.wav
- Heart sounds, heartbeat: 0.7838
- Throbbing: 0.1188
- Hum: 0.0882
- Heart murmur: 0.0037
- Inside, small room: 0.0005
- Speech: 0.0004
- Music: 0.0004
- Sound effect: 0.0003
- Vehicle: 0.0002
- Car: 0.0002

### 34_ending_roll_v1.wav
- Crack: 0.1249
- Sound effect: 0.1054
- Ping: 0.0745
- Clapping: 0.0654
- Breaking: 0.0582
- Crackle: 0.032
- Chink, clink: 0.028
- Speech: 0.0261
- Walk, footsteps: 0.0215
- Tap: 0.0212

### 35_settle_tick_v1.wav
- Single-lens reflex camera: 0.1896
- Typewriter: 0.0981
- Speech: 0.0619
- Computer keyboard: 0.0561
- Sound effect: 0.0538
- Typing: 0.053
- Coin (dropping): 0.0452
- Camera: 0.0298
- Cash register: 0.0289
- Inside, small room: 0.0217

### 36_ui_click_v1.wav
- Coin (dropping): 0.1115
- Single-lens reflex camera: 0.1039
- Slap, smack: 0.0617
- Sound effect: 0.0588
- Ping: 0.0483
- Cap gun: 0.0371
- Speech: 0.0354
- Gunshot, gunfire: 0.0329
- Creak: 0.03
- Bang: 0.0232
