# Spec v1.5: Items (18 pieces of equipment in three ratings, legendary ones grant a relic, a loot drop from the charger)

Builds on spec 1.4 (the chest and the inventory: `Inventory`, `ItemData`, `ItemRegistry`, `ItemEffects`, `InventoryScreen`; PR #16, not merged yet) and on the relics of spec 1.0 (`PlayerRelics`, `RelicData`, `LevelUpRoller`, the HUD slots). This branch is stacked on `spec-1.4-inventory` with `main` (`e996c02`, which has the vacuum magnet, PR #15) merged in. Status: rev 2 (applies an independent review: pickup range was never applied to the collector, the screen labels and the 1.4 test assertions that change, the default rating of the 1.4 test items, the tests' save path, a banner that survives the pause, the HUD outline rule, a cap and a throttle for lying drops, the restore ordering, unlock through the registry, and what `cooldown` really affects).

Terms: a **rating** is an item's tier: `standard`, `epic` or `legendary`. A **granted relic** is a relic a worn legendary item gives the hero for the whole run, in an extra relic slot. The **loot drop** is the ground pickup that unlocks an item.

## Flow

Killing a charger (the Dasher, `dasher.tres`) has a 10% chance (a number in its data file, to be lowered to 1% after testing) to drop a glowing item on the ground, tinted by its rating. Walking onto it unlocks the item for good (saved at once) and shows "Found: Warden Helm (Epic)". Back in the hub the chest lists it; wear it and the hero's stats rise. Standard items give a small bonus to one stat, epic items a larger one to two stats, legendary items the largest bonus and, for five of the six types, a **relic** from the first moment of every run: it sits in a fifth relic slot (a legendary ring gives stats only). So a hero with four relics picked from level-up cards and Emberstep Boots on has five passives. The granted relic can still be raised to level 3 by level-up cards.

## 1. Scope

In scope:
- 18 items, three per type, one of each rating (section 2); their data files and the registry list.
- Rating fields on `ItemData`, an auto-generated stat line, rating colours (section 3).
- The granted relic: extra relic slots, creation, run carry-over, level-up cards and HUD (section 4).
- The loot drop from the charger: data, roll, ground pickup, unlock and banner (section 5).
- The inventory screen shows rating colours, the stat line and the granted relic (section 6).
- Tests and docs.

Out of scope (decided): drops from other enemies or bosses (bosses do not exist yet; the drop chance is a field any `EnemyData` can set); shops; icons (items still draw as coloured squares with a letter, see O5); a sixth relic; equipping during a run; selling or upgrading items; set bonuses; changing the five relics themselves; a new sound (the pickup reuses `level_up`).

Out of scope (later): boss drops and the 1% chance; item icons; per-character item restrictions; a way to compare items.

## 2. The 18 items

One folder each, `content/items/<id>/item.tres`, `id` equal to the folder name. Three per item type, one of each rating. Bonuses use the keys and format of spec 1.4 (`adds` are added, `scales` multiply as `1 + fraction`); every key is one the game reads. Verified: `max_hp` (`Player._ready`, after `_apply_character`), `hp_regen`, `move_speed` and `damage` (read when used), `auto_speed` and `cooldown` (`AbilityCaster`; `cooldown` only affects the Q, E and R abilities, not the auto attack or relic cooldowns), and `pickup_radius`, which `XPCollector.refresh()` reads only in its own `_ready` (which runs before `Player._ready`, so before the items are applied) and after a level-up: section 4 adds a refresh so the three pickup-range items work. No item uses mana, because the Archer has none (`uses_mana = false`).

| Type | Standard | Epic | Legendary (relic) |
|---|---|---|---|
| Helmet | `leather_cap`: +0.3 HP/s | `warden_helm`: +0.6 HP/s, +10 max HP | `stormcaller_crown`: +1.0 HP/s, +20 max HP, **Storm Orbs** |
| Chestplate | `padded_vest`: +15 max HP | `reinforced_mail`: +30 max HP, +0.3 HP/s | `thornmail`: +50 max HP, +0.5 HP/s, **Thorn Nova** |
| Necklace | `bone_charm`: +4% damage | `amber_pendant`: +8% damage, +15% pickup range | `frostfall_pendant`: +12% damage, +30% pickup range, **Frost Comet** |
| Ring | `copper_ring`: +4% attack speed | `silver_ring`: +8% attack speed, +3% damage | `ring_of_mastery`: +14% attack speed, +6% damage (no relic) |
| Pants | `cloth_trousers`: -4% ability cooldowns | `hardened_greaves`: -8% ability cooldowns, +10 max HP | `tidewalker_greaves`: -12% ability cooldowns, +20 max HP, **Tidal Wave** |
| Shoes | `worn_boots`: +4% move speed | `swift_boots`: +8% move speed, +20% pickup range | `emberstep_boots`: +12% move speed, -4% ability cooldowns, **Fire Trail** |

Display names are the ids in title case ("Leather Cap", "Stormcaller Crown", "Ring of Mastery"). Each has an optional flavour line of at most 40 characters (O1). The numbers are a first pass sized against the camp: one Might level is +3% damage and one Toughness level +8 max HP, so a standard item is about one level of one stat, an epic about two to three, a legendary about four plus the relic. The ring is the stats-only legendary (the user's choice for the sixth), so its numbers are the largest of the legendaries. All values live in the `.tres` files; tuning after play is editing numbers.

Relic ids (verified in `content/relics/*/relic.tres`): `storm_orbs`, `thorn_nova`, `frost_comet`, `tidal_wave`, `fire_trail`; each relic is granted by exactly one item.

## 3. `ItemData` changes (`scripts/inventory/item_data.gd`)

- New fields: `rating: StringName = &"standard"` (one of `ItemData.RATINGS = [&"standard", &"epic", &"legendary"]`) and `relic_id: StringName = &""` (the relic a worn legendary grants; empty otherwise).
- `ItemData.rating_color(rating) -> Color`: standard `#b8b0a0` (stone), epic `#b070ff` (purple), legendary `#ff9a3a` (orange). `ItemData.rating_name(rating)`: "Standard", "Epic", "Legendary".
- `stat_text() -> String`: the bonuses as one line, from `adds` then `scales`, each in the order the keys are written in the file, with labels from a fixed table (`max_hp` "max HP", `hp_regen` "HP/s", `damage` "damage", `auto_speed` "attack speed", `cooldown` "ability cooldowns", `move_speed` "move speed", `pickup_radius` "pickup range", `max_mana` "max mana", `mana_regen` "mana/s"): an add is `+N label` (a whole number without decimals, else one decimal), a scale is `+N% label` or `-N% label`. Example: `+1.0 HP/s, +20 max HP`. A key not in the table is shown as its own name. An item with no bonuses (the 1.4 test items) gives `""`. `rating` defaults to `standard` and `relic_id` to empty, so the 1.4 tests' hand-made items stay valid unchanged.
- `description` shrinks to at most 40 characters (it is now a flavour line under the stat line; the 80 limit of spec 1.4 is replaced); the doc comment of the field and the header comment of `ItemRegistry` ("no item ships in spec 1.4") are updated.

## 4. The granted relic

Verified against the code: `PlayerRelics` has `MAX_SLOTS := 4`, a `slots` field (`var slots := MAX_SLOTS`), `free_slots() = slots - levels.size()`, and `add_or_raise(data, flash)` which refuses in the hub; `Hud._draw_relics` loops over the constant `PlayerRelics.MAX_SLOTS`; `RunProgress.restore` re-adds every saved relic with `add_or_raise` called as many times as its saved level; `LevelUpRoller.roll` offers a new relic only when `free_slots() > 0`, an upgrade card for an owned relic below level 3, and forces a new relic among the first three cards when `relics.levels.is_empty()`.

- **`PlayerRelics.grant(data) -> bool`**: not in the hub, and not when the relic is already owned: `slots += 1`, the id is appended to the new `granted: Array[StringName]`, and the relic is added at level 1 without flashing (`add_or_raise(data, false)`). Because `slots` grows by one for each granted relic, `free_slots()` is the same as without it.
- **`Player._ready`**: after the player registers itself, every `equipment` item with a `relic_id` is granted (`RelicRegistry.find`). The hub player never gets one (the hub has no relics). So a run's player always starts with its granted relics in the first slots, before any card is picked.
- **Pickup range:** `Player._ready` calls `collector.refresh()` (the `XPCollector`, `scripts/player/xp_collector.gd`) right after `_apply_character`, so `pickup_radius` from items is in the collector's shape from the start (`48 x 1.15` for `amber_pendant`). Without it the three pickup-range items would do nothing.
- **Raising and cards:** a granted relic is an owned relic: upgrade cards can raise it to level 3; it is never offered as a new relic (it is owned). `LevelUpRoller`'s "no relic yet: one of the three is a new relic" rule is changed from `relics.levels.is_empty()` to `relics.levels.size() <= relics.granted.size()` (no relic has been *picked* yet), so wearing a legendary does not remove the first-level-up guarantee.
- **Carry-over between stages:** `RunProgress.restore` is changed to raise each saved relic until its level equals the saved one (`while level_of(relic) < saved`), instead of calling `add_or_raise` once per saved level: a granted relic already stands at level 1 when `restore` runs, and the old loop would raise it past what was saved. The old loop never went past level 3 (the raise is refused there) but it did raise a relic that stood at level 1 above a saved level 1 or 2. The snapshot is still `levels.duplicate()` and `granted` is not saved: the next stage's player is created with the same equipment, so `Player._ready` grants the same relics first and `main.gd` calls `RunProgress.restore` after `add_child`, which then raises them to their saved levels; the order is stable.
- **HUD:** `Hud._draw_relics` loops `relics.slots` instead of `MAX_SLOTS`; `relic_slot_rect(i, view)` is unchanged and already works for any `i` (the column grows downwards: nine slots, the most possible with five granted, end at y 266, clear of the other HUD parts). A granted relic's slot (`ids[i] in relics.granted`) has a gold outline (`#ffd866`) instead of the relic colour ring; the white flash of a raise still overrides it. The doc comments that say "slot 0 to 3" (`PlayerRelics.flashed`, `Hud.relic_slot_rect`, `Hud._draw_relics`) are updated.
- **Removing an item** needs nothing: equipment only changes in the hub, and a run reads it once at creation. A run that starts without the item has no granted relic.

## 5. The loot drop

Verified: `SpawnDirector._on_enemy_died` spawns a gem, rolls a coin and rolls the vacuum magnet (spec 1.3) inside its `pickups` branch; `Pickups` owns the pools and the magnet and is set up by `main.gd` (`spawn_director.pickups = $Pickups`, `coin_bonus`); pickups hop out with `Pickups.random_pop()` and `pop_step` and cannot be taken until the hop ends; `GameSession` must not be read from `Pickups` or an item (CLAUDE.md), so `main.gd` hands over what is needed.

- **`EnemyData.item_drop_chance: float = 0.0`** (an `@export_range(0, 1)` in a new `@export_group("Loot")`): the chance that a kill drops an item. `dasher.tres` sets `0.10`. After testing it is edited to `0.01`. Nothing else sets it.
- **`LootData`** (`scripts/inventory/loot_data.gd`, `class_name LootData`, a `Resource`) and `content/items/loot.tres`: `weights: Dictionary` rating to weight (`standard` 70, `epic` 25, `legendary` 5), `pick_distance: float` (14 px) and `max_lying: int` (6). One file for the table, so the rarity of items is tuned in one place.
- **`ItemLoot.pick(owned, lying, loot, rng) -> StringName`** (`scripts/inventory/item_loot.gd`, static): draws a rating by the weights among the ratings that still have an item that is neither `owned` (unlocked) nor `lying` (already on the ground); then a random such item of that rating; returns `&""` when nothing is left (every item owned or lying). `rng` is a `RandomNumberGenerator` so tests can seed it. A rating with no candidates is skipped, not re-rolled.
- **`ItemDrop`** (`scripts/systems/item_drop.gd`, `class_name ItemDrop`, a `Node2D`; `scenes/item_drop.tscn`): like the magnet, it hops out, then is taken by the living player who comes within `pick_distance` of the body point (`global_position + Vector2(0, -6)`); it has no `attract()`, so the pickup radius never pulls it. It does **not** expire: it lies until the stage ends. Drawn in code: a small gem-shaped square in the rating colour with a glow that breathes (standard radius 8 px, epic 11, legendary 14) and, for epic and legendary, a thin vertical beam 24 px tall so it is easy to see in a crowd. It checks for a taker every 6th physics frame (not every frame) and redraws its glow at about 15 Hz, because many can lie at once.
- **`Pickups`** gets `@export var loot: LootData`, `@export var item_drop_scene: PackedScene`, `var inventory: Inventory` (set by `main.gd`; null means no drops), a `signal item_collected(item_id)`, and: `roll_item_drop(pos, chance, rng := null) -> bool` (rolls `chance`, then `ItemLoot.pick`; skips when `inventory` is null; returns whether one was placed), `place_item_drop(pos, item_id)`, `release_item_drop(drop)` and `lying_item_ids() -> Array[StringName]`. Drops are pooled like coins: a small list that reuses released nodes. At most `LootData.max_lying` (6) drops lie at once; `roll_item_drop` returns false at the cap. `lying_item_ids()` counts a drop that is still hopping. A dead player takes nothing; the drops are freed with the stage (they are children of `Pickups`).
- **`SpawnDirector._on_enemy_died`** calls `pickups.roll_item_drop(enemy.global_position, enemy.data.item_drop_chance)` when `item_drop_chance > 0`, inside the existing `pickups` branch.
- **`main.gd`** sets `pickups.inventory = GameSession.inventory`, connects `item_collected` to `_on_item_collected(item_id)`: only when `GameSession.inventory.unlock(item_id)` returns true (it refuses an unknown or already owned id; it autosaves, spec 1.4) does it play `Audio.play(&"level_up")` and show the banner. The banner is a `Label` named `ItemBanner` in `$UI`, top centre at y 44, text `Found: <name> (<Rating>)` in the rating colour, shown for 3 s and then faded out in 0.5 s, using a timer and tween that keep running while the tree is paused (`process_mode` ALWAYS, `create_timer(3.0, true)`, as `StageBanner` does) so a level-up menu open at that moment cannot leave it on screen; a second find replaces the text and restarts the time. Items found in a run can only be worn from the hub, so a line under the name reads "Wear it at the chest in the hub" in grey.
- A run that is lost or abandoned keeps the items already unlocked (they are saved when found).

## 6. The inventory screen with ratings

`InventoryScreen` (spec 1.4) changes only in how it draws and what it says:
- The frame of a cell holding an item is drawn in the item's rating colour (the cursor frame stays gold; the "worn here" frame brightening stays).
- The three labels of the screen change like this: `_name_label` shows the name in the rating colour; `_type_label` shows "Epic Helmet", and for a legendary with a relic "Legendary Shoes - Fire Trail"; `_desc_label` shows the item's `stat_text()` and, on a second line, the flavour `description` when there is one (the label is 3 lines of about 40 characters, 33 px instead of 22, so the panel grows by 11 px, about 250 px high, inside 360). An empty slot still names itself ("Helmet slot").
- The assertions of `tests/inventory/inventory_screen.gd` that read the labels (`_type_label.text == "Helmet"`, `_desc_label.text == "A plain cap."`) change to the new texts ("Standard Helmet", and the flavour line under an empty stat line); nothing else about the screen changes.

## 7. Files

New: `docs/spec-1.5.md`, `content/items/<id>/item.tres` x 18, `content/items/loot.tres`, `scripts/inventory/loot_data.gd`, `scripts/inventory/item_loot.gd`, `scripts/systems/item_drop.gd`, `scenes/item_drop.tscn` (all with `.uid`), `tests/inventory/item_content.gd`, `tests/inventory/item_loot.gd`, `tests/inventory/item_drop.gd`, `tests/inventory/legendary_relic.gd`.

Changed: `scripts/player/xp_collector.gd` is read-only here but `scripts/player/player.gd` gains the refresh call; `scripts/inventory/item_data.gd`, `scripts/inventory/item_registry.gd` (`PATHS` with the 18 and its header comment), `scripts/relics/player_relics.gd` (`grant`, `granted`, the "slot 0 to 3" comment), `scripts/player/player.gd` (the grants), `scripts/systems/run_progress.gd` (`restore`), `scripts/relics/level_up_roller.gd` (the guarantee rule), `scripts/ui/hud.gd` (`slots`, the gold outline), `scripts/ui/inventory_screen.gd` (section 6), `scripts/enemy/enemy_data.gd` (`item_drop_chance`), `content/enemies/dasher.tres`, `scripts/systems/pickups.gd`, `scripts/systems/spawn_director.gd`, `scripts/main.gd`, `scenes/main.tscn` (the two exports), `tests/inventory/inventory_model.gd` (its content block, see section 8), `tests/content_load.gd`, `content/items/README.md`, `README.md`, `tests/README.md`.

## 8. Tests it touches

- `tests/inventory/inventory_model.gd`: its `_content(count)` block asserts "no item ships" (`count == 0`) and a description limit of 80. The block moves to `item_content.gd` (which checks the real 18 with a limit of 40); the model test keeps using `test_items` for its own cases and drops the count check.
- `tests/content_load.gd` scans `content/` and checks each class of `.tres` is registered: it gains an `ItemData` orphan check against `ItemRegistry` (and `LootData` loads).
- `tests/relic_progress.gd` (capture and restore keep ids, levels and order) and `tests/relic_cards.gd` (the first-level-up guarantee) cover the two changed behaviours for heroes without items and must still pass unchanged; the new test adds the with-items cases. `tests/relic_hud.gd` (slot rects 0 to 3, the column ends at y 136) is unchanged.
- `tests/inventory/inventory_screen.gd`: the label assertions above change and rating assertions are added (frame colour per rating, the relic in the type line); the hub tests keep passing.
- The new tests that run `main.tscn` wire `GameSession.inventory` and autosave through `InventorySave`: they set `SaveGame.override_path` to a scratch path (or `""`) and call `GameSession.load_inventory()` first, as the 1.4 tests do, and clean the `.inventory` files; a hand run outside the tests uses `HERO_HORDE_SAVE`, which `InventorySave.path()` follows (it appends `.inventory` to `SaveGame.path()`).
- Tests that kill many dashers with the global RNG (`tests/impact_feedback.gd` kills one) can now see an item drop at 10%; it sits inert in `Pickups` and changes none of their assertions (the same reasoning as spec 1.3 section 7a). A test that must be exact sets `item_drop_chance` to 0 on a duplicate of the data.

## 9. New tests (`tests/inventory/`)

Rules (CLAUDE.md): `GameSession`, `Player`, `Pickups`, the hub and the screen use autoloads, so tests hold them in untyped variables, `await process_frame` first and use `load()`; `ItemData`, `ItemRegistry`, `ItemLoot`, `LootData` and `Inventory` use none and may be named through `preload`.

1. **`item_content.gd`**: the registry holds exactly 18 items; each id equals its folder name and its file is `content/items/<id>/item.tres`; per type exactly one of each rating (so 3 per type, 6 types); ids and display names are unique; the stat keys are in the allow-list of spec 1.4 and none is a mana key; the table of section 2 matches the data (a test table lists every item's stats and relic); every legendary except the ring has a `relic_id` that `RelicRegistry` knows, all five distinct, and no standard or epic has one; the ring legendary has none; the numbers rise with rating (the sum of the absolute bonus per stat key is non-decreasing standard to epic to legendary within a type); `description` is at most 40 characters; `stat_text()` gives exactly the strings of the table for every item; `rating_color` has three different colours.
2. **`item_loot.gd`**: with a seeded `RandomNumberGenerator`, over 3000 picks from nothing owned the rating shares are within 3 points of 70/25/5; an owned item is never picked; an item already lying is never picked; with every standard item owned no standard is ever returned and the other shares rescale; with every item owned or lying the result is `&""`; the same seed gives the same sequence.
3. **`item_drop.gd`**: on a run (`main.tscn`): `roll_item_drop` at chance 1.0 places exactly one `ItemDrop` at the position, tinted by the item's rating; at 0 none; with `inventory` null none; a second roll while one lies never repeats its item; a dasher killed through the director with its chance set to 1.0 drops one, a grunt never; a drop is not taken during its hop, is taken by a living player within 14 px (the `item_collected` signal fires, the item becomes unlocked in `GameSession.inventory` and is saved, the banner shows the right name and rating colour and then fades), is not taken by a dead player, is not pulled by the pickup radius, and does not expire (still there after 120 s of game time, advanced by setting its age); `unlock` returning false (an item already owned) shows no banner and plays no sound; at most 6 lie at once and a hopping drop counts as lying; the banner is still cleared after a pause that spans its 3 s; the second find replaces the banner; `dasher.tres` has `item_drop_chance == 0.10` and no other enemy sets it.
4. **`legendary_relic.gd`**: (first, a worn `amber_pendant` makes the collector's `_shape.radius` equal `48 x 1.15`, and `swift_boots` and `frostfall_pendant` likewise;) a Player created with a legendary in `equipment` (in a run) owns the relic at level 1 in slot 0, `relics.slots == 5`, `free_slots() == 4` and `granted` lists it; without legendaries `slots == 4`; the ring legendary grants nothing; the hub player gets none; two legendaries give two granted relics and six slots; the granted relic rises to level 3 through `add_or_raise` and a roller card; it is never in the new-relic cards; with 4 further relics picked the player has 5 passives and no card offers a new one; the first-level-up guarantee still holds with a legendary worn (`levels.size() <= granted.size()`); `RunProgress.capture` then `restore` on a new player created with the same equipment keeps level 3 and the order, and a granted relic does not end above its saved level; the HUD draws five slot rects (`relics.slots`) and marks the granted one (the slot count the HUD loops over is `relics.slots`); the relic's behavior node exists and works (its `cooldown_fraction` or effect is reachable, e.g. Fire Trail leaves flames when the hero moves).

Every new test runs with the time limit CLAUDE.md asks for; the whole suite runs before the PR (the known `crowd_bone_warren` failure stays, O8).

## 10. Docs

`README.md`: the items (ratings, the legendary relic, the charger's drop, the chance in `dasher.tres`) and the project layout. `content/items/README.md`: the ratings, `relic_id`, `stat_text`, the loot table. `tests/README.md`: a row per new test and the changed rows. The status line of this spec is updated at the review and at the build (to "built", with build notes in a last section, as spec 1.4 has).

## 11. Build order

Each step is one commit with its tests.

1. **The items:** `ItemData` fields, `stat_text`, colours; the 18 `.tres` files and the registry list; `tests/inventory/item_content.gd`; the changed model test and `content_load.gd`; the screen's rating colours and stat line with its test additions.
2. **The granted relic:** `PlayerRelics.grant`, the `Player` grants, `RunProgress.restore`, the roller rule, the HUD slots and outline; `tests/inventory/legendary_relic.gd`.
3. **The loot:** `LootData`, `ItemLoot`, `EnemyData.item_drop_chance`, `ItemDrop`, `Pickups`, the director call, `main.gd` (the unlock and the banner); `tests/inventory/item_loot.gd` and `item_drop.gd`.
4. **Docs and the suite:** READMEs, a rendered frame of the screen with the real items and of a drop on the ground, the whole suite.

## 12. Open questions / assumptions

- **O1 (assumed).** The flavour lines are short placeholders written at build (for example "A soft cap."), each at most 40 characters; the names are generic as asked. The user can rename or rewrite any of them.
- **O2 (assumed: first-pass numbers).** The stat values in section 2 and the loot weights 70/25/5 are guesses sized against the camp attributes, not measured. They are data (the `.tres` files and `loot.tres`), so tuning needs no code.
- **O3 (user's choice, 10% for testing).** The charger's drop chance is 0.10 now and is expected to become 0.01; both are one edit of `dasher.tres`.
- **O4 (assumed: the ring is the stats-only legendary).** The user chose "the 6th legendary is stats only" without naming the type; the ring is used because two ring slots make a second relic-less legendary the least likely to be missed. Another type can swap with it by editing two files.
- **O5 (assumed: no icons).** Items still draw as coloured squares with a letter (spec 1.4), now with a rating-coloured frame. Icons (24x24 or smaller) come later with the art.
- **O6 (assumed).** A granted relic sits in the first slots (it is created before any card is picked) and is marked by a gold outline; the column grows by one slot per granted relic (at most five, so nine slots).
- **O7 (assumed).** The "first level-up offers a new relic" rule is kept by counting only picked relics; a hero with a granted relic still gets that guarantee.
- **O8 (existing).** `tests/maps/crowd_bone_warren.gd` fails its frame-time limit on `main` already; the only added per-frame work is at most 6 `ItemDrop` nodes, each checking for a taker every 6th frame; the cost is to be measured at the 10% chance and is accepted at 1%.
- **O9 (assumed).** An item can be found only from the charger for now and only in runs; there is no other way to unlock one (no debug command is added; setting `item_drop_chance` to 1.0 in `dasher.tres` is the way to test by hand).
- **O10 (assumed).** An item already unlocked is never dropped again, so a hero that owns all 18 sees no more drops.
- **O11 (stacking).** This branch is stacked on `spec-1.4-inventory`; its PR targets `main` and shows the 1.4 commits until #16 merges (or is retargeted after the merge).

## 13. Definition of Done

- 18 items exist (three per type: standard, epic, legendary), each with the stats of section 2, listed in `ItemRegistry`; the chest shows their rating colours, stat lines and, for legendaries, the relic.
- Wearing a legendary (other than the ring) gives the hero its relic at level 1 in an extra slot at the start of every run, in every stage, upgradable by cards to level 3, never offered as a new relic, marked on the HUD; five passives are possible with four picked relics.
- A charger kill drops an item with the chance in its data (10% now); walking onto it unlocks the item, saves it and shows the banner; no item drops twice and none drops when all are owned.
- Existing relic, run-progress, HUD and inventory behaviour is unchanged for a hero with no items.
- All new tests pass; the whole suite passes except the known `crowd_bone_warren` failure; `.uid` files are committed; the READMEs are current; the open questions are answered or logged; nothing is claimed as tried by hand that was not.
