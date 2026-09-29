# -*- coding: utf-8 -*-
# game/audio/listen/ 22개를 최신 sfx/loops 렌더 결과로 갱신
import shutil, os

GAME_AUDIO = r"C:\Users\fixme\Desktop\flesh-pit-main\game\audio"
LISTEN = os.path.join(GAME_AUDIO, "listen")

pairs = [
    ("01_tear_flesh_v1.wav", "sfx/tear_flesh_v1.wav"),
    ("02_tear_fat_v1.wav", "sfx/tear_fat_v1.wav"),
    ("03_tear_nerve_v1.wav", "sfx/tear_nerve_v1.wav"),
    ("04_tear_membrane_v1.wav", "sfx/tear_membrane_v1.wav"),
    ("05_swallow_v1.wav", "sfx/swallow_v1.wav"),
    ("06_stomach_gurgle_v1.wav", "sfx/stomach_gurgle_v1.wav"),
    ("07_chew_loop_a.wav", "loops/chew_loop_a.wav"),
    ("08_chew_loop_b.wav", "loops/chew_loop_b.wav"),
    ("09_chew_strain.wav", "loops/chew_strain.wav"),
    ("10_vomit_toilet_v1.wav", "sfx/vomit_toilet_v1.wav"),
    ("11_vomit_floor_v1.wav", "sfx/vomit_floor_v1.wav"),
    ("12_step_flesh_s1_v1.wav", "sfx/step_flesh_s1_v1.wav"),
    ("13_step_flesh_s3_v1.wav", "sfx/step_flesh_s3_v1.wav"),
    ("14_step_tile_s1_v1.wav", "sfx/step_tile_s1_v1.wav"),
    ("15_step_tile_s3_v1.wav", "sfx/step_tile_s3_v1.wav"),
    ("16_toilet_flush_v1.wav", "sfx/toilet_flush_v1.wav"),
    ("17_canary_warn_v1.wav", "sfx/canary_warn_v1.wav"),
    ("18_canary_wrong_v1.wav", "sfx/canary_wrong_v1.wav"),
    ("19_amb_restroom.wav", "loops/amb_restroom.wav"),
    ("20_amb_body_a.wav", "loops/amb_body_a.wav"),
    ("21_amb_body_b.wav", "loops/amb_body_b.wav"),
    ("22_depth_marker_v1.wav", "sfx/depth_marker_v1.wav"),
]

ok = 0
for dst_name, src_rel in pairs:
    src = os.path.join(GAME_AUDIO, src_rel)
    dst = os.path.join(LISTEN, dst_name)
    shutil.copyfile(src, dst)
    ok += 1
print("updated listen/", ok, "/", len(pairs))
