#!/usr/bin/env python3
"""Builds the grunt slime art of every map from the Aseprite sources.

    python3 tools/slimes/build_slimes.py            write the sheets and SpriteFrames
    python3 tools/slimes/build_slimes.py --check    write nothing; exit 1 if a committed sheet or .tres differs

Reads art/source/slimes/slime_<name>.aseprite (32x32 RGBA, 13 frames; no Aseprite needed: the file is parsed
here, pure stdlib) and writes, into content/maps/<folder>/monsters/:
    grunt_sheet.png    the 13 frames side by side (416x32)
    grunt_frames.tres  a SpriteFrames over that sheet, fed to MonsterVariant.sprite_frames
<name> is the map id, except `cave`, which is the `_default` map.

The tags saved in the .aseprite files overlap (bounce 0-12, hit 4-12, death 8-12), so they are ignored; the
animations are fixed by frame range below (the frames and their durations show the intended split):
    bounce  frames 0-3   loops
    hit     frames 4-7   one shot (white and red flash, then back to the bounce)
    death   frames 8-12  one shot (flattens into a puddle; the last frame holds 600 ms)
Frame times come from the file's per-frame durations: the animation runs at FPS and each frame's `duration`
multiplier is its milliseconds / (1000 / FPS), so 120 ms is 1.2.
"""
import os
import struct
import sys
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SOURCE = os.path.join(ROOT, "art", "source", "slimes")
MAPS = os.path.join(ROOT, "content", "maps")
NAMES = ["cave", "bone_warren", "crystal_vault", "ember_depths", "flooded_gallery", "frostbite_grotto",
         "mossy_hollow", "spore_cavern", "sulfur_pits"]
FOLDER_OF = {"cave": "_default"}
SIZE = 32
FRAME_COUNT = 13
FPS = 10.0
ANIMATIONS = [("bounce", 0, 3, True), ("hit", 4, 7, False), ("death", 8, 12, False)]


def read_aseprite(path):
    """(width, height, [RGBA bytes per frame], [duration in ms per frame]) of a 32 bit RGBA .aseprite file.
    Cels of all layers are drawn in file order (the slime files have one visible layer)."""
    with open(path, "rb") as f:
        d = f.read()
    _, _, frames, w, h, depth = struct.unpack_from("<IHHHHH", d, 0)
    if depth != 32:
        raise SystemExit("%s: colour depth %d, only RGBA (32) is supported" % (path, depth))
    off = 128
    imgs, durs = [], []
    for _ in range(frames):
        fsize, _, old_chunks, dur = struct.unpack_from("<IHHH", d, off)
        chunks = struct.unpack_from("<I", d, off + 12)[0] or old_chunks
        durs.append(dur)
        buf = bytearray(w * h * 4)
        pos = off + 16
        for _ in range(chunks):
            csize, ctype = struct.unpack_from("<IH", d, pos)
            if ctype == 0x2005:  # cel
                _, x, y, _, cel_type = struct.unpack_from("<HhhBH", d, pos + 6)
                p = pos + 6 + 16
                cw, chh = struct.unpack_from("<HH", d, p)
                p += 4
                data = d[p:pos + csize]
                if cel_type == 2:
                    data = zlib.decompress(data)
                for row in range(chh):
                    for col in range(cw):
                        if 0 <= y + row < h and 0 <= x + col < w:
                            s = (row * cw + col) * 4
                            if data[s + 3]:
                                o = ((y + row) * w + x + col) * 4
                                buf[o:o + 4] = data[s:s + 4]
            pos += csize
        imgs.append(bytes(buf))
        off += fsize
    return w, h, imgs, durs


def write_png(w, h, rgba):
    raw = b"".join(b"\x00" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))

    def chunk(t, body):
        return struct.pack(">I", len(body)) + t + body + struct.pack(">I", zlib.crc32(t + body) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def sheet_png(imgs, w, h):
    n = len(imgs)
    sheet = bytearray(w * n * h * 4)
    for i, im in enumerate(imgs):
        for y in range(h):
            sheet[(y * w * n + i * w) * 4:(y * w * n + i * w + w) * 4] = im[y * w * 4:(y + 1) * w * 4]
    return write_png(w * n, h, sheet)


def frames_tres(folder, durs, w, h):
    texture = "res://content/maps/%s/monsters/grunt_sheet.png" % folder
    out = ['[gd_resource type="SpriteFrames" format=3]', "",
           '[ext_resource type="Texture2D" path="%s" id="t0"]' % texture, ""]
    for i in range(FRAME_COUNT):
        out += ['[sub_resource type="AtlasTexture" id="f%d"]' % i, 'atlas = ExtResource("t0")',
                "region = Rect2(%d, 0, %d, %d)" % (i * w, w, h), ""]
    out += ["[resource]", "animations = ["]
    blocks = []
    for name, first, last, loop in ANIMATIONS:
        frames = ", ".join('{\n"duration": %s,\n"texture": SubResource("f%d")\n}' % (round(durs[i] / (1000.0 / FPS), 3), i)
                           for i in range(first, last + 1))
        blocks.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}'
                      % (frames, "true" if loop else "false", name, FPS))
    out.append(", ".join(blocks))
    out += ["]", ""]
    return "\n".join(out)


def outputs():
    """{path: bytes} of everything the script owns."""
    result = {}
    for name in NAMES:
        src = os.path.join(SOURCE, "slime_%s.aseprite" % name)
        w, h, imgs, durs = read_aseprite(src)
        if (w, h, len(imgs)) != (SIZE, SIZE, FRAME_COUNT):
            raise SystemExit("%s: %dx%d with %d frames, expected %dx%d with %d" % (src, w, h, len(imgs), SIZE, SIZE, FRAME_COUNT))
        folder = os.path.join(MAPS, FOLDER_OF.get(name, name), "monsters")
        result[os.path.join(folder, "grunt_sheet.png")] = sheet_png(imgs, w, h)
        result[os.path.join(folder, "grunt_frames.tres")] = frames_tres(FOLDER_OF.get(name, name), durs, w, h).encode()
    return result


def main():
    check = "--check" in sys.argv[1:]
    stale = []
    for path, data in sorted(outputs().items()):
        rel = os.path.relpath(path, ROOT)
        current = open(path, "rb").read() if os.path.isfile(path) else None
        if current == data:
            continue
        stale.append(rel)
        if not check:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
            print("wrote", rel)
    if check:
        for rel in stale:
            print("differs:", rel)
        sys.exit(1 if stale else 0)
    print("up to date" if not stale else "run godot --headless --path . --import and commit the .import files")


main()
