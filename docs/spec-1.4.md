# Spec v1.4: The chest and the inventory (equipment slots and an item pool, in the hub)

Builds on the hub (spec 0.4: `Hub`, `HubDoor`, walk mode), the camp (spec 0.7: `CampSite`, `CampScreen`, `GameSession`, `SaveGame`, `CampAttributes`) and the content layout of spec 1.2. `main` at `cea4ff8`. Status: rev 2 (applies an independent review: inventory files in `run_all.sh`'s cleanup, a public `load_inventory()` so the load is testable, the `equip` edge cases and the meaning of `closed(changed)`, the focus and scroll rules, slot labels that fit, the typed-class rules for the new tests, the chest's opaque rows, the new `assets/hub/` folder, a stat-key allow-list). This PR builds the **system**; the items themselves (their art, stats and how they are unlocked) come in the next PR.

Terms: an **item** is a piece of equipment (`ItemData`). A **slot** is a place on a character where one item is worn. The **pool** is the list of items the player has unlocked. A **loadout** is what one character wears. The **chest** is the object in the hub that opens the inventory screen.

## Flow

In the hub, in walk mode, to the right of the door in the north wall stands a chest (the art in `chest.aseprite`). Walking up to it shows the prompt "F: Inventory"; pressing F plays the door-open sound, a ring of light and a puff at the chest, and opens the inventory screen over the paused game. The screen shows the character being played: on the left seven slots (helmet, chestplate, necklace, two rings, pants, shoes), on the right the pool of unlocked items in a grid, and under them the description of the item under the cursor. Clicking (or Enter on) an item in the grid wears it; clicking an equipped slot takes it off; Esc closes the screen. Equipped items change the hero's stats, in the hub and in every run, and the loadouts and the pool are saved. Until the next PR adds items, the grid reads "No items yet" and nothing can be worn.

## 1. Scope

In scope:
- The chest in the hub: art, placement, prompt and interaction (section 2).
- The data: `ItemData`, `ItemRegistry`, the slot table (section 3).
- The model: `Inventory` (pool, loadouts, rules) and its save (sections 4 and 5).
- The effect: equipped items write their stat modifiers into the hero's `Stats` when it is created (section 6).
- The screen: `InventoryScreen`, mouse and keyboard (section 7).
- Tests and docs (sections 9 and 10).

Out of scope (decided): any real item content (art, names, stats; no item file ships in this PR, the registry list is empty); how items are unlocked (drops, shops, achievements: the model has `unlock(id)` and nothing calls it outside tests); drag and drop; changing equipment during a run; selling, upgrading or comparing items; a stat summary panel; an open-lid animation for the chest (the art is one frame); new sounds; showing equipment on the character's sprite.

Out of scope (later): the items (next PR); item rarity; set bonuses; a per-item cost; showing worn items on the hub pedestals.

## 2. The chest in the hub

Verified against `main`: the hub scene is 960x560 (`scenes/hub.tscn`, Arena `size`), the door is at (480, 0) with `wall_band` 16, its trigger is a 48x24 rectangle centred at (480, 28) (x 456 to 504, y 16 to 40), the torches beside it are at x = 480 +/- 44, y 9; the camp (`CAMP_POS` (170, 300), `CAMP_RADIUS` 48) is the model for an interactable: `CampSite` is a code-drawn node with no collider, `Hub._interact_target()` returns `&"pedestal"`, `&"camp"` or `&""` (always empty in browse mode), `_process` sets the prompt text, `_unhandled_input` acts on the `interact` action (key F) when `_lockout` is over, and `reserved_areas()` keeps the cave decor off it (`tests/cave.gd` checks every decor piece stays 24 px away from each reserved rectangle). The returning player spawns at (480, 80), below the door.

