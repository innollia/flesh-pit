"""Zip up addons/flesh_dig_kit for sharing, versioned from plugin.cfg.

Usage (from game/):
    python -X utf8 tools/export_kit.py

Writes dist/flesh_dig_kit-<version>.zip at the project root (game/dist/).
"""
from __future__ import annotations

import configparser
import pathlib
import sys
import zipfile

PROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent
KIT_DIR = PROJECT_ROOT / "addons" / "flesh_dig_kit"
DIST_DIR = PROJECT_ROOT / "dist"


def read_version() -> str:
    cfg = configparser.ConfigParser()
    cfg.read(KIT_DIR / "plugin.cfg", encoding="utf-8")
    return cfg.get("plugin", "version", fallback="0.0.0")


def main() -> int:
    if not KIT_DIR.is_dir():
        print(f"ERROR: kit directory not found: {KIT_DIR}", file=sys.stderr)
        return 1

    version = read_version()
    DIST_DIR.mkdir(exist_ok=True)
    zip_path = DIST_DIR / f"flesh_dig_kit-{version}.zip"

    file_count = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(KIT_DIR.rglob("*")):
            if path.is_dir():
                continue
            if ".godot" in path.parts:
                continue
            arcname = pathlib.Path("addons") / path.relative_to(KIT_DIR.parent)
            zf.write(path, arcname)
            file_count += 1

    print(f"OK wrote {zip_path} ({file_count} files, version {version})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
