# Maps

One folder per map: `content/maps/<id>/` holds `map.tres` (a `MapTheme`), `thumbnail.png` (64x40) and
`monsters/{grunt,ranged,dasher}.tres`. The grunt's `monsters/` also holds `grunt_sheet.png` (13 frames of 32x32) and
`grunt_frames.tres` (a SpriteFrames over it), which `grunt.tres` names in `sprite_frames`; see "Slimes" below. A leading underscore marks a folder that is not a playable map:
`_default` (today's cave, whose `monsters/` holds only the grunt: no stage means this map) and `_template` (what new maps are copied from). Spec: `docs/spec-0.6.md` section 3.

## Adding a map

1. `python3 tools/maps/new_map.py <id> "<Display Name>"` copies `_template` to `content/maps/<id>/`, fills in the id
   and name, and appends the id to `MapRegistry.IDS`. Then run `godot --headless --path . --import` (it creates the
   `.import` file for the thumbnail; commit it). The copy has the template's palette, so change it before testing.
2. Open `scenes/dev/map_preview.tscn`, pick the new `map.tres` and edit palette, layout rules and decor weights; the
   preview rebuilds on demand (`L` reloads the files from disk).
3. Edit `monsters/*.tres` for the three monster looks; the preview shows a sample of each. The template's grunt has no
   `sprite_frames`, so a new map shows the drawn placeholder grunt until it gets a slime (see "Slimes").
4. Add the map's colours to `tools/maps/gen_thumbnails.py` and run it to make `thumbnail.png`.
5. Run `tests/run_all.sh`. `map_content.gd`, `map_themes.gd`, `map_layout.gd` and `monster_variants.gd` cover the new
   folder with no test changes (the count checks ask for at least eight maps and for a theme per registry id). `map_themes.gd` fails on a fresh copy until the map has its own palette and layout or decor (it must differ from every other map), which is meant.
6. Review all maps side by side (needs a real renderer, so no `--headless`; a window opens for a few seconds):
   `godot --path . --script tools/maps/shot_maps.gd -- <folder>` writes `<id>.png` (normal zoom), `<id>_full.png`
   (the whole arena), `<id>_monsters.png`, `contact_sheet.png` and `monsters_sheet.png` into `<folder>`
   (`--seed=N` after the folder changes the seed, default 7). Look at the PNGs; pixels are not tested.

## Ambient life

Each `map.tres` has an "Ambience" group (spec v0.9 section 3): `ambience_kind` (`0` none, `1` dust, `2` embers, `3` spores, `4` frost,
`5` glint), `ambience_color` (its alpha is ignored; the kind sets it) and `ambience_count` (0 to 80 motes alive at once). The kind is
the motion: dust drifts sideways, embers rise and flicker, spores wander, frost falls, glints twinkle in place. The motes are drawn by
`Ambience` (`scripts/systems/ambience.gd`) in the world, apart from the hit-effect particles. A new map starts with the template's warm
dust; pick a kind and a colour that suit it. `ambience.gd` checks every map's kind, colour and count against the table in the spec.

## The workbench and the screenshot tool

- `scenes/dev/map_preview.tscn` (F6 in the editor, or `godot --path . scenes/dev/map_preview.tscn`): the map picked in
  the `map` export, built by `MapBuilder` like a run, with the three monsters in a row near the centre. Keys: `Tab`
  next map, `R` new seed, `L` reload the map files from disk, `O` overlay of obstacle footprints and the flow field,
  `Z` whole-arena zoom, arrows pan. Tick `walk` to put a Player in. It reads and writes nothing in `GameSession`.
- `tools/maps/shot_maps.gd` works in `--script` mode: a windowed run does render, into off-screen SubViewports.

## Slimes (the drawn grunt)

The grunt is drawn art, one slime per map: `art/source/slimes/slime_<name>.aseprite` (32x32, 13 frames; `<name>` is
the map id, `cave` is `_default`). `python3 tools/slimes/build_slimes.py` parses them (no Aseprite needed) and writes
each map's `monsters/grunt_sheet.png` and `monsters/grunt_frames.tres`; `--check` only compares. Run
`godot --headless --path . --import` afterwards and commit the `.import` files. The animations come from frame ranges, not
from the tags saved in the files (those overlap): `bounce` 0-3 (loops), `hit` 4-7 and `death` 8-12 (one shots), each frame
lasting the file's duration. To give a new map a slime: add `slime_<id>.aseprite` and its id to `NAMES` in the script, run
it, then set `sprite_frames` of the map's `grunt.tres` to `grunt_frames.tres` (Inspector, or an `ext_resource` line like
the other maps). The dasher stays drawn in code. The ranged enemy has art on every map: the demon head, set on its `EnemyData` (`content/enemies/ranged/`, see below); a variant without `sprite_frames` keeps it. `tests/maps/slime_sprites.gd` checks all of it.

## The demon head (the ranged enemy's art)

`content/enemies/ranged/` holds the Ranged enemy's drawn art for every map: `demon_head_sheet.png` (31 frames of 64x64
in one row), `frames.tres` (a `SpriteFrames`) and, in `art/source/demon-head/`, the Aseprite file and its JSON export.
`python3 tools/enemies/build_demon_head.py` rebuilds `frames.tres` from the JSON (animations come from the frame tags
`walk`, `attack`, `idle`, `hurt`, `death`; the drawn frame times are kept; `--check` only compares). `ranged.tres` names the
frames and sets `art_scale`, `art_offset` and `art_faces_left`. Animations: `idle` and `walk` loop, `attack` plays when a shot
winds up (its glow frame lands at the 0.4 s shot), `hurt` on damage, `death` as a corpse. A map's ranged `MonsterVariant`
needs no `sprite_frames`: it keeps this art. `tests/enemy_demon_head.gd` checks all of it.
