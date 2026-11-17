#!/usr/bin/env python3
"""Spec 1.2 migration: moves files to the content/ layout and rewrites every `res://` path that names them.

usage: python3 tools/migrate_content_layout.py <group> [--dry-run]
groups: knight, wizard, archer, enemies_attributes, relics, shared_upgrades

Run from anywhere inside the repo. Every move is `git mv` (with the .uid and .import sidecars). The table below is
explicit: nothing is computed from what is on disk. Deleted again before the PR (spec 1.2, build step 8).
"""
import os
import re
import subprocess
import sys

ROOT = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
os.chdir(ROOT)

CH = "content/characters"


def character(cid, frames_old, abilities, char_upgrades, extra_scripts, sprite_files, raw_sprites=()):
    """abilities: [(ability_id, ability_file, behavior_script_or_None, [upgrade files])]."""
    pairs = [
        (f"data/characters/{cid}.tres", f"{CH}/{cid}/character.tres"),
        (f"data/characters/{frames_old}", f"{CH}/{cid}/frames.tres"),
    ]
    for aid, afile, behavior, ups in abilities:
        base = f"{CH}/{cid}/abilities/{aid}"
        pairs.append((f"data/abilities/{afile}", f"{base}/ability.tres"))
        if behavior:
            pairs.append((f"scripts/abilities/{behavior}", f"{base}/behavior.gd"))
        for u in ups:
            pairs.append((f"data/upgrades/{u}.tres", f"{base}/upgrades/{u}.tres"))
    for u in char_upgrades:
        pairs.append((f"data/upgrades/{u}.tres", f"{CH}/{cid}/upgrades/{u}.tres"))
    for old, new in extra_scripts:
        pairs.append((old, f"{CH}/{cid}/{new}"))
    for f in sprite_files:
        pairs.append((f"assets/sprites/{cid}/{f}", f"{CH}/{cid}/sprites/{f}"))
    for f in raw_sprites:
        pairs.append((f"assets/sprites/{f}", f"{CH}/{cid}/sprites/raw/{f}"))
    return pairs


def strips(cid, names):
    return [f"{cid}_{n}.png" for n in names]


GROUPS = {
    "knight": character(
        "knight", "knight_frames.tres",
        [
            ("slash", "slash.tres", "slash_behavior.gd", ["slash_arc", "slash_damage", "slash_speed"]),
            ("spin", "spin.tres", "spin_behavior.gd", ["spin_cyclone", "spin_double", "spin_wide"]),
            ("slam", "slam.tres", "slam_behavior.gd", ["slam_damage", "slam_shockwave", "slam_stun"]),
            # dash's behavior (DashSlashBehavior) is shared with the Archer and stays in scripts/abilities/
            ("dash", "dash_slash.tres", None, ["dash_chain", "dash_efficient", "dash_range", "dash_trail"]),
        ],
        [], [], strips("knight", ["idle", "walk"]),
        ["Pixel Knight Idle Animation Sheet.png", "walk.png"],
    ),
    "wizard": character(
        "wizard", "wizard_frames.tres",
        [
            # bolt's behavior (BoltBehavior) is shared (ArrowBehavior reads SPREADS) and stays in scripts/abilities/
            ("bolt", "bolt.tres", None, ["bolt_pierce", "bolt_rapid", "bolt_twin"]),
            ("lightning", "lightning.tres", "lightning_behavior.gd", ["lightning_arc", "lightning_jumps", "lightning_stun"]),
            ("meteor", "meteor.tres", "meteor_behavior.gd", ["meteor_radius", "meteor_scorch", "meteor_twin"]),
            ("phase", "phase.tres", "phase_behavior.gd", ["phase_long", "phase_orbs", "phase_swift", "phase_touch"]),
        ],
        [], [("scripts/characters/arcane_focus.gd", "arcane_focus.gd")],
        strips("wizard", ["attack1", "attack2", "death", "hurt", "idle", "lightning", "meteor", "phase", "walk"]),
    ),
    "archer": character(
        "archer", "archer_frames.tres",
        [
            ("arrow", "arrow.tres", "arrow_behavior.gd", ["arrow_pierce", "arrow_rapid", "arrow_twin"]),
            ("dashshot", "dash_shot.tres", "dash_shot_behavior.gd", ["dashshot_chain", "dashshot_range", "dashshot_spray"]),
            ("ricochet", "ricochet.tres", "ricochet_behavior.gd", ["ricochet_bounce", "ricochet_count", "ricochet_hits"]),
            ("arrow_rain", "arrow_rain.tres", "arrow_rain_behavior.gd", ["rain_linger", "rain_radius", "rain_zones"]),
        ],
        ["archer_eagle", "archer_haste"],
        [("scripts/abilities/ricochet_volley.gd", "abilities/ricochet/ricochet_volley.gd")],
        strips("archer", ["attack1", "attack2", "dash", "death", "hurt", "idle", "walk"]),
    ),
    "enemies_attributes": (
        [(f"data/enemies/{n}.tres", f"content/enemies/{n}.tres") for n in ["dasher", "grunt", "ranged", "training_dummy"]]
        + [(f"data/attributes/{n}.tres", f"content/attributes/{n}.tres")
           for n in ["agility", "focus", "fury", "greed", "haste", "might", "recovery", "toughness"]]
    ),
    "relics": [
        pair for n in ["fire_trail", "frost_comet", "storm_orbs", "thorn_nova", "tidal_wave"]
        for pair in [(f"data/relics/{n}.tres", f"content/relics/{n}/relic.tres"),
                     (f"scripts/relics/{n}.gd", f"content/relics/{n}/{n}.gd")]
    ],
    "shared_upgrades": [
        (f"data/upgrades/{n}.tres", f"content/shared/upgrades/{n}.tres")
        for n in ["damage", "max_hp", "move_speed", "pickup_radius", "mana_regen", "max_mana"]
    ],
}

