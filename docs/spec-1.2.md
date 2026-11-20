# Spec v1.2: Content layout (a folder per character, ability and relic)

Builds on spec v1.1 (merged, PR #11, `main` at `9761712`: the Archer) and on the map layout of spec v0.6 (`content/maps/<id>/`). Status: built (rev 3 records the build's deviations in section 14); rev 2 (rev 2 applies an independent review: two test assertions that change, `SteadyAim` stays in `scripts/`, template scripts without `class_name`, wider greps and docs list, a split build step 6, corrected cross-references). A **refactor**: no gameplay, number, scene or save change.

Terms: **content** is a game data file (`.tres`) plus the small script or art that belongs to exactly one item. **Engine** is code that serves many items (bases, registries, systems, UI). An **owner** is the character an ability or upgrade belongs to. A **shared** item is used by more than one character.

## Flow

A developer adding a character, ability or upgrade works in one folder: `content/characters/<id>/` holds the character's data, trait, art, and one folder per ability with that ability's behavior script and its upgrades. Players see no change. The game, the saves and every test behave as before; only paths move.

## 1. Scope

In scope:
- `data/characters`, `data/abilities`, `data/upgrades`, `data/enemies`, `data/relics`, `data/attributes` move under `content/` (section 2); `data/` disappears.
- Per-ability behavior scripts, per-character scripts (trait) and per-relic behavior scripts move next to their data (section 3).
- Character sprites move into the character's folder (section 4).
- `CharacterRegistry`, `RelicRegistry`, `AttributeRegistry`, `scenes/main.tscn`, `scenes/dev/map_preview.gd`, `tools/prepare_knight_sprites.gd`, the tests and the docs that name a moved path are updated (section 6).
- A path-rewriting migration script, a template character, `content/characters/README.md` and a new test that loads all content (sections 7 to 9).

Out of scope (decided): changing any number, id, display text or behavior; folder-scanning registries (section 5); moving enemy brains (section 3); moving `assets/audio`, `assets/32x32.png`, `assets/ui`; moving `scripts/` subsystems (`systems`, `ui`, `player`, `maps`, `stages`, `hub`); renaming any `class_name`; rewriting the text of earlier specs (they keep the paths of their day; the README says so).

Out of scope (later): a per-character sound folder (`assets/audio` is flat and `Audio.SOUNDS` lists names; see O3); ability icons per ability folder once real icons exist (today they are atlas regions of `assets/32x32.png`); an ability or upgrade created by a tool like `tools/maps/new_map.py`.

## 2. The new layout

Verified against `main`: 12 ability files, 46 upgrade files, 3 characters with 3 `*_frames.tres`, 4 enemy files, 5 relic files, 8 attribute files; Knight, Wizard and Archer pools share six upgrades (`damage`, `max_hp`, `move_speed`, `pickup_radius` in all three; `mana_regen`, `max_mana` in Knight and Wizard only).

```
content/
  characters/
    README.md                       how to add a character, ability, upgrade
    _template/                      a complete example to copy (excluded from exports; its scripts have no class_name, section 8)
    knight/
      character.tres                was data/characters/knight.tres
      frames.tres                   was data/characters/knight_frames.tres
      sprites/                      was assets/sprites/knight/ (+ the two raw sheets, section 4)
      upgrades/                     passives only this character has (not created for the Knight or Wizard: git does not track an empty folder)
      abilities/
        slash/        ability.tres  upgrades/{slash_arc,slash_damage,slash_speed}.tres
                      behavior.gd   was scripts/abilities/slash_behavior.gd
        spin/         ability.tres  behavior.gd  upgrades/{spin_cyclone,spin_double,spin_wide}.tres
        slam/         ability.tres  behavior.gd  upgrades/{slam_damage,slam_shockwave,slam_stun}.tres
        dash/         ability.tres  upgrades/{dash_chain,dash_efficient,dash_range,dash_trail}.tres
                      (its behavior, DashSlashBehavior, is shared: section 3)
    wizard/
      character.tres  frames.tres  sprites/  arcane_focus.gd (the trait)
      abilities/{bolt,lightning,meteor,phase}/   same shape; bolt's behavior is shared (section 3)
    archer/
      character.tres  frames.tres  sprites/       (its trait, SteadyAim, stays in scripts/characters/, section 3)
      upgrades/{archer_haste,archer_eagle}.tres
      abilities/{arrow,dashshot,ricochet,arrow_rain}/   same shape; ricochet/ also holds ricochet_volley.gd
  shared/
    upgrades/{damage,max_hp,move_speed,pickup_radius,mana_regen,max_mana}.tres
  enemies/    {grunt,ranged,dasher,training_dummy}.tres          (flat: data only, section 3)
  attributes/ {agility,focus,fury,greed,haste,might,recovery,toughness}.tres   (flat)
  relics/
    fire_trail/   relic.tres  fire_trail.gd
    frost_comet/  relic.tres  frost_comet.gd
    storm_orbs/   relic.tres  storm_orbs.gd
    thorn_nova/   relic.tres  thorn_nova.gd
    tidal_wave/   relic.tres  tidal_wave.gd
  maps/       (unchanged)
```

Rules:
- **Folder name = the item's folder id.** For a character it is its `id`. For an ability folder it is the **ability `id`** where that is a valid folder name: `arrow_rain`, `ricochet`, `slash` and so on; the two ids that differ from their files today are `dash` (file `dash_slash.tres`, folder `dash`) and `dashshot` (file `dash_shot.tres`, folder `dashshot`). Resource ids inside files do **not** change (stat keys, saves and tests depend on them).
- **File names are fixed per type** (`character.tres`, `frames.tres`, `ability.tres`, `behavior.gd`, `relic.tres`), so a path is predictable and a tool can find them. Upgrades keep their current file names (`arrow_twin.tres`), so an upgrade id still equals its file name; the test fixture relies on that (section 6).
- **An upgrade lives with what it upgrades.** Per-ability upgrades go in `abilities/<ability>/upgrades/`; passives that only one character has go in `<character>/upgrades/`; upgrades used by two or more characters go in `content/shared/upgrades/`. Whether an upgrade belongs to an ability is read from its stat key prefix (`slam.damage` belongs to `slam`), which is why every ability-keyed upgrade has a unique owner today (checked: every ability-keyed upgrade's key prefix equals its ability id, in `adds` and `mults`; the exceptions are in section 10).
- A character's `upgrade_pool` still lists upgrades explicitly, by path, in its `character.tres`; shared upgrades are referenced from there like any other.

## 3. Which scripts move, and which stay

Rule: a script moves into `content/` only if **exactly one** content item uses it **and nothing else names it by path**. Everything else is engine and stays in `scripts/`.

Moves (all keep their `class_name`, so no code that uses the class changes; verified that `scripts/**` and `scenes/**` reference these scripts only by `class_name` or from a `.tres`, except the preloads in section 6):

| From | To |
|---|---|
| `scripts/abilities/slash_behavior.gd`, `spin_behavior.gd`, `slam_behavior.gd` | `content/characters/knight/abilities/{slash,spin,slam}/behavior.gd` |
| `scripts/abilities/lightning_behavior.gd`, `meteor_behavior.gd`, `phase_behavior.gd` | `content/characters/wizard/abilities/{lightning,meteor,phase}/behavior.gd` |
| `scripts/abilities/arrow_behavior.gd`, `dash_shot_behavior.gd`, `arrow_rain_behavior.gd`, `ricochet_behavior.gd` | `content/characters/archer/abilities/{arrow,dashshot,arrow_rain,ricochet}/behavior.gd` |
| `scripts/abilities/ricochet_volley.gd` | `content/characters/archer/abilities/ricochet/ricochet_volley.gd` (only `RicochetBehavior` creates it) |
| `scripts/characters/arcane_focus.gd` | `content/characters/wizard/arcane_focus.gd` (the Wizard's trait; only tests name it, by `get_global_name()`) |
| `scripts/relics/{fire_trail,frost_comet,storm_orbs,thorn_nova,tidal_wave}.gd` | `content/relics/<id>/<id>.gd` |

Stays in `scripts/` (engine, or shared):
- `scripts/abilities/`: `ability_behavior.gd`, `ability_caster.gd`, `ability_data.gd`, `player_projectile.gd`, and the two **shared bases** `dash_slash_behavior.gd` and `bolt_behavior.gd`. `DashShotBehavior` (Archer) extends `DashSlashBehavior` (Knight) and `ArrowBehavior` reads `BoltBehavior.SPREADS` (Wizard); a behavior another character depends on would otherwise make one character's folder import another's. `dash/ability.tres` and `bolt/ability.tres` therefore point at the scripts in `scripts/abilities/`, and the README of `content/characters` says why (O1).
- `scripts/characters/`: `character_data.gd`, `character_registry.gd` and **`steady_aim.gd`**: engine code uses `SteadyAim` (`player_projectile.gd` lines 31, 37, 48, 94 read `SteadyAim.FULL_DISTANCE` and `multiplier`; `arrow_behavior.gd`, `dash_shot_behavior.gd` and `ricochet_volley.gd` call it), so it is shared like the bases above (O8). `scripts/relics/`: `relic_data.gd`, `relic_behavior.gd`, `relic_registry.gd`, `player_relics.gd`, `level_up_roller.gd`. `scripts/camp/`, `scripts/upgrades/`: unchanged.
- `scripts/enemy/`: **all of it**, including `grunt_brain.gd`, `ranged_brain.gd`, `dasher_brain.gd`, `dummy_brain.gd`. Verified: enemies are plain `Node2D`s and `Enemy` picks a brain by `EnemyData` class, and `tests/maps/*` list `data/enemies/` with `DirAccess`; the four `.tres` are data only. Enemies and attributes stay **flat** (`content/enemies/*.tres`, `content/attributes/*.tres`) because a folder each would hold a single file (O2).

## 4. Art

- `assets/sprites/<character>/*.png` and their `.import` files move with `git mv` to `content/characters/<character>/sprites/`. The `frames.tres` files point at them by path (verified: no `uid=` in the three `*_frames.tres`), so the path inside each is rewritten.
- The two raw Knight sheets (`assets/sprites/Pixel Knight Idle Animation Sheet.png`, `assets/sprites/walk.png`) move to `content/characters/knight/sprites/raw/`. They are inputs of `tools/prepare_knight_sprites.gd`, whose `OUT_DIR`, `FRAMES_PATH` and the two source paths are updated; it must still write the same `knight_*.png` files (checked in build step 9 by running the tool and expecting no change in `git status`).
- `assets/sprites/.gitkeep` is removed with the folder if it ends up empty. `assets/` keeps `audio/`, `ui/` and `32x32.png`; `art/source/` (aseprite sources of the slimes) is untouched.
- Moving a `.png` regenerates its `.import`. Each `.png.import` is moved with its `.png` by `git mv` (its `uid` stays, which keeps any uid reference valid), then `godot --headless --path . --import` is run. `.import` files left pointing at an old source path are deleted (CLAUDE.md).

## 5. Registries

Verified: all four lists are explicit (`CharacterRegistry.PATHS`, `RelicRegistry`, `AttributeRegistry`, `MapRegistry`), with the comment that exported builds need explicit paths.
- Each registry keeps its explicit list with the new paths. No folder scanning at runtime (`DirAccess` on `res://` in an export sees `.remap` files and skips resources that are not referenced; the explicit list is what guarantees they are exported).
- The `export_presets.cfg` `exclude_filter` gets `content/characters/_template/*` next to the map template.
- The one place that **does** scan folders is the new content test (section 8), which is not exported.

## 6. Everything that names a moved path

Found with `git grep` on `main` (the migration script rewrites them, then the greps in the Definition of Done (section 13) must find nothing under the old paths):
- **`.tres` files**: every `ext_resource` of an ability, upgrade, character, frames, relic or script that moves (the characters' `upgrade_pool` lines, `ability_*` and `trait_script`, the frames' textures, each ability's `behavior`, each relic's `behavior`). Resource `id`s do not change.
- **`scenes/main.tscn`** (lines 20 to 22, three enemy resources), **`scenes/dev/map_preview.gd`** (`ENEMY_PATHS`), **`scripts/hub.gd`** (`DUMMY_DATA`), **`scripts/camp/attribute_registry.gd`**, **`scripts/characters/character_registry.gd`**, **`scripts/relics/relic_registry.gd`**.
- **Tests** (13 files). Direct paths (10): `archer_arrow_dash`, `archer_ricochet_rain`, `audio_layers`, `dasher_lane`, `gold`, `run_progress`, `wizard_animations`, `maps/slime_sprites`, `maps/map_content`, `maps/monster_variants`. `tests/archer_arrows.gd` preloads `steady_aim.gd`, which does not move, so it is unchanged. **Two assertions change**: `archer_arrow_dash.gd:46` and `:51` check `resource_path.ends_with("/arrow_behavior.gd")` and `"/dash_shot_behavior.gd"`; they become `ends_with("/arrow/behavior.gd")` and `ends_with("/dashshot/behavior.gd")`. The `.tres` names in that file's messages (`dash_shot.tres`) and in `archer_ricochet_rain.gd:9-10` (`ricochet.tres`, `arrow_rain.tres`) are rewritten to `.../ability.tres`. Comments that say `data/enemies/` (`fixture.gd:27`, `maps/map_content.gd:26`) are edited by hand. `tests/fixture.gd` (the 3rd file, with `archer_upgrades.gd`) and `archer_upgrades.gd` load an upgrade **by id** as `res://data/upgrades/%s.tres`; there is no folder for "all upgrades" any more, so `fixture.gd` gets `static func upgrade_path(id: String) -> String` that scans `content/**/upgrades/` once (cached; until build step 6 it also scans `data/upgrades/`) and returns the path, and both use it. Fixed paths of tests for engine scripts that stay (`ability_behavior.gd`, `level_up_roller.gd`, `enemy_status.gd`, `character_registry.gd`) do not change.
- **Docs**, partly by hand (the script only rewrites `res://` strings): `README.md` (lines 46, 50, 62 to 64 and "Adding things" 84 to 87, which say `data/relics`, `data/characters`, `data/enemies`, `data/upgrades`), **`CLAUDE.md`** ("Tuning and content are data (`data/**/*.tres`, soon `content/`)" becomes `content/**`; the user approves this edit by approving the spec), the new `content/characters/README.md` and one new row in `tests/README.md` (no existing row names a moved path). Earlier `docs/spec-*.md` keep their original paths; a line is added to `README.md` saying older specs name pre-1.2 paths and mapping them in one sentence.
- **Tool**: `tools/prepare_knight_sprites.gd` (section 4).

`scenes/main_menu.tscn` and `.claude/` are untracked in the working tree, are not part of this work and are never committed or touched (`main_menu.tscn` points at a script that does not exist). All path searches in this spec use `git grep` (the untracked `.claude/worktrees/` hold full repo copies).

Not affected (verified): `project.godot` (main scene is `scenes/hub.tscn`), `scripts/systems/save_game.gd` (saves hold attribute ids and gold, never paths), `tests/run_all.sh` (globs `tests/`), `.uid` files (a `.gd.uid` moves with its script by `git mv`).

## 7. The migration script

`tools/migrate_content_layout.py` (a build tool: committed in step 2 and deleted in step 8, before the PR is raised, so it cannot run twice):
1. Reads one table (`OLD -> NEW`, built from the lists in sections 2 to 4, explicit, not computed) and refuses to run if an `OLD` is missing or a `NEW` exists.
2. Runs `git mv` for each pair (plus the `.uid` and `.import` sidecars).
3. Rewrites every occurrence of an old `res://` path in all tracked text files (`.tres .tscn .gd .md .py .cfg`), quoting paths with spaces (the `Pixel Knight Idle Animation Sheet.png` sheet and its `.import`), outside `docs/spec-*.md`, `docs/requirements-*.md` and `AGENT_DECISION_LOG.md`, longest path first so that `…/dash_slash.tres` is not hit by a shorter prefix.
4. Prints the files it changed and a count, and exits non-zero on any unmapped old path left in a file it was told to rewrite.
It is run per character in separate commits (the build order, section 9), so the table is split the same way.

## 8. The new test

`tests/content_load.gd` (row added to `tests/README.md`): walks `content/` with `DirAccess` (skipping `maps`, which `map_content.gd` covers) and checks that
- the **template** is loaded explicitly: `_template` is exempt from the orphan, unique-id and pool rules below (its ids repeat real ones), but its `character.tres` and everything it names must load. The template's behavior scripts have **no `class_name`** and `extend AbilityBehavior`, so a copy never duplicates a global class; its README step says to add one if wanted;
- every `.tres` loads, and every `ext_resource` it names exists (a missing one prints the file);
- every character in `CharacterRegistry.all()` has all four abilities, each ability has a `behavior`, and each `ability.tres` lies in `content/characters/<character id>/abilities/<ability id>/` or names a shared base (the two exceptions listed in the test);
- upgrade ids are unique across `content/`, and each upgrade in a pool exists once;
- each per-ability upgrade's stat keys start with the id of its folder's ability; each `shared/` upgrade is in the pool of at least two characters; each `<character>/upgrades/` upgrade is in only that character's pool;
- no upgrade, ability, relic or attribute file exists that nothing registers (an orphan): every `.tres` under `abilities/*/upgrades/`, `upgrades/` and `shared/upgrades/` is in some `upgrade_pool`, every relic in `RelicRegistry`, every attribute in `AttributeRegistry`. (Today the pools use all 46 upgrades; verified by the counts in section 10.) A per-ability upgrade's key check covers `adds` and `mults` (`phase_orbs` has two keys, both `phase.*`). The two shared-base exceptions are listed in the test.

## 9. Build order

One commit per step, tests run after each (`tests/run_all.sh`), `git status` checked before each commit.
1. **Test first**: add `tests/content_load.gd` and `Fixture.upgrade_path`, pointed at the *old* layout where needed (`content/` does not exist for characters yet), so the whole suite is green before any move. (The new test is expected to skip the folder rules until step 3; it is switched on in step 6.)
2. **Migration script** and its table; dry run (prints, changes nothing); run in step 3.
3. **Knight**: `git mv` data, behaviors, sprites (+ raw sheets), rewrite paths, update `prepare_knight_sprites.gd`, re-import, suite.
4. **Wizard**: same.
5. **Archer**: same, including `ricochet_volley.gd`.
6. **Enemies and attributes** (flat), with `scenes/main.tscn`, `map_preview.gd`, `hub.gd`, `AttributeRegistry` and the tests that name them (8 or more files); suite.
7. **Relics** (folder each) and `RelicRegistry`; suite. Then **shared upgrades**; suite.
8. **Switch the content test's folder rules on**, remove empty `data/` and `assets/sprites/`, then **template and docs**: `content/characters/_template/`, `content/characters/README.md`, `README.md`, `CLAUDE.md`, `tests/README.md`, `export_presets.cfg` exclude filter (both presets). Delete the migration script.
9. **Final checks**: the Definition of Done below, including re-running `tools/prepare_knight_sprites.gd` and rendering one frame per character.

## 10. Counts to confirm (verified on `main`)

| Group | Files |
|---|---|
| Knight abilities | slash 3, spin 3, slam 3, dash 4 upgrades (`dash_chain`, `dash_efficient`, `dash_range`, `dash_trail`) = 13 |
| Wizard | bolt 3, lightning 3, meteor 3, phase 4 = 13 |
| Archer | arrow 3, dashshot 3, ricochet 3, arrow_rain 3 = 12, plus 2 character upgrades (`archer_haste`, `archer_eagle`) = 14 |
| Shared | 6 (`damage`, `max_hp`, `move_speed`, `pickup_radius`, `mana_regen`, `max_mana`) |
| Total | 13 + 13 + 14 + 6 = **46**. `git ls-files data/upgrades` has **46** `.tres`; the build recounts and stops if they differ |

`archer_haste` (key `cooldown`) and `archer_eagle` (keys `steady.full`, `arrow.range`) are the only character-bound upgrades whose keys do not start with an ability id; they are the reason for `<character>/upgrades/`.

## 11. Tests it touches

Existing tests change only in a path or a helper call (section 6); none changes what it asserts. The suite is run before step 1 (baseline) and after every step; a test that was failing on `main` is listed, not fixed. Headless has no renderer, so pixels are not tested: after the Archer step one frame of each character is rendered with `--write-movie` and compared by eye with `main` to confirm the sprites still load (CLAUDE.md method; `HERO_HORDE_SAVE` set). The "one run per character casts all four abilities" check is part of `content_load.gd`'s runtime half (a Player fixture per registered character, each ability cast once, no error); the by-eye frame check and the hand play-through are listed unchecked in the PR.

## 12. Open questions / assumptions

- **O1** Shared bases (`DashSlashBehavior`, `BoltBehavior`) stay in `scripts/abilities/` because another character extends or reads them. Alternative: a `content/shared/abilities/` folder. Chosen: stay, because they are code, not data, and engine code lives in `scripts/`.
- **O2** Enemies and attributes stay flat (one file each, nothing to group). If an enemy later gets its own art or brain, it becomes a folder like a relic; nothing else changes.
- **O3** Sounds stay in the flat `assets/audio/` and `Audio.SOUNDS`. A per-character sound folder is a later step.
- **O4** `ability.tres` icons stay atlas regions of `assets/32x32.png`.
- **O5** Item folders are named by id, files by role (`ability.tres`), so the editor's file list shows many files with the same name; the tab title shows the folder. Accepted for predictable paths; the alternative (`slash.tres`) was rejected because a rename of an id would then touch two names.
- **O6** Godot rewrites a `.tres` on re-save and may reorder keys; the migration edits text only, and a diff of numbers is part of step 9.
- **O8** `SteadyAim` stays in `scripts/characters/` because the projectile code (engine) uses it. A trait used only by its own character (`ArcaneFocus`) moves.
- **O7** `README.md` says "Upgrade: new `UpgradeData` in `data/upgrades/`"; it is rewritten to the new rule (section 2).

## 13. Definition of Done

- `git grep -nE "res://data/|res://assets/sprites/|res://scripts/abilities/(slash|spin|slam|lightning|meteor|phase|arrow|arrow_rain|dash_shot|ricochet|ricochet_volley)_?[a-z_]*\.gd|res://scripts/characters/arcane_focus|res://scripts/relics/(fire_trail|frost_comet|storm_orbs|thorn_nova|tidal_wave)\.gd" -- . ':!docs/spec-*' ':!docs/requirements-*' ':!AGENT_DECISION_LOG.md'` prints nothing, and so does the same search for the bare words `data/(abilities|upgrades|characters|enemies|relics|attributes)` and `assets/sprites` (hand-written mentions in the README, comments and `CLAUDE.md`). `data/` and `assets/sprites/` do not exist.
- No resource `id`, stat key, number or text changed: a script compares the property block (everything below `[resource]`) of every moved `.tres` with its `main` version by id, with no difference. `git diff -M` shows moved files with edits only in `ext_resource`, `preload`/`load` lines and the two named test assertions; `.import` and `.uid` sidecars are exempt (an `.import` is rewritten by re-import: its `source_file` and hashed `path` change).
- `tests/run_all.sh` has the same pass set as the baseline plus `content_load.gd` passing.
- `godot --headless --path . --import` produces no error and no "Could not find type".
- `content_load.gd`'s runtime half passes (all registered characters, all abilities cast); the hub's three pedestals and one run per character are looked at in rendered frames (not headless), and the hand play-through is an **unchecked** box in the PR's test plan.
- A new character can be made by copying `content/characters/_template/` and adding one line to `CharacterRegistry` (the template loads in the content test).
- The README, `CLAUDE.md`, `tests/README.md` and `content/characters/README.md` match the layout.

## 14. Build notes (deviations from rev 2)

- **Fixture lookup.** `Fixture.upgrade_path(id)` delegates to a new `tests/upgrade_index.gd` (a plain `RefCounted`, skipped by `run_all.sh`) instead of scanning inside `fixture.gd`: `archer_upgrades.gd` is data-only and cannot load the fixture, which names autoload classes. It scanned `data/upgrades` and `content/` until step 6 and scans `content/` only now.
- **Content test.** `tests/content_load.gd` has a `FOLDER_RULES` switch (off in step 1, on in step 8). Its runtime half builds the grunt itself, so it needed no fixture change.
- **Build order.** Step 6 became: enemies and attributes (6); relics (7a); shared upgrades (7b); template, docs and the switch (8). The migration script also rewrites `.import` files and handles paths with spaces. It was committed in step 2 and removed in step 8.
- **Template.** `_template` has one example ability reused in all four slots, ids prefixed `template_`, and a `frames.tres` that points at the Knight's sprites (no art copied).
- **A slip, fixed.** `scenes/main_menu.tscn` (not part of this work) was staged by mistake in step 6 and removed again by amending that unpushed commit; it is untracked and in no commit.
- **Not verified.** Timing tests (`crowd_performance`, `crowd_bone_warren`, `enemy_status`) failed intermittently under load (a Godot editor and other test runs were open), then passed on rerun. Only the Knight pedestal was looked at in a rendered frame; the Wizard and Archer pedestals were behind the info panel. No full play-through by hand.
