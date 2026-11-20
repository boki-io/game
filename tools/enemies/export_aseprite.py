#!/usr/bin/env python3
"""Exports an .aseprite file as a one-row sheet PNG plus a JSON of frames and tags (the format build_demon_head.py reads),
for when the Aseprite program is not at hand. Reads RGBA files: visible normal-blend layers, opacity, linked cels, tags
and frame durations. Pure Python (zlib), no Pillow.
usage: python3 tools/enemies/export_aseprite.py <in.aseprite> <out_sheet.png> <out.json>
"""
import json
import struct
import sys
import zlib


def parse(path):
    d = open(path, "rb").read()
    _, magic, nframes, w, h, depth = struct.unpack("<IHHHHH", d[:14])
    assert magic == 0xA5E0 and depth == 32, "needs an RGBA .aseprite"
    pos, layers, tags, frames = 128, [], [], []
    for fi in range(nframes):
        fsize, fmagic, old, dur, _, new = struct.unpack("<IHHH2sI", d[pos:pos + 16])
        chunks = new or old
        p, cels = pos + 16, []
        for _ in range(chunks):
            csize, ctype = struct.unpack("<IH", d[p:p + 6])
            body = d[p + 6:p + csize]
            if ctype == 0x2004:  # layer
                flags, ltype, child, _, _, blend, opacity = struct.unpack("<HHHHHHB", body[:13])
                layers.append({"visible": bool(flags & 1), "type": ltype, "blend": blend, "opacity": opacity, "child": child})
            elif ctype == 0x2005:  # cel
                li, x, y, op, ct = struct.unpack("<HhhBH", body[:9])
                if ct == 1:
                    cels.append({"layer": li, "x": x, "y": y, "op": op, "link": struct.unpack("<H", body[16:18])[0]})
                else:
                    cw, ch = struct.unpack("<HH", body[16:20])
                    raw = body[20:] if ct == 0 else zlib.decompress(body[20:])
                    cels.append({"layer": li, "x": x, "y": y, "op": op, "w": cw, "h": ch, "px": raw})
            elif ctype == 0x2018:  # tags
                n = struct.unpack("<H", body[:2])[0]
                q = 10
                for _ in range(n):
                    a, b, direction = struct.unpack("<HHB", body[q:q + 5])
                    ln = struct.unpack("<H", body[q + 17:q + 19])[0]
                    tags.append({"name": body[q + 19:q + 19 + ln].decode(), "from": a, "to": b, "direction": ["forward", "reverse", "pingpong", "pingpong_reverse"][direction]})
                    q += 19 + ln
            p += csize
        frames.append({"duration": dur, "cels": cels})
        pos += fsize
    return w, h, layers, tags, frames


def compose(w, h, layers, frames):
    out = []
    for fi, fr in enumerate(frames):
        img = bytearray(w * h * 4)
        for c in sorted(fr["cels"], key=lambda c: (c["layer"], c["op"])):
            lay = layers[c["layer"]]
            if not lay["visible"] or lay["type"] != 0 or lay["blend"] != 0:
                continue
            src = c
            if "link" in c:
                src = next(k for k in frames[c["link"]]["cels"] if k["layer"] == c["layer"] and "px" in k)
            for y in range(src["h"]):
                py = c["y"] + y
                if not 0 <= py < h:
                    continue
                for x in range(src["w"]):
                    px = c["x"] + x
                    if not 0 <= px < w:
                        continue
                    i = (y * src["w"] + x) * 4
                    r, g, b, a = src["px"][i:i + 4]
                    a = a * lay["opacity"] * c["op"] // 65025
                    if a == 0:
                        continue
                    o = (py * w + px) * 4
                    da = img[o + 3]
                    ta = a + da * (255 - a) // 255
                    for k, s in enumerate((r, g, b)):
                        img[o + k] = (s * a + img[o + k] * da * (255 - a) // 255) // ta
                    img[o + 3] = ta
        out.append(bytes(img))
    return out


def png(w, h, rgba):
    def chunk(t, b):
        c = struct.pack(">I", len(b)) + t + b
        return c + struct.pack(">I", zlib.crc32(t + b) & 0xFFFFFFFF)
    rows = b"".join(b"\x00" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


def main():
    src, sheet, js = sys.argv[1:4]
    w, h, layers, tags, frames = parse(src)
    imgs = compose(w, h, layers, frames)
    n = len(imgs)
    rgba = bytearray(w * n * h * 4)
    for i, img in enumerate(imgs):
        for y in range(h):
            o = (y * w * n + i * w) * 4
            rgba[o:o + w * 4] = img[y * w * 4:(y + 1) * w * 4]
    open(sheet, "wb").write(png(w * n, h, bytes(rgba)))
    meta = {"frames": [{"filename": f"{i}", "frame": {"x": i * w, "y": 0, "w": w, "h": h}, "duration": fr["duration"]} for i, fr in enumerate(frames)],
            "meta": {"size": {"w": w * n, "h": h}, "frameTags": tags}}
    json.dump(meta, open(js, "w"), indent=1)
    print(f"{n} frames of {w}x{h}; tags:", [(t["name"], t["from"], t["to"], t["direction"]) for t in tags])
    print("durations:", [fr["duration"] for fr in frames])


main()
