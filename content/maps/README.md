# Maps

One folder per map: `content/maps/<id>/` holds `map.tres` (a `MapTheme`), `thumbnail.png` (64x40) and
`monsters/{grunt,ranged,dasher}.tres`. A leading underscore marks a folder that is not a playable map:
`_default` (today's cave) and `_template` (what new maps are copied from). Spec: `docs/spec-0.6.md` section 3.

## Adding a map

1. `python3 tools/maps/new_map.py <id> "<Display Name>"` copies `_template` to `content/maps/<id>/`, fills in the id
   and name, and appends the id to `MapRegistry.IDS`. Then run `godot --headless --path . --import` (it creates the
   `.import` file for the thumbnail; commit it). The copy has the template's palette, so change it before testing.
2. Open `scenes/dev/map_preview.tscn`, pick the new `map.tres` and edit palette, layout rules and decor weights; the
   preview rebuilds on demand (`L` reloads the files from disk).
3. Edit `monsters/*.tres` for the three monster looks; the preview shows a sample of each.
4. Add the map's colours to `tools/maps/gen_thumbnails.py` and run it to make `thumbnail.png`.
5. Run `tests/run_all.sh`. `map_content.gd`, `map_themes.gd`, `map_layout.gd` and `monster_variants.gd` cover the new
   folder with no test changes, except that the checks that count "eight maps" (`map_content.gd`) must be updated.
6. Review all maps side by side (needs a real renderer, so no `--headless`; a window opens for a few seconds):
   `godot --path . --script tools/maps/shot_maps.gd -- <folder>` writes `<id>.png` (normal zoom), `<id>_full.png`
   (the whole arena), `<id>_monsters.png`, `contact_sheet.png` and `monsters_sheet.png` into `<folder>`
   (`--seed=N` after the folder changes the seed, default 7). Look at the PNGs; pixels are not tested.

## The workbench and the screenshot tool

- `scenes/dev/map_preview.tscn` (F6 in the editor, or `godot --path . scenes/dev/map_preview.tscn`): the map picked in
  the `map` export, built by `MapBuilder` like a run, with the three monsters in a row near the centre. Keys: `Tab`
  next map, `R` new seed, `L` reload the map files from disk, `O` overlay of obstacle footprints and the flow field,
  `Z` whole-arena zoom, arrows pan. Tick `walk` to put a Player in. It reads and writes nothing in `GameSession`.
- `tools/maps/shot_maps.gd` works in `--script` mode: a windowed run does render, into off-screen SubViewports.
