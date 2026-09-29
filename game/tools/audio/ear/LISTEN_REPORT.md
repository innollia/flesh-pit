# LISTEN REPORT (2단계 개선 최종, round4)

Models: laion/clap-htsat-unfused (zero-shot CLAP), MIT/ast-finetuned-audioset-10-10-0.4593 (AudioSet top-10)

| file | intent | clap top label | clap top score | warn |
|---|---|---|---|---|
| 01_tear_flesh.wav | wet ripping of raw meat and flesh tearing | balloon deflating | 0.488 | WARN |
| 02_tear_fat.wav | squelchy wet mushing sound of fat tissue being torn | squelchy wet mushing sound of fat tissue being torn | 0.466 | ok |
| 03_tear_nerve.wav | tight thin string snapping and twanging | whip crack | 0.653 | WARN |
| 04_tear_membrane.wav | rubbery creak followed by a wet pop of membrane bursting | rubbery creak followed by a wet pop of membrane bursting | 0.975 | ok |
| 05_swallow.wav | a person gulping and swallowing loudly | a person gulping and swallowing loudly | 0.920 | ok |
| 06_stomach_gurgle.wav | human stomach gurgling and rumbling | human stomach gurgling and rumbling | 0.980 | ok |
| 07_chew_loop_a.wav | a person chewing wet food repeatedly | paper crumpling | 0.460 | WARN |
| 08_chew_loop_b.wav | crunchy cartilage chewing with occasional clicks | footsteps on gravel | 0.468 | WARN |
| 09_chew_strain.wav | a person straining and grunting while swallowing with nasal breathing | cattle bellowing | 0.516 | WARN |
| 10_vomit_toilet.wav | a person vomiting into a toilet with liquid splashing | arcade laser gun shot | 0.989 | WARN |
| 11_vomit_floor.wav | a person vomiting onto a hard floor with splatter | arcade laser gun shot | 0.911 | WARN |
| 12_step_flesh_s1.wav | a single wet squelchy footstep on soft flesh | footstep on wet sand | 0.833 | WARN |
| 13_step_flesh_s3.wav | a heavy wet squelchy footstep on soft flesh with more weight | footstep on wet sand | 0.916 | WARN |
| 14_step_tile_s1.wav | a crisp clicking footstep on hard tile floor | a crisp clicking footstep on hard tile floor | 0.549 | ok |
| 15_step_tile_s3.wav | a heavy footstep on tile with wet flesh residue splatting | footstep on sand | 0.591 | WARN |
| 16_toilet_flush.wav | a toilet flushing with rushing water and swirling drain | a toilet flushing with rushing water and swirling drain | 0.825 | ok |
| 17_canary_warn.wav | a small bird chirping a warning call, pitched up | a small bird chirping a warning call, pitched up | 0.945 | ok |
| 18_canary_wrong.wav | a small bird making a strange distorted warble | a small bird making a strange distorted warble | 1.000 | ok |
| 19_amb_restroom.wav | a restroom ambience with faint ventilation fan hum | white noise | 0.602 | WARN |
| 20_amb_body_a.wav | a low deep ambient rumble inside a body cavity, shallow shell | engine idling | 0.586 | WARN |
| 21_amb_body_b.wav | a low deep ambient rumble inside a body cavity, deep shell | engine idling | 0.527 | WARN |
| 22_depth_marker.wav | a soft musical chime marking depth, with faint background noise | a soft musical chime marking depth, with faint background noise | 0.984 | ok |

## 요약

- 최종 도구 판정: OK 9개, WARN 13개(22개 중). 배경음 예외 3개(19_amb_restroom, 20_amb_body_a, 21_amb_body_b)는 CLAP의 지속음 판정 한계로 청감 우선 유지 대상이라 WARN이어도 문제로 보지 않는다. 남은 진짜 개선 대상 WARN은 10개(01,03,07,08,09,10,11,12,13,15).
- 1단계 대비 2단계에서 05_swallow, 22_depth_marker가 WARN -> OK로 개선됨.
- 나머지 WARN 10개(01,03,07,08,09,10,11,12,13,15)는 real_layer 게인을 최대 +14dB, 합성 출력을 최대 60%까지 축소했음에도 CLAP top-1이 바뀌지 않음. 추가 CC0 녹음이 필요하나 freesound API가 인증 없이 다운로드를 거부해(401) 이번 회차에서는 확보하지 못함.
- 19_amb_restroom, 20/21_amb_body는 형님이 청감상 양호(19)하거나 방향이 맞다고 본 배경음 트랙으로, CLAP이 지속 배경음/드론 분류에 약한 것으로 알려진 한계 영역(README_EAR.md 명시)이라 WARN이어도 청감 우선으로 유지.
- 18_canary_wrong은 형님 지시대로 건드리지 않았고 통과(OK) 상태 유지.