- **Art:** the file is `~/Downloads/chest.aseprite`: one frame of 32x32 (no tags), a closed wooden chest with a gold clasp whose opaque pixels span x 3 to 28 and y 7 to 26. `tools/enemies/export_aseprite.py` exports it (no Aseprite program needed). Files: `art/source/chest/chest.aseprite` (the source, as `art/source/charger/` and `art/source/demon-head/` do) and `assets/hub/chest.png` (+ `.import`), the exported 32x32 frame; `assets/hub/` is a new folder (hub objects drawn from a sprite: nothing else of the kind exists yet, and `assets/` otherwise holds audio, UI and tilesets).
- **`HubChest`** (`scripts/hub/hub_chest.gd`, `class_name HubChest`, a `Node2D`): a `Sprite2D` child with `chest.png`, `centered = false`, `offset = (-16, -27)` so the node's origin is the chest's base (bottom centre of the opaque pixels, row 27), at scale 1. It Y-sorts with the player by its base: it sits in `$World` with `y_sort_enabled`, as the pedestals do; verify at build that `$World` sorts. No collider (as the camp: nothing in the hub blocks the player).
- **Placement:** `Hub.CHEST_POS := Vector2(570, 64)`: 90 px right of the door's centre and 64 px below the top. The sprite's opaque pixels then span x 557 to 582 and y 44 to 63 (the 32x32 frame spans x 554 to 586, y 37 to 69): clear of the wall band (y < 16), of the door trigger (x 456 to 504), of the torch at x 524 (it lights the wall, not the floor) and 90 px from the nearest spot the player returns to from a run (480, 80), so returning from a run never puts the player in range of the chest. The exact spot is confirmed in a rendered frame at build (O3).
- **Interaction:** `Hub.CHEST_RADIUS := 40.0`. `_interact_target()` gains `&"chest"` after `&"pedestal"` and `&"camp"` (the three zones are far apart; the test checks they cannot overlap). The prompt reads "F: Inventory". The `interact` action calls `Hub._open_inventory()`, which opens `Hub.inventory_screen` with the character being played (`characters[focus_index]`): the names mirror `camp_screen` and `_open_camp()`, and the signature is `open(character)`, unlike the camp's `open()`. Only in walk mode, like the camp. A mouse click on the chest does nothing (the camp has no click either).
- **Decor:** `reserved_areas()` gains `Rect2(CHEST_POS.x - 24, CHEST_POS.y - 40, 48, 56)`, so the decor stays 24 px off it (the existing decor test then covers the chest).
- **On open:** `Audio.play(&"door_open")` (an existing sound), `Effects.ring(CHEST_POS, 24.0)` and a gold `puff` above the chest, the same pair `Hub._confirm` uses for a pedestal.

## 3. The data

- **`ItemData`** (`scripts/inventory/item_data.gd`, `class_name ItemData`, a `Resource`): `id: StringName`, `display_name: String`, `description: String` (one short line shown in the screen), `slot: StringName` (one of the six item types below), `icon: Texture2D` (optional; without it the grid and slot draw a coloured square with the first letter of the name), `adds: Dictionary` and `scales: Dictionary` (stat key to amount, exactly the format and meaning of `AttributeData.adds` and `scales`: an add is added, a scale is multiplied as `1 + fraction`; the same keys as upgrades and attributes use, such as `max_hp`, `damage`, `move_speed`, `pickup_radius`).
- **Slots** (constants on `Inventory`): the seven places, in screen order: `helmet`, `chestplate`, `necklace`, `ring_1`, `ring_2`, `pants`, `shoes`. The six item types are `helmet`, `chestplate`, `necklace`, `ring`, `pants`, `shoes`; a `ring` item fits `ring_1` or `ring_2`, every other type fits the slot of its own name. `Inventory.slots_for(item_type) -> Array[StringName]`.
- **Files:** one folder per item, `content/items/<id>/item.tres` (and its `icon.png` beside it later), as characters and relics have since spec 1.2. `ItemRegistry` (`scripts/inventory/item_registry.gd`) lists the paths explicitly in a `PATHS` array so exported builds find them, like `AttributeRegistry`; the array is empty in this PR. `ItemRegistry.all()`, `find(id)`. `ItemRegistry.test_items` is a static `Array[ItemData]` (empty by default): when it is not empty, `all()` returns it instead of loading `PATHS`, so tests can use items without shipping any (the same idea as `SaveGame.override_path`). `content/items/README.md` says how to add an item (a folder, `item.tres`, one line in `PATHS`).
- `export_presets.cfg` needs no change (`content/items/` is exported; only `tests/` and `tools/` are excluded).

## 4. The model: `Inventory`

`Inventory` (`scripts/inventory/inventory.gd`, `class_name Inventory`, a `RefCounted`; `GameSession` owns the one instance, section 5). No autoload, nothing reads `GameSession` from inside it.

State: `unlocked: Array[StringName]` (item ids in the order they were unlocked, no duplicates) and `_worn: Dictionary` (character id to a dictionary of slot to item id). Signal `changed`.

