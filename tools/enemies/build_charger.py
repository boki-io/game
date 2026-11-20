#!/usr/bin/env python3
"""Writes content/enemies/charger/frames.tres (a SpriteFrames) from the export in art/source/charger/.

The export is charger_sheet.json (made from charger_animation.aseprite by export_aseprite.py: 34 frames of 64x64 in one
row, tags idle, walk, attack, damage, death); the sheet PNG is content/enemies/charger/charger_sheet.png. Each tag
becomes an animation with its drawn durations (a frame's time in 1/FPS units, as build_demon_head.py does), with two
changes: `damage` is named `hurt` (what Enemy plays on a hit), and the one `attack` tag is cut at SPLIT_FRAME into
`windup` (the crouch, frames 10 to 15) and `dash` (the lunge, 16 to 22), the two phases the dasher's brain plays
separately and fits to its own timings. `--check` only compares.
usage: python3 tools/enemies/build_charger.py [--check]
"""
import json
import sys

JSON = "art/source/charger/charger_sheet.json"
SHEET = "res://content/enemies/charger/charger_sheet.png"
OUT = "content/enemies/charger/frames.tres"
FPS = 10.0
LOOPS = {"walk": True, "idle": True}  # every other animation plays once
RENAME = {"damage": "hurt"}
SPLIT_FRAME = 16  # the first frame of the dash


def ranges(tags):
    out = {}
    for tag in tags:
        if tag["name"] == "attack":
            out["windup"] = (tag["from"], SPLIT_FRAME - 1)
            out["dash"] = (SPLIT_FRAME, tag["to"])
        else:
            out[RENAME.get(tag["name"], tag["name"])] = (tag["from"], tag["to"])
    return out


def build() -> str:
    data = json.load(open(JSON))
    frames = data["frames"]
    frames = list(frames.values()) if isinstance(frames, dict) else frames
    lines = ['[gd_resource type="SpriteFrames" format=3]', "",
             f'[ext_resource type="Texture2D" path="{SHEET}" id="t0"]', ""]
    for i, f in enumerate(frames):
        r = f["frame"]
        lines += [f'[sub_resource type="AtlasTexture" id="f{i}"]', "atlas = ExtResource(\"t0\")",
                  f'region = Rect2({r["x"]}, {r["y"]}, {r["w"]}, {r["h"]})', ""]
    blocks = []
    for name, (a, b) in sorted(ranges(data["meta"]["frameTags"]).items()):
        entries = []
        for i in range(a, b + 1):
            dur = round(frames[i]["duration"] / (1000.0 / FPS), 3)
            entries.append('{\n"duration": %s,\n"texture": SubResource("f%d")\n}' % (dur, i))
        blocks.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}'
                      % (", ".join(entries), "true" if LOOPS.get(name, False) else "false", name, FPS))
    lines += ["[resource]", "animations = [" + ", ".join(blocks) + "]", ""]
    return "\n".join(lines)


def main() -> None:
    text = build()
    if "--check" in sys.argv:
        same = open(OUT).read() == text
        print("same" if same else "DIFFERENT")
        sys.exit(0 if same else 1)
    open(OUT, "w").write(text)
    print(f"wrote {OUT}")


main()
