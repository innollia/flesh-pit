"""Copies one structure's model and painted atlas into the game.

    python tools/struct_models/install.py <kind> [--src C:/projects/hwapongstuy/texture3d/out]

From <src>/fp_<kind>/: model.glb -> game/main/art/structures/<kind>.glb,
texture.png (1024) -> <kind>.png at 512, prompt.txt -> <kind>.prompt.txt.
"""
import argparse
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DST = ROOT / "game" / "main" / "art" / "structures"


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("kind")
    ap.add_argument("--src", default=r"C:\projects\hwapongstuy\texture3d\out")
    ap.add_argument("--size", type=int, default=512)
    args = ap.parse_args(argv)
    src = Path(args.src) / f"fp_{args.kind}"
    tex = src / "texture.png"
    if not tex.is_file():
        print(f"no painted atlas yet: {tex}")
        return 1
    DST.mkdir(parents=True, exist_ok=True)
    shutil.copy(src / "model.glb", DST / f"{args.kind}.glb")
    Image.open(tex).convert("RGB").resize((args.size, args.size), Image.LANCZOS).save(DST / f"{args.kind}.png")
    if (src / "prompt.txt").is_file():
        text = (src / "prompt.txt").read_text(encoding="utf-8")
        (DST / f"{args.kind}.prompt.txt").write_text(text, encoding="utf-8", newline="\n")
    print("installed", args.kind)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
