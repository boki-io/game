#!/usr/bin/env python3
"""Writes content/enemies/ranged/frames.tres (a SpriteFrames) from the Aseprite export in art/source/demon-head/.

The export is demon-head_sheet.json (frames with durations and the tags walk, attack, idle, hurt, death) next to
demon-head_animations.aseprite; the sheet PNG is content/enemies/ranged/demon_head_sheet.png (31 frames of 64x64
in one row). Each tag becomes an animation; the frame durations are kept (the animation runs at FPS, a frame's
`duration` is its time in 1/FPS units, as build_slimes.py does for the slimes). `--check` only compares.
usage: python3 tools/enemies/build_demon_head.py [--check]
"""
import json
import sys

JSON = "art/source/demon-head/demon-head_sheet.json"
SHEET = "res://content/enemies/ranged/demon_head_sheet.png"
OUT = "content/enemies/ranged/frames.tres"
FPS = 10.0
LOOPS = {"walk": True, "idle": True}  # every other animation plays once


def build() -> str:
    data = json.load(open(JSON))
    frames = data["frames"]
    frames = list(frames.values()) if isinstance(frames, dict) else frames
    tags = data["meta"]["frameTags"]
    lines = ['[gd_resource type="SpriteFrames" format=3]', "",
             f'[ext_resource type="Texture2D" path="{SHEET}" id="t0"]', ""]
    for i, f in enumerate(frames):
        r = f["frame"]
        lines += [f'[sub_resource type="AtlasTexture" id="f{i}"]', "atlas = ExtResource(\"t0\")",
                  f'region = Rect2({r["x"]}, {r["y"]}, {r["w"]}, {r["h"]})', ""]
    blocks = []
    for tag in sorted(tags, key=lambda t: t["name"]):
        entries = []
        for i in range(tag["from"], tag["to"] + 1):
            dur = round(frames[i]["duration"] / (1000.0 / FPS), 3)
            entries.append('{\n"duration": %s,\n"texture": SubResource("f%d")\n}' % (dur, i))
        blocks.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}'
                      % (", ".join(entries), "true" if LOOPS.get(tag["name"], False) else "false", tag["name"], FPS))
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