| Call | Rule |
|---|---|
| `unlock(id) -> bool` | Adds the id to the pool if `ItemRegistry.find(id)` knows it and it is not there yet. Emits `changed`. False when unknown or already unlocked. |
| `is_unlocked(id)` | |
| `worn(character_id, slot) -> ItemData` | The item worn in that slot, or null. |
| `worn_items(character_id) -> Array[ItemData]` | Everything that character wears (what section 6 applies). |
| `wearer_of(id) -> StringName` | The character id that wears the item, or `&""`. |
| `equip(character_id, id, slot := &"") -> StringName` | Wears an unlocked item and returns the slot used, or `&""` if it cannot (not unlocked, or `slot` does not fit the item). Without `slot`: the item's own slot; for a ring the first free ring slot, and when both are full it replaces `ring_1`. **No-ops** (return the slot it already occupies, emit nothing, no sound): equipping an item this character already wears when no `slot` is given, or into the slot it already occupies. With an explicit different `slot` an item worn by this character moves there. An item worn by **another** character is taken from them (there is one copy of each item). Whatever was in the target slot goes back to the pool unworn. Emits `changed` once. A click or Enter on a grid item this character already wears therefore does nothing; taking it off is done from its slot. |
| `unequip(character_id, slot) -> bool` | Takes the item off; it stays in the pool. False when the slot was empty. |

