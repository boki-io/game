#!/usr/bin/env python3
"""Scaffolds a map: python3 tools/maps/new_map.py <id> "<Display Name>"

Copies content/maps/_template/ to content/maps/<id>/, fills in the id and display name (and the res:// paths that
name the folder), and appends the id to MapRegistry.IDS. Generates nothing else: the thumbnail is the template's
until you add the map to gen_thumbnails.py. Pure stdlib (spec 0.6 section 3.5)."""
import os
import re
import shutil
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
MAPS = os.path.join(ROOT, "content", "maps")
REGISTRY = os.path.join(ROOT, "scripts", "maps", "map_registry.gd")


def fail(msg):
    print("error:", msg, file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 3:
        fail('usage: new_map.py <id> "<Display Name>"')
    map_id, name = sys.argv[1], sys.argv[2].strip()
    if not re.fullmatch(r"[a-z][a-z0-9]*(_[a-z0-9]+)*", map_id):
        fail("id must be lowercase snake_case (letters, digits, single underscores), not starting with _ or a digit")
    if not name or '"' in name or "\\" in name or "\n" in name:
        fail("display name must be non-empty and contain no quotes or backslashes")
    dest = os.path.join(MAPS, map_id)
    if os.path.exists(dest):
        fail("content/maps/%s already exists" % map_id)
    with open(REGISTRY) as f:
        registry = f.read()
    match = re.search(r"const IDS := \[(.*?)\n\]", registry, re.S)
    if not match:
        fail("could not find the IDS list in scripts/maps/map_registry.gd")
    if '"%s"' % map_id in match.group(1):
        fail("%s is already in MapRegistry.IDS" % map_id)
    # Names are unique (map_content.gd checks): refuse a duplicate display name.
    for other in os.listdir(MAPS):
        path = os.path.join(MAPS, other, "map.tres")
        if not other.startswith("_") and os.path.isfile(path):
            with open(path) as f:
                if 'display_name = "%s"' % name in f.read():
                    fail('display name "%s" is already used by %s' % (name, other))

    # .import files are not copied: Godot makes new ones (with their own uid) on the next import.
    shutil.copytree(os.path.join(MAPS, "_template"), dest, ignore=shutil.ignore_patterns("*.import", "*.uid"))
    for folder, _, files in os.walk(dest):
        for fn in files:
            if fn.endswith(".tres"):
                path = os.path.join(folder, fn)
                with open(path) as f:
                    text = f.read()
                text = text.replace("res://content/maps/_template/", "res://content/maps/%s/" % map_id)
                text = text.replace('id = &"_template"', 'id = &"%s"' % map_id)
                text = text.replace('display_name = "Template Map"', 'display_name = "%s"' % name)
                with open(path, "w") as f:
                    f.write(text)

    body = match.group(1)
    registry = registry[:match.start(1)] + body + '\n\t"%s",' % map_id + registry[match.end(1):]
    with open(REGISTRY, "w") as f:
        f.write(registry)
    print("created content/maps/%s and added it to MapRegistry.IDS" % map_id)
    print("next: godot --headless --path . --import, then see content/maps/README.md")


main()