# Folder-level references (a const that names a directory); applied with the files of the group.
DIRS = {
    "knight": [("assets/sprites/knight/", f"{CH}/knight/sprites/")],
    "wizard": [("assets/sprites/wizard/", f"{CH}/wizard/sprites/")],
    "archer": [("assets/sprites/archer/", f"{CH}/archer/sprites/")],
    "enemies_attributes": [("data/enemies/", "content/enemies/")],
}

TEXT_SUFFIXES = (".tres", ".tscn", ".gd", ".md", ".py", ".cfg", ".sh", ".godot")
SKIP = ("docs/spec-", "docs/requirements-", "AGENT_DECISION_LOG.md", "tools/migrate_content_layout.py")


def tracked(path):
    return subprocess.run(["git", "ls-files", "--error-unmatch", path], capture_output=True).returncode == 0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if len(args) != 1 or args[0] not in GROUPS:
        sys.exit(__doc__)
    group = args[0]
    pairs = GROUPS[group]

    moves = []  # (old, new) including sidecars
    problems = []
    for old, new in pairs:
        if not tracked(old):
            problems.append(f"missing source: {old}")
        if os.path.exists(new):
            problems.append(f"target exists: {new}")
        moves.append((old, new))
        for ext in (".uid", ".import"):
            if tracked(old + ext):
                moves.append((old + ext, new + ext))
    if problems:
        sys.exit("\n".join(problems))

    mapping = {f"res://{o}": f"res://{n}" for o, n in pairs}
    for o, n in DIRS.get(group, []):
        mapping[f"res://{o}"] = f"res://{n}"
    pattern = re.compile("|".join(re.escape(k) for k in sorted(mapping, key=len, reverse=True)))

    files = subprocess.check_output(["git", "ls-files"], text=True).splitlines()
    files = [f for f in files if f.endswith(TEXT_SUFFIXES) and not f.startswith(SKIP) and f not in SKIP]
    # the files being moved are rewritten after they move, so map old names to new ones
    moved = dict(moves)

    print(f"{group}: {len(moves)} moves")
    if dry:
        for o, n in moves:
            print(f"  {o} -> {n}")
    else:
        for o, n in moves:
            os.makedirs(os.path.dirname(n), exist_ok=True)
            subprocess.check_call(["git", "mv", o, n])

    changed = 0
    for f in files:
        path = moved.get(f, f)
        if dry:
            path = f
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except (UnicodeDecodeError, FileNotFoundError):
            continue
        new_text = pattern.sub(lambda m: mapping[m.group(0)], text)
        if new_text != text:
            changed += 1
            print(f"  rewrite {path}")
            if not dry:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(new_text)
    print(f"{changed} files rewritten")

    if not dry:
        left = []
        for o, _ in pairs:
            out = subprocess.run(["git", "grep", "-lF", f"res://{o}", "--", "."] + [f":!{s}" for s in SKIP],
                                 capture_output=True, text=True).stdout.split()
            left += [f"{f}: {o}" for f in out]
        if left:
            sys.exit("old paths still named:\n" + "\n".join(left))
        print("no old paths left")


main()