Each character has its own loadout; the pool is shared. The `closed(changed)` of section 7 means "the played character's worn set differs from when the screen opened"; taking an item from another character changes that other loadout too, which the hub does not rebuild for (only the played character's player exists).

## 5. Saving

Verified: `SaveGame` (`scripts/systems/save_game.gd`) writes `user://camp.json` (version 1: `gold`, `levels`) through a temp file, honours `override_path` and `HERO_HORDE_SAVE`, saves nothing under `--headless` without one of them, and keeps a bad file as `.bad`; `tests/camp/camp_save.gd` asserts `load_data() == {gold = 0, levels = {}}` exactly. So the inventory is saved in **its own file**, leaving `SaveGame` and its tests untouched.

- **`InventorySave`** (`scripts/inventory/inventory_save.gd`, static): `path()` is `SaveGame.path() + ".inventory"` (`""` when saving is off, so tests and headless runs never touch the player's file); `save(inv) -> bool` (JSON `{version: 1, unlocked: [ids], worn: {character: {slot: id}}}`, written to `<path>.tmp` and renamed, as `SaveGame` does) and `load_into(inv)`. `load_into` does not emit `changed` (loading must not trigger an autosave); `save` reads `path()` at the moment it writes, which is what lets a test point it at its own file with `SaveGame.override_path`. Loading is lenient and clamps like `SaveGame`: a missing or empty file is a new game; invalid JSON or a wrong version is renamed to `.bad` and gives a new game; ids the registry no longer knows are dropped; a worn id that is not unlocked, whose slot does not fit its type, or that is already worn elsewhere (the first one wins, in the order of the file) is dropped.
- **`GameSession`** gets `var inventory := Inventory.new()`, a public `load_inventory()` (called from `_ready` next to the camp save; it replaces the contents with the file's, so a test can set `override_path`, write a file and call it) and an autosave connected to `inventory.changed`. Ids a later registry no longer knows are dropped on load and the file is rewritten without them at the next change: intentional. Nothing else reads the file.
- Gold and attributes are unaffected (`SaveGame.save(gold, levels)` is not called any differently).

## 6. The effect on stats

Verified: `Player._apply_character()` calls `CampAttributes.apply(stats, attribute_levels)` and `health.setup(stats.value(&"max_hp", max_hp))` follows; `attribute_levels` is a field the creator sets before the player enters the tree (`Hub._spawn_player`, `main.gd` line 37); after the camp closes with a change the hub rebuilds the player in place (`_rebuild_player`) because attributes apply once at creation.

- **`ItemEffects.apply(stats, items)`** (`scripts/inventory/item_effects.gd`): for each item adds `adds[key]` and multiplies `1 + scales[key]`, the same arithmetic as `CampAttributes.apply` (level fixed at 1). Equipped bonuses therefore stack with attributes and with upgrades like any other add or multiply.
- **`Player.equipment: Array[ItemData]`** (default empty): `_apply_character()` calls `ItemEffects.apply(stats, equipment)` right after `CampAttributes.apply`. `Hub._spawn_player` and `main.gd` set it from `GameSession.inventory.worn_items(character.id)` where they set `attribute_levels` (the player scene never reads `GameSession`, as CLAUDE.md asks of low-level classes). Tests and tools that create a `Player` without it get no bonuses.
- Closing the inventory screen with a change rebuilds the hub player, as the camp does, so the effect shows at once (the hub's training dummies show the damage).
- Changing equipment is only possible in the hub, so a run always starts with the loadout it was entered with.

## 7. The screen: `InventoryScreen`

`scripts/ui/inventory_screen.gd` (`class_name InventoryScreen`, a `Control` built in code, as `CampScreen` is): a child of the hub's `$UI`, `process_mode = ALWAYS`, hidden until `open(character)`; `open` pauses the tree and `close()` unpauses and emits `closed(changed: bool)` (whether the loadout differs from when it opened), exactly the camp's contract. Esc, Start and `ui_cancel` close it, handled in `_input` before the pause menu sees them. Built with `UiKit` (the 640x360 base resolution, font size 8, a dim layer, `centered`). **Focus** follows `CampScreen`: slots and grid cells are plain `Control`s with `focus_mode = NONE` (not `Button`s) and `mouse_filter = STOP`; `open` releases the current focus owner; Esc and Start are handled in `_input`, the cursor keys in `_unhandled_input`; the dim layer swallows clicks behind the panel. The `ScrollContainer` does not follow a custom cursor on its own: moving the cursor sets `scroll_vertical` so the cursor row is visible (the mouse wheel scrolls it too).

Layout (about 330 x 240 px, centred; 28 px slots with 4 px gaps):

```
INVENTORY - Knight                                  
 [ helmet ]            Items
 [necklace]            [][][][][][]
[ring][chest][ring]    [][][][][][]
 [ pants  ]            [][][][][][]
 [ shoes  ]            ...
                       Name  (slot)
                       description
```

- Left: the seven slots in the shape above, each labelled with a faint short name when empty (`Helm`, `Neck`, `Chest`, `Ring`, `Ring`, `Pants`, `Shoes`: at font size 8 the full words do not fit a 28 px slot; the full slot name is in the description line) and showing the item's icon (or letter square) when full.
- Right: the pool as a grid of 6 columns; 5 rows are visible and more scroll (a `ScrollContainer`). A worn item is marked (a small "E" corner and a lighter frame); an item worn by **another** character shows that character's initial in the corner and is dimmed. With an empty pool the grid area reads "No items yet".
- Under the grid: the name (coloured), the slot type and the description of the item under the cursor or mouse; nothing when none. The description is a fixed-height label of 2 lines with autowrap (the column is about 188 px, so about 40 characters per line): `description` is at most 80 characters, which the content test checks, so the 240 px height holds.
- **Mouse:** hover selects; left click on a grid item equips it (`Inventory.equip`); left click on an occupied slot unequips it. A click on an item worn by someone else moves it here (O1).
- **Keyboard:** two zones, the slots and the grid. Arrows move the cursor inside the zone; Left from the grid's first column goes to the slots and Right from a slot to the grid; Enter (`ui_accept`) equips from the grid or unequips from a slot; for a ring, Enter on the grid uses the first free ring slot (section 4). Esc closes. The first open puts the cursor on the first grid item, or on the helmet slot if the pool is empty.
- **Sounds:** equip `hub_choose`, unequip `menu_click`, a refused action (an item that cannot be worn) `no_mana`, as the camp does; all existing. `last_sound` records the last one so tests can check without audio files, as `CampScreen.last_sound` does.
- A click on a worn grid item does nothing (section 4). It is built once in `Hub._ready` next to `_build_camp_screen()` and kept in `Hub.inventory_screen`; `Hub._on_inventory_closed(changed)` sets the lockout and rebuilds the player when `changed`.

## 8. Files

New: `docs/spec-1.4.md`, `scripts/inventory/{item_data,item_registry,item_effects,inventory,inventory_save}.gd` (+ `.uid`), `scripts/hub/hub_chest.gd` (+ `.uid`), `scripts/ui/inventory_screen.gd` (+ `.uid`), `content/items/README.md`, `art/source/chest/chest.aseprite`, `assets/hub/chest.png` (+ `.import`), `tests/inventory/*.gd` (section 9, + `.uid`).

Changed: `scripts/hub.gd` (chest, `CHEST_POS`, `CHEST_RADIUS`, interact target and prompt, `reserved_areas`, the screen, rebuild on close), `scripts/player/player.gd` (`equipment`, one call), `scripts/main.gd` (one line), `scripts/systems/game_session.gd` (`inventory`, load and save), `tests/run_all.sh` (the loop gains `tests/inventory/*.gd`, its header comment says so, and its per-test cleanup also removes `$save.inventory`, `$save.inventory.tmp` and `$save.inventory.bad`, which autosave would otherwise leave in the temp directory; the new tests' own `_clean()` removes the same suffixes, as `camp_save.gd` does), `tests/README.md`, `README.md` (project layout, the hub), `content/characters/README.md` is untouched.

Existing tests touched: `tests/cave.gd` (the chest's reserved rectangle joins the loop; no edit needed), `tests/hub_walk.gd` (asserts no prompt away from a pedestal: the player there is far from the chest; no edit expected), `tests/camp/camp_site.gd` (clear-of checks do not include the chest; no edit). Run `tests/run_all.sh` as before; the new directory must be in its glob or the new tests never run.

## 9. Tests (new directory `tests/inventory/`)

**Rules for all of them (CLAUDE.md):** `GameSession`, `Player`, `Hub` and `InventoryScreen` use autoloads, so tests hold them in untyped variables, `await process_frame` first, and load scenes and scripts with `load()`; `Inventory`, `ItemData`, `ItemRegistry`, `ItemEffects` and `InventorySave` use no autoload and may be named through `preload`. A test that sets `ItemRegistry.test_items` resets it to `[]` at the end. Stat keys in the content check come from a literal allow-list in the test (`max_hp`, `damage`, `move_speed`, `pickup_radius`, `hp_regen`, `mana_regen`, `max_mana`, `auto_speed`, `cooldown`: `Stats` has no registry); the next PR must also teach `tests/content_load.gd` about `ItemData`.

1. **`inventory_model.gd`** (nothing is seeded, so no 30-seed loop): the slot table (seven slots in order, six item types, `slots_for`); `unlock` (unknown id false, duplicate false, order kept); `equip` puts each type in its own slot; a ring takes `ring_1`, then `ring_2`, then replaces `ring_1`; `equip(..., slot)` with a bad slot returns `&""` and changes nothing; replacing an occupied slot returns the old item to the pool unworn; moving an item between slots; per-character loadouts are independent; an item worn by another character is taken from them (`wearer_of`); `unequip`; `changed` emits once per real change and not on a refused one; the no-op cases of section 4 (re-equipping a worn item, equipping into its own slot) emit nothing and return the slot; every item in `ItemRegistry.all()` (none today) has `id` equal to its folder name, a valid `slot`, a description of at most 80 characters, and only allow-listed stat keys. Uses `ItemRegistry.test_items`.
2. **`inventory_save.gd`**, with its own save path: a round trip; a missing, empty or disabled file is a new game and writes nothing when disabled; invalid JSON, a wrong version, a wrong type each give `.bad` and a new game; unknown ids, a worn item that is not unlocked, a ring in a helmet slot, and the same item worn twice are dropped as section 5 says; the `.tmp` recovery; the camp save file (`SaveGame`) is not touched; `GameSession.load_inventory()` (the test sets `override_path`, writes a file and calls it) loads and does not autosave, and a `changed` writes `InventorySave.path()`; the test removes `.inventory`, `.tmp` and `.bad` files afterwards.
3. **`inventory_stats.gd`**: `ItemEffects.apply` adds and scales (`max_hp` +10 and `damage` x1.2 give `stats.value(&"max_hp", 100) == 110` and `damage` x1.2), and stacks with camp attributes; a `Player` created with `equipment` has the stats and the matching `max_hp` in its health, one without has none; a run (`main.tscn`) player gets the loadout of its own character and none of another's; a Wizard's items do not reach a Knight.
4. **`hub_chest.gd`**: the chest exists at `CHEST_POS` right of the door, its texture is the 32x32 chest; it is clear of the door trigger, the torches, the camp, the pedestals, the training area and the sign; `reserved_areas()` contains its rectangle and no decor is within 24 px; the three interaction zones cannot overlap; the prompt reads "F: Inventory" within `CHEST_RADIUS` in walk mode, is hidden away from it and in browse mode; the interact action calls `_open_inventory()` and opens `hub.inventory_screen` once and only after the lockout (this test replaces the screen by a stub with `open(character)` and a `closed(changed)` signal, so it checks the hub's side only); the tree is paused while it is open; closing with a change rebuilds the player, without a change it does not; the player returning from a run is out of range. A rendered frame (not a test) checks the player sprite drawing correctly while overlapping the chest, since there is no collider.
5. **`inventory_screen.gd`**: seven slots and the grid exist; an empty pool shows "No items yet"; with three test items the grid shows three; a click on an item equips it and the slot, the item's mark and the stats change; a click on the slot unequips; two rings fill two slots; an item worn by another character is dimmed with their initial and a click moves it; hover and keyboard update the description line; arrows, zone switching, Enter and Esc work; Esc unpauses and emits `closed` with the right flag; 40 items scroll without error; `last_sound` is right for equip, unequip and a refusal; the title shows the character's name.

Every new test runs with the time limit CLAUDE.md asks for; the whole suite runs before the PR (the known `crowd_bone_warren` failure stays, see O5).

## 10. Docs

`README.md`: the hub (the chest and F: Inventory), the project layout (`scripts/inventory/`, `content/items/`), and the save. `tests/README.md`: a row per new test and the new directory. `content/items/README.md`: how to add an item. The spec's status line is updated at the review and at the build.

## 11. Build order

Each step is one commit with its tests.

1. **Data and model:** `ItemData`, `ItemRegistry` (with `test_items`), `Inventory`, `ItemEffects`; `tests/inventory/inventory_model.gd`; `tests/run_all.sh` learns the directory and the inventory cleanup suffixes; `tests/README.md` line 8 (the directories it lists) is updated.
2. **Saving:** `InventorySave`, `GameSession.inventory` and its autosave; `tests/inventory/inventory_save.gd`.
3. **Stats:** `Player.equipment`, the two creators set it; `tests/inventory/inventory_stats.gd`.
4. **The chest:** the exported art, `HubChest`, the hub's placement, prompt, reserved area and interaction (opening a stub that only pauses and closes until step 5); `tests/inventory/hub_chest.gd`; a rendered frame of the hub with the chest checked.
5. **The screen:** `InventoryScreen`, wired to the chest and to the rebuild; `tests/inventory/inventory_screen.gd`; a rendered frame of the open screen with test items.
6. **Docs and the suite:** READMEs, the content README, the whole suite.

## 12. Open questions / assumptions

- **O1 (assumed: one copy of each item).** An item worn by the Knight is taken off him when the Wizard puts it on; the screen shows who wears what. The other reading (every character may wear the same item at once) is a one-line change in `Inventory.equip` and the saved shape allows it.
- **O2 (assumed).** No item file ships here, so in the game the chest opens on "No items yet" until the next PR; tests use `ItemRegistry.test_items`. The unlock mechanism is the next PR's (O4 below).
- **O3 (to confirm by eye).** The chest position (570, 64), scale 1 and radius 40 are computed from the code and the art's bounds, not seen; the build renders a frame, and the position may move a few pixels.
- **O4 (assumed).** `Inventory.unlock(id)` is the only entry point for new items; the next PR adds the way the player gets them (drops, shop, achievements) and the item files.
- **O5 (existing).** `tests/maps/crowd_bone_warren.gd` fails its frame-time limit on `main` already; nothing here touches runtime cost (the stat application runs once per player creation).
- **O6 (assumed).** Equipment is applied once at creation, so changing it in the hub rebuilds the hub player (cooldowns reset), as buying a camp attribute does today.
- **O7 (assumed).** The inventory file is `<save path>.inventory` (so `user://camp.json.inventory`), a name chosen to follow the existing `.tmp` and `.bad` suffixes and to leave `SaveGame` and its tests alone; a cleaner single file is possible later by moving both into one versioned save.
- **O8 (assumed).** Icons are optional; without one a coloured square with a letter is drawn. The next PR decides the icon size (the grid cells are 28 px; art should be 24x24 or smaller).

## 13. Definition of Done

- A chest stands right of the hub door; F near it (walk mode only) opens the inventory of the character being played, over a paused game; Esc closes it.
- The screen has the seven slots and the pool grid; items can be worn and taken off by mouse and keyboard; rings use two slots; each character has its own loadout and an item is worn by one character at a time.
- Equipped items change the hero's stats in the hub and in runs; the loadouts and the pool survive a restart and a corrupt file never crashes or loses the camp save.
- Nothing about gold, attributes, runs or the existing hub changes when no item is equipped.
- All new tests pass; the whole suite passes except the known `crowd_bone_warren` failure; `.uid` and `.import` files are committed; README files are current; the open-question items are answered or logged; nothing is claimed as tried by hand that was not.
