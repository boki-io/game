# Characters

One folder per character: `content/characters/<id>/` holds `character.tres` (a `CharacterData`), `frames.tres` (a
`SpriteFrames` over `sprites/`) and `abilities/<ability id>/`, each with `ability.tres` (an `AbilityData`),
`behavior.gd` (the cast) and `upgrades/<upgrade id>.tres` (that ability's `UpgradeData`). A leading underscore marks a
folder that is not a playable character: `_template` (what new characters are copied from; its ids start with
`template_` so they never clash). Relics live apart in `content/relics/<id>/` (`relic.tres` plus a behavior script) and
upgrades every character may draw in `content/shared/upgrades/`. Spec: `docs/spec-1.2.md` sections 2 and 3.

## Naming rules

- Folder name = the id (`knight`, `slash`, `fire_trail`). The ids inside the `.tres` match the folder.
- Fixed file names: `character.tres`, `frames.tres`, `ability.tres`, `behavior.gd`, `relic.tres`. Upgrades are named
  after their id (`slash_damage.tres`).
- Upgrade ids are unique across the whole game (the test checks it). Prefix them with the ability or character.
- An upgrade's stat keys are `<ability id>.<stat>` (`slash.damage`, `slash.arc_degrees`), so an upgrade only works for
  an ability that is in the character's pool.
- `behavior.gd` has **no `class_name`** and `extends AbilityBehavior`. A `class_name` is global: two characters could
  clash, and the class cache must be rebuilt. `ability.tres` names the script by path.

## Adding a character (copy the template)

1. Copy `content/characters/_template/` to `content/characters/<id>/` (Finder or `cp -R`; do not copy art, give the
   new folder its own `sprites/`).
2. Rename every id: in `character.tres` (`template_hero`), each `ability.tres` (`template_example`) and each upgrade
   (`template_damage`, `template_arc`) and the stat keys inside them. Fix the `res://content/characters/_template/...`
   paths in the `.tres` files, `frames.tres` included (the template borrows the Knight's sprites; point it at yours).
3. Do not add a `class_name` to a copied `behavior.gd` unless the name is unique in the project.
4. Add one line to `CharacterRegistry.PATHS` (`scripts/characters/character_registry.gd`).
5. Run `godot --headless --path . --import`, then `tests/content_load.gd`.

## Adding an ability

Make `abilities/<id>/` with `ability.tres` and `behavior.gd` (`extends AbilityBehavior`, override `cast()`, and
`update()` / `finish()` if the cast lasts; `scripts/abilities/ability_behavior.gd` has `hit_arc` and `hit_circle`).
Numbers (cooldown, damage, range) go in `ability.tres`; read them through `caster.value(d, &"range", d.range)` so
upgrades apply. Put it in a slot (`ability_auto`, `ability_q`, `ability_e`, `ability_r`) of `character.tres`, and add
its upgrades to the character's `upgrade_pool`. The `abilities/example/` folder of the template is the smallest case.

## Adding an upgrade

A `.tres` of `UpgradeData` in the ability's `upgrades/` folder: `id`, `display_name`, `description`, `tag`,
`max_level`, and `adds` / `mults` keyed by `<ability id>.<stat>` (or a player stat such as `max_hp`). List it in the
`upgrade_pool` of every character that may offer it. One that suits every character goes in `content/shared/upgrades/`
and is listed in each pool.

## Adding a relic

`content/relics/<id>/relic.tres` (a `RelicData`: id, name, colour, glyph, `levels`) plus a behavior script that
extends `RelicBehavior` (here a `class_name` is the norm, as in `fire_trail.gd`). Add the path to
`RelicRegistry.PATHS` (`scripts/relics/relic_registry.gd`).

## What is shared, and why

- `content/shared/upgrades/` holds the stat upgrades every character can draw (`max_hp`, `damage`, ...).
- The dash and bolt behaviors stay in `scripts/abilities/` (`dash_slash_behavior.gd`, `bolt_behavior.gd`), and so does
  `SteadyAim`: several characters build on them (the Knight's and Wizard's dashes, the Wizard's and Archer's bolts), so
  they belong to no one folder. An ability folder then holds only its `ability.tres` (and a thin `behavior.gd` where
  it needs one).

## Registries are explicit lists

Nothing scans the folders at run time. `CharacterRegistry.PATHS`, `RelicRegistry.PATHS`, `AttributeRegistry.PATHS`
and `MapRegistry.IDS` list what ships; a folder that is not listed is not in the game (this is how `_template` stays
out). After adding a script with a `class_name` (a relic behavior, say), run `godot --headless --path . --import` so
the global class cache knows it; a missing class shows up as "Could not find type" parse errors. Commit the new
`.uid` and `.import` files.

## What `tests/content_load.gd` checks

Every `.tres` under `data/` and `content/` (not `content/maps/`) loads and every `ext_resource` path exists; upgrade
ids are unique; each registered character has four abilities, each with a behavior; nothing is an orphan (no upgrade,
ability, relic, attribute or frames file that nothing uses); per-ability upgrades only touch stat keys of an ability in
the character's pool; and a run as each character casts every ability once. `_template` is loaded explicitly and held
to the same rules (and, once `FOLDER_RULES` is on, to the folder layout above) although it is not registered.
Run: `godot --headless --path . --script tests/content_load.gd`.
