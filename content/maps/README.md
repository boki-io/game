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
6. `godot --headless --path . --script tools/maps/shot_maps.gd -- <folder>` to review all maps side by side.

`scenes/dev/map_preview.tscn` and `tools/maps/shot_maps.gd` come from the same version (v0.6) as this README and
`new_map.py`, but are added in later build steps; until they exist, steps 2 and 6 are not available.
