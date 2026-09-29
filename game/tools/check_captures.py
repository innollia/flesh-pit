"""Capture check that needs no eye: the first-person hands must really be on
screen. tools/capture.gd is run twice (normal, and with `-- nohands`), and
this compares the two sets: pixels that differ by more than a threshold in
the lower 55% of the frame are hand pixels (grain/noise is tiny and fixed-
seed per frame, so it stays under the threshold).

    python tools/check_captures.py <with_hands_dir> <no_hands_dir>
Exit 1 when a stage shows fewer hand pixels than required.
"""
import sys, os
from PIL import Image, ImageChops

NEED = {"01_restroom": 0.02, "03_dug_tunnel": 0.02, "05_hand_grab": 0.06, "08_carry_pile": 0.02}

def hand_frac(a_path, b_path):
    a = Image.open(a_path).convert("RGB")
    b = Image.open(b_path).convert("RGB")
    w, h = a.size
    box = (0, int(h * 0.45), w, h)
    d = ImageChops.difference(a.crop(box), b.crop(box)).convert("L")
    n = sum(1 for v in d.getdata() if v > 40)
    return n / (w * h)

def main():
    with_dir, without_dir = sys.argv[1], sys.argv[2]
    bad = 0
    for s, need in NEED.items():
        f = hand_frac(os.path.join(with_dir, s + ".png"), os.path.join(without_dir, s + ".png"))
        ok = f >= need
        print("%-15s hand pixels %.3f of frame (need >= %.2f) %s" % (s, f, need, "OK" if ok else "FAIL"))
        bad += 0 if ok else 1
    sys.exit(1 if bad else 0)

main()
