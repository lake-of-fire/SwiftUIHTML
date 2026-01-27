#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path

def run_magick(args):
    candidates = [
        ("/opt/homebrew/bin/magick", True),
        ("magick", True),
        ("/opt/homebrew/bin/convert", False),
        ("convert", False),
    ]
    for tool, uses_magick in candidates:
        cmd = [tool] + (["convert"] if uses_magick else []) + args
        try:
            out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True).strip()
            return out
        except FileNotFoundError:
            continue
        except subprocess.CalledProcessError:
            continue
    return None

def parse_geom(value):
    if not value or "+" not in value or "x" not in value:
        return None
    size, x, y = value.split("+")
    w, h = size.split("x")
    return int(w), int(h), int(x), int(y)

if len(sys.argv) < 2:
    print("usage: measure_margin.py <image.png>")
    sys.exit(2)

path = Path(sys.argv[1])
if not path.exists():
    print(f"missing: {path}")
    sys.exit(1)

info = run_magick([str(path), "-format", "%w %h", "info:"])
trim = run_magick([str(path), "-trim", "-format", "%@", "info:"])
if not info or not trim:
    print("magick output missing")
    sys.exit(1)

w, h = map(int, info.split())
geom = parse_geom(trim)
if not geom:
    print("failed to parse trim geometry")
    sys.exit(1)

trim_w, trim_h, x, y = geom
right = max(0, w - (x + trim_w))
bottom = max(0, h - (y + trim_h))

print(f"image={w}x{h}")
print(f"trim={trim_w}x{trim_h}+{x}+{y}")
print(f"margins top={y} left={x} bottom={bottom} right={right}")
