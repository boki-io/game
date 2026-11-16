# Spec v0.7: The camp (spending gold on character attributes)

Builds on spec v0.6 (merged into `main`, PR #3) and on v0.5's gold. Status: draft rev 4 (rev 3 added Recovery, Fury, Agility; rev 4 applies its review). Rev 2 applied an independent review: no camp click in browse mode (the camp is off-screen there), the camp screen handles Esc itself, coins are banked when the run ends, "Vitality" renamed Toughness, per-test save files, control and save details.

Terms: an **attribute** is a permanent upgrade bought with gold at the camp (new). It is not an **upgrade**, which is
the per-run pick from the level-up menu (v0.1 section 9) and stays as it is. (The level-up pool already has an upgrade
called "Vitality", +20 max HP, which is why the attribute is named Toughness.) The **camp** is a small place in the hub
with a character and a chest; the **camp screen** is the menu it opens. **Banking** is adding a run's coins to the
saved gold total when the player is back in the hub.

## 1. Scope

Gold has been collected since v0.5 but cannot be spent. v0.7 gives it a use: a camp in the hub where the player
levels up eight attributes that make every character stronger from the start of every run.

In scope:
- **Eight attributes** (Toughness, Recovery, Might, Fury, Haste, Agility, Focus, Greed), **7 levels each**, **shared by all characters**
  (section 3).
- **A camp in the hub** (section 6): a camper next to a small tent and a chest, placed under the training dummies,
  that you interact with to open the camp screen.
- **The camp screen** (section 7): shows your gold and each attribute's level, what the next level gives and what it
  costs, with buy and undo buttons, and keyboard, mouse and gamepad control.
- **Free respec**: any level can be undone and its gold comes back in full, so nothing is lost by trying a build
  (section 5.3).
- **Coins are banked when you return to the hub** (section 4): coins picked up during a run are a "run purse"; when the
  run ends and you are back in the hub they are added to your saved gold and shown (a "+N gold" banner and a counter).
- **Saving to disk** (section 8): gold and attribute levels survive closing the game. This is the first thing the
  game saves.
- Tests, and the README and test README rows that go with them.

Out of scope (later): attributes per character, more attributes (section 3.3 lists candidates), shop items or
consumables, camp upgrades or a visible camp that grows, showing attribute bonuses on the hub info panel or the
in-run HUD, a settings or key-rebinding menu, new sounds or art for the camp beyond placeholder drawing, cloud saves,
multiple save slots, and balancing the in-run level-up pool (it is untouched).

**The question this version answers:** does earning and spending gold between runs make "one more run" worth it?

## 2. Flow

```
hub (walk mode) --F near the camp--> camp screen (buy / undo levels) --Esc--> hub
run: coins -> run purse (GameSession.run_gold)
run ends (death, abandon or victory) -> hub: purse banked into gold, saved, "+N gold" banner
next run: Player starts with the attribute bonuses (Stats modifiers)
```

- The camp is **not reachable in browse mode**: with the browse camera on a pedestal the camp (and the training
  dummies) is off screen. A player who starts the game with gold presses Enter to choose a character and walks to the
  camp (6.3).
- Between the stages of one run the player goes to the select screen, not the hub, so the purse is **not** banked
  there: it grows through the whole run and is banked once, on the return to the hub (4.1).

## 3. The attributes

All eight are data: one `AttributeData` resource each in `data/attributes/`, listed in an explicit
`AttributeRegistry` (like `CharacterRegistry`; an export cannot list a directory reliably). Numbers below are first
guesses and live in the `.tres` files.

### 3.1 The eight
The order here is the order of the `AttributeRegistry` and of the camp screen rows.

| Attribute | Each level | At level 7 | How it is applied |
|---|---|---|---|
| **Toughness** | +8 max HP | +56 HP (Knight 100 to 156) | `Stats` add on `max_hp` |
| **Recovery** | +0.4 HP regenerated per second | +2.8 HP/s | new `Stats` key `hp_regen` (add); `Player` heals `hp_regen x delta` each physics frame while alive and below max (3.2) |
| **Might** | +3% all damage | +21% | `Stats` multiplier on `damage` of `1 + 0.03 x level` |
| **Fury** | +4% auto attack speed | +28% attacks per second | `Stats` multiplier on a new key `auto_speed` of `1 + 0.04 x level`; `cooldown_of` divides the auto attack's cooldown by it |
| **Haste** | -3% cooldowns of Q, E and R | -21% | `Stats` multiplier on a new key `cooldown` of `1 - 0.03 x level`; applies to the Q/E/R slots only |
| **Agility** | +3% movement speed | +21% (Knight 90 to 108.9) | `Stats` multiplier on the existing `move_speed` key of `1 + 0.03 x level` |
| **Focus** | +5 max mana and +0.4 mana regen/s | +35 mana, +2.8 regen/s | `Stats` adds on `max_mana` and `mana_regen` |
| **Greed** | +2 points of coin drop chance | 25% rises to 39% (on a stage with currency 0; path stages add -5 to +20 points) | added to the director's coin chance (3.2) |

- Bonuses are **linear in the level** (`level x per-level value`), not compounding, so the totals above are exact.
- They stack with the in-run upgrades and with traits (Arcane Focus) as `Stats` already combines them:
  `(base + adds) x mults`. For example Might and the Power upgrade multiply.
- Every character gets the same attributes. Max HP and max mana are added to the character's own base (the Wizard's
  90 HP becomes 146 at Toughness 7).
- **Haste and Fury are separate on purpose.** Haste shortens the cooldowns of Q, E and R only; Fury speeds up the auto attack only (the Slash or the Arcane Bolt). They never stack on one ability. Fury's +28% attacks per second at level 7 is a bit more than Might's +21% damage; tune if it is too strong.
- **Recovery** is a small trickle: 2.8 HP/s at level 7 is about 1.8% of the Knight's 156 HP per second. It does not revive and stops at max HP.
- **Hub:** the walk-mode Player also gets the attributes, so the training dummies show the real damage. The hub keeps
  its infinite mana and no damage taken.

### 3.2 Where each one plugs in (verified against the code)
- `Stats.value(key, base)` is `(base + adds) x mults`. `Player._apply_character()` calls `mana.configure()` and
  `Player._ready()` calls `health.setup(stats.value("max_hp", max_hp))`, so the attribute modifiers must be written to
  `stats` **before** those two calls (section 9).
- `damage_of()` in `AbilityCaster` already multiplies by `stats.value("damage", 1.0)`: Might needs no code change.
- `cooldown_of()` reads only the per-ability key (`"<ability id>.cooldown"`). It gets one extra factor, the same way
  `damage_of` has one: for the auto slot (`data == ability_auto`) it divides by `stats.value("auto_speed", 1.0)` (Fury);
  for Q, E and R it multiplies by `stats.value("cooldown", 1.0)` (Haste). The HUD cooldown sweep calls
  `cooldown_of`, so it follows. No other code computes a cooldown (checked: only `ability_caster.gd` and the HUD).
- Agility needs no code change: `Player` already reads `stats.value("move_speed", move_speed)` every physics frame.
- Recovery is the one new behaviour: `Player._physics_process` (not dead) calls
  `health.heal(stats.value("hp_regen", 0.0) * delta)` only when `hp_regen > 0` and `current < max_health`, so a full
  health bar does not emit `changed` every frame. In the hub nothing damages the Player, so it is a no-op there.
- Greed is not a `Stats` key on the Player: the coin chance is read in `SpawnDirector` (`stage.coin_chance()`), which
  has no Player. `main.gd` sets `spawn_director.coin_bonus` in `_ready` (before the first spawn; the director's default
  is 0, so tests that force 0% or 100% drops with `currency = +-100` are unaffected), computed by
  `CampAttributes.coin_bonus(levels)`, the sum of every attribute's `coin_chance x level`. `StageData.coin_chance()` is unchanged; the director adds the bonus and clamps to 0..1.

### 3.3 Candidates for later (not built)
Swiftness (move speed, +2% a level), Magnet (pickup radius), Learning (XP gain), Resolve (a short immunity after a hit),
Fortune (rarer level-up choices, once the pool has rarities). Adding one is a new `.tres` file and one registry line.

### 3.4 `AttributeData` (new resource, `scripts/camp/attribute_data.gd`)

| Field | Meaning |
|---|---|
| `id` | `&"toughness"` ..., unique |
| `display_name`, `description` | Shown on the camp screen (the description is one line) |
| `max_level` | 7 |
| `base_cost`, `cost_growth` | The cost formula of 5.1 (40 and 1.5) |
| `adds` | `Stats` key -> amount **per level** (applied as `amount x level`) |
| `scales` | `Stats` key -> fraction per level (applied as a multiplier `1 + fraction x level`; negative for Haste; Fury's `auto_speed` is a multiplier too) |
| `coin_chance` | Greed's points per level as a fraction (0.02). Read by `CampAttributes.coin_bonus`, not written to `Stats` |
| `summary` | Text with `{0}`, `{1}` placeholders, e.g. `"+{0} max mana, +{1} mana/s"` |
| `display_values` | The numbers for the placeholders, per level, e.g. `[5, 0.4]` |

`summary` and `display_values` are plain data that must match `adds`, `scales` and `coin_chance`; a test checks that
(as `tests/hub_data.gd` does for trait text). `AttributeData.describe(level)` returns the text for a level
(`level x display_values`), formatted with `HubInfoPanel.num`.

## 4. Gold: the run purse and banking

Today `GameSession.gold` rises the moment a coin is collected (`Coin._physics_process`), is shown by the HUD and is
kept across runs, but only in memory. v0.7 splits it in two:

| Name | Meaning | Persisted |
|---|---|---|
| `GameSession.gold` | The **banked** total you can spend | Yes (section 8) |
| `GameSession.run_gold` | Coins collected in the current run (new) | No |

### 4.1 Rules
- `Coin` adds to `GameSession.run_gold`, not `gold`.
- `GameSession.new_run()` sets `run_gold = 0`. `run_start_gold` (v0.5: gold when the run started) is removed: it
  existed only to compute the run's earnings, which `run_gold` now is.
- The in-run HUD gold number shows `run_gold`. The victory summary's `gold_earned` is `run_gold`.
- **Banking happens when the run ends, not when the player leaves the end screen**, so closing the window on the
  death or victory screen cannot lose coins the screen has just announced. `GameSession.bank_run()` returns the reward and does:
  `reward = run_gold`, `gold += reward`, `run_gold = 0`, `last_reward += reward`, then saves (section 8). It is called
  from: `finish_run()` (victory), `abandon_run()`, and `EndScreen.show_result(DEATH)` (the moment the death screen
  appears; `fail_run()` is only reached later, by the button). `go_to_hub()` also calls it, so a path that reaches the hub
  without banking cannot leave coins behind; with an empty purse it does nothing. **All coins are kept on every ending**,
  including death and abandoning.
- The **death screen shows "Gold earned N"** as the victory screen already does, since the coins are kept. Order matters: `show_result(DEATH)` takes `var reward := GameSession.bank_run()` and builds its text from `reward` (by then `run_gold` is 0), and `finish_run()` computes `gold_earned` (= `run_gold`) **before** it banks.
- Between stages of a run (`complete_stage()` to the select screen) nothing is banked.
- **Closing the game mid-run loses the run purse**, because the run never ended. (Pause menu Exit, or the window
  close, while still playing.) This is intended, and listed in section 14.
- The hub reads `GameSession.take_reward()` in `_ready()`, which returns `last_reward` and clears it, so the banner
  shows once. (`last_reward` accumulates if banking happens more than once before the hub loads.)

### 4.2 Showing it (section 7.4)
On return to the hub it shows a **"+N gold" banner** (with the coin icon and the `coin` sound) and a gold counter that
counts from the old total to the new one over about one second. With a reward of 0 nothing animates.

## 5. Costs and respec

### 5.1 Cost
The cost of buying level `n` (1 to 7) is `round(base_cost x cost_growth ^ (n - 1))`. With 40 and 1.5:

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | Total |
|---|---|---|---|---|---|---|---|---|
| Cost | 40 | 60 | 90 | 135 | 203 | 304 | 456 | 1,288 |

All eight attributes cost 10,304 gold (8 x 1,288). Rough income: a stage lasts 300 s (`RunManager.RUN_DURATION`); the spawn rate
rises from 0.8/s to 6.4/s (3.6/s on average, about 1,080 spawns per stage); a mob drops a coin 25% of the time at
value 1 (before stage modifiers). If every spawn were killed that is about 270 gold per stage and up to 810 for a
three-stage run, so a full build is roughly 13 full runs. Real income is lower (not every mob is killed; one death
ends the run). This is a first guess to tune after playing.

### 5.2 Buying
Buying level `n` needs `gold >= cost(n)`; it subtracts the cost and raises the level. At `max_level` the button is
disabled and reads "MAX". Nothing is bought partially and nothing goes negative.

### 5.3 Free respec
- **Undo** (the minus button) lowers one attribute by one level and refunds exactly the cost that level had
  (`cost(n)`), so gold is conserved and no loop can create gold.
- **Reset all** undoes every level of every attribute and refunds the total spent.
- Both are free, instant and always available (also with 0 gold), and write the save.

### 5.4 `CampShop` (new, pure logic, `scripts/camp/camp_shop.gd`)
No scene, no autoload. Static functions over a state of `gold: int` and `levels: Dictionary` (id -> int):
`cost(attr, level)`, `can_buy(state, attr)`, `buy(state, attr) -> bool`, `undo(state, attr) -> bool`,
`reset_all(state) -> int` (returns the refund), `spent(state)`. `GameSession.buy_attribute(id)`,
`undo_attribute(id)` and `reset_attributes()` call these and then save.
**Invariant (tested over random sequences):** `gold + spent == the starting gold`, levels stay within `0..max_level`.

## 6. The camp in the hub

### 6.1 Look and place
A small **tent** (a triangle of cloth), a **chest** (a box with a lid and a gold clasp), a **campfire** and a
**camper**: a character standing by the chest, drawn as placeholder shapes like the hub's sign and the dummies
(real art is later). A wood sign reads **"CAMP"**. It sits **below the training dummies**: the training area is
`TRAINING_AREA = Rect2(110, 100, 140, 120)`, so the camp is centred at `CAMP_POS = Vector2(170, 300)`. It is
decoration with **no collider**, like the pedestals; the Player walks over it. `CampSite` is a child of the hub's
y-sorted `World` node with `z_index = -1`, so it is drawn under the Player wherever the Player stands (a tent at y 300 would otherwise cover a Player walking behind it). (`hub.gd` today has a sign at
`SIGN_POS (480, 290)` and the pedestal row at y 380; the camp clears both.)

`CampSite` (new, `scripts/hub/camp_site.gd`, a `Node2D`) draws itself (static, no `_process` unless the fire is
animated) and has no click area (6.3). `hub.gd` adds `CAMP_POS` and `CAMP_RADIUS` constants and a
`Rect2(CAMP_POS.x - 50, CAMP_POS.y - 45, 100, 80)` to `reserved_areas()` so decor keeps off it. That rect is clear of
`TRAINING_AREA` (it ends at y 220) and of the pedestal rects; it may grow if the drawing needs more room.

### 6.2 Interacting (walk mode)
The `interact` action (F, gamepad A) already returns from walk mode to browse mode when the Player stands within
`INTERACT_RADIUS` (60 px) of a pedestal. Now it also opens the camp when the Player is within `CAMP_RADIUS` (48 px)
of `CAMP_POS`. The nearest pedestal is about 253 px from `CAMP_POS`, more than `INTERACT_RADIUS + CAMP_RADIUS`, so at most one target
qualifies. The prompt label (`hub.gd._process`) shows "F: Camp" near the camp; near a pedestal it keeps its
current text "F: Change character" (set in `hub.tscn`), so `_process` now sets the text as well as the visibility. The existing 0.2 s
`MODE_LOCKOUT` applies.

### 6.3 Browse mode
The camp cannot be used in browse mode. The browse camera sits on a pedestal at `(x, y - 40)` with `BROWSE_OFFSET
(90, 0)` and the view is 640 wide, so on the Knight (pedestal x 410) only x 180..820 is visible and on the Wizard (x 550)
x 320..960: the camp at x 120..220 is mostly off screen (only its right 40 px can show) and the info panel covers the right side. So it is not usable and there is no
click target. Enter chooses a character and the camp is a short walk away.

### 6.4 While the screen is open
The camp screen pauses the tree (as the level-up menu does). The hub is a pausable node, so its `_unhandled_input`
does not run while the tree is paused: the pause is the guard and the hub needs no input code for it. **If any level changed while the screen was open, the hub rebuilds its Player on close** at the same position, from the new `GameSession.attribute_levels` (the same creation path as `_enter_walk`, which also resets cooldowns and effects), because `Stats` cannot remove modifiers and attributes are applied once, at creation. So the training dummies show the new damage, speed and cooldowns at once. On close the
hub sets `_lockout = MODE_LOCKOUT` so the key that closed the screen cannot also act in the hub. `CampScreen.process_mode`
is Always (its children inherit it), and so is the `GoldCounter` in its header; tweens on pausable nodes (the banner
fade) freeze while it is open.

## 7. The camp screen

`CampScreen` (new, `scripts/ui/camp_screen.gd`, a `Control` in the hub's `UI` layer, built in code like `LevelUpMenu`,
using `UiKit` at the 640x360 base resolution with an 8 px font, which fits eight two-line rows at about 24 px each: about 190 px of rows plus the header and buttons, inside 360). It runs while the tree is paused, so its `process_mode` is Always.

### 7.1 Layout
```
+--------------------------------------------------+
|  CAMP                                  (coin) 530 |
|                                                  |
|  Toughness    [#####..]  Lv 5/7                  |
|    +40 max HP  ->  +48 max HP        304 gold  [-][+] |
|  Might        [###....]  Lv 3/7                  |
|    ...                                            |
|  (eight rows in all, in the order of 3.1)         |
|                                                  |
|  [Reset all]                              [Close] |
+--------------------------------------------------+
```
Each row: the attribute name, seven pips (filled = owned), `Lv n/7`, the summary text for the current and the next
level (`describe(level)`; Haste's values are shown as "-3%": the sign is part of `summary`, `display_values` are positive), the next cost (or "MAX"), a minus button and a plus button. The plus button is dimmed when
the player cannot afford the next level (and the price turns red); the minus button is dimmed at level 0.

### 7.2 Controls
Rows are **not** focus targets: the `[+]` and `[-]` buttons and the rows have `focus_mode = FOCUS_NONE` (mouse only),
so Enter on a focused button cannot do the wrong thing. `CampScreen` keeps a `selected_row` (0 when it opens; Up/Down
clamp at the ends; mouse hover sets it). **Reset all** and **Close** are the only focusable controls: Down from the
last row moves focus to Reset, Right to Close, Up back to the last row. **While Reset or Close has focus, the row keys (Enter buys, Left and Backspace undo) are ignored**, so Enter presses the focused button and Left only moves focus; `selected_row` is not drawn highlighted then. Keys use the built-in actions (the project
overrides none): Up/Down are `ui_up`/`ui_down`, buy is `ui_accept`, undo is `ui_left` or a raw Backspace key, close is
`pause` or `ui_cancel`.

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move between rows | Up / Down | D-pad up / down |
| Buy one level of the selected row | Enter, or click `[+]` | South |
| Undo one level of the selected row | Left arrow or Backspace, or click `[-]` | D-pad left |
| Reset all | click, or Down from the last row, then Enter | Down from the last row, then South |
| Close | Esc or click Close | B (`ui_cancel`) or Start (`pause`) |

**Esc must close the camp, not open the pause menu.** `PauseMenu._unhandled_input` marks every `pause` press as
handled (even when it cannot open), it is Always-processing and the last child of the hub's `UI`, so it would see the
event first. `CampScreen` therefore handles `pause` and `ui_cancel` in `_input()` (which runs before every
`_unhandled_input`), closes, unpauses and calls `set_input_as_handled()`. **Both of its input handlers (`_input` and the buy/undo keys) return at once unless the screen is open**; otherwise, being Always-processing, it would swallow every Esc in the hub and fire buy keys from the hub (Enter is `ui_accept`). `pause_menu.gd` needs no change (its
`_can_open()` is already false while the tree is paused).

### 7.3 Feedback
The row buttons are plain `Button`s, not `UiKit.button` (which plays `menu_click` on every press, so a buy would play two sounds). Buy: the `hub_choose` sound and a brief flash on the row. Undo: `menu_click`. Cannot afford: the plus button is only **dimmed** (`modulate`), not `disabled` (a disabled button emits no `pressed`), so a click or Enter gives the `no_mana` blip and a
red flash of the cost; at MAX it is disabled and silent. Reset all: `menu_click`. No new sound files (the sound rule in `CLAUDE.md` is not triggered).

### 7.4 Gold counter and banner
`GoldCounter` (new, `scripts/ui/gold_counter.gd`) is a coin icon and a number, drawn like `Hud._draw_gold` (the same
two circles). It is placed top right in the hub's UI and in the camp screen header. It animates a count-up when
`GameSession.gold` rises after a return (4.2). (The hub's `Hud` binds without a `RunManager`, so it draws no gold
there and there is no overlap.) The banner is a label that fades in for 2 s ("+N gold"). It is shown
from `hub.gd._ready()` when `take_reward()` returns more than 0. `take_reward()` is called and the banner started
**before** the last-character early return (`_enter_walk(...)` then `return`, `hub.gd:58-63`), not at the end of
`_ready`.

## 8. Saving

New `SaveGame` (`scripts/systems/save_game.gd`, static, no autoload).

- **File:** `user://camp.json` (JSON text), fields `version` (1), `gold` (int) and `levels` (`{attribute id: int}`).
- **When:** loaded once when `GameSession` is ready (the autoload that owns the state); written after every buy, undo,
  reset and every banking. Nothing is written during a run.
- **Safe write:** write `camp.json.tmp`, then rename it over `camp.json` (`DirAccess.rename_absolute`; checked on
  macOS that it replaces an existing file, but Godot does not promise it is atomic on every platform). On load, if
  `camp.json` is missing and `camp.json.tmp` exists, load the tmp. A write failure (`FileAccess.open` returns null)
  logs a warning, keeps the state in memory and never crashes.
- **Parsing:** `JSON.parse_string` returns null on a syntax error, floats for every number and any type for the root.
  The root must be a Dictionary with `version == 1` (any other version is a bad file); numbers are accepted only when
  `TYPE_INT` or `TYPE_FLOAT` and finite, and converted with `int()`; `levels` must be a Dictionary and its keys are
  matched as strings against the registry.
- **Bad data:** a missing file means a new game (0 gold, no levels). A file that cannot be parsed or fails the checks
  above is renamed to `camp.json.bad` (kept for inspection) and the game starts new. Values are clamped on load:
  `gold` within `0..GOLD_MAX` (999,999,999), each level within `0..max_level`, ids that no longer exist are dropped
  (their gold is not refunded; section 14).
- **Tests and tools must never touch the player's save.** `SaveGame.path()` returns `SaveGame.override_path` if a
  test set it, else the `HERO_HORDE_SAVE` environment variable if set, else an empty path (saving disabled) when
  `DisplayServer.get_name() == "headless"` (checked: `OS.has_feature("headless")` is false under `--headless`), else
  `user://camp.json`. `GameSession._ready` is the only reader of the save. A **zero-length file** (e.g. one made by `mktemp`) is a new game: no error, no `.bad` rename. `tests/run_all.sh` gives **each test its own
  fresh temporary file** (`HERO_HORDE_SAVE=$(mktemp -u)`, a path that does not exist yet, inside its loop; afterwards `rm -f "$f" "$f.tmp" "$f.bad"`) so tests that bank coins (a
  scene flow that ends a run) cannot leave levels or gold for the next test; a test that needs levels sets
  `GameSession.attribute_levels` directly. **Non-headless runs** (render runs with `--write-movie`, `tools/maps/shot_maps.gd`)
  would write the real save when they reach banking: they must set `HERO_HORDE_SAVE`, and `CLAUDE.md`'s render note
  and `tests/README.md` say so.
- No other game state is saved in v0.7.

## 9. Wiring

- `Player` gets `var attribute_levels: Dictionary` (set by the creator before the Player enters the tree, default
  empty). In `_apply_character()`, **before** `mana.configure()`, it calls
  `CampAttributes.apply(stats, attribute_levels)`. `main.gd` and `hub.gd` set `player.attribute_levels =
  GameSession.attribute_levels` (they are the high-level scenes; `Player` itself does not read `GameSession`). A Player
  made by a test with no levels is unchanged, so existing tests see no difference.
- `CampAttributes` (new, `scripts/camp/camp_attributes.gd`, static, no autoload): `apply(stats, levels)` writes the
  `adds` and `scales` of every attribute into a `Stats` (once, at creation; not re-applied on `refresh_stats`), and
  `coin_bonus(levels) -> float` sums `coin_chance x level` over the attributes (Greed's effect, which is not a `Stats` key).
- `RunProgress.restore()` is unchanged: it re-applies in-run upgrades onto a Player that already has the attributes
  (they are written in `_apply_character`, before `restore`), and its `health.setup` / `mana.configure` read the
  combined `Stats`.
- `AbilityCaster.cooldown_of()` gets the `cooldown` factor for Q/E/R (Haste) and the `auto_speed` division for the auto slot (Fury) (3.2). `Player._physics_process` gets the Recovery heal (3.2).
- `main.gd` sets `spawn_director.coin_bonus` and `SpawnDirector` adds it to `stage.coin_chance()` (clamped 0..1).
- `Coin` adds to `run_gold`; `Hud._draw_gold` shows `run_gold`.
- `GameSession`: new `run_gold`, `last_reward`, `attribute_levels`, `buy_attribute`, `undo_attribute`,
  `reset_attributes`, `bank_run` (called from `finish_run`, `abandon_run`, the death screen and `go_to_hub`),
  `take_reward`, loading in `_ready`. `run_start_gold` removed.
- `hub.gd`: the camp, its interact, the banner and counter. `CampScreen` handles Esc in `_input` (7.2), so
  `pause_menu.gd` is not edited.

## 10. File layout

```
data/attributes/            NEW: toughness.tres recovery.tres might.tres fury.tres haste.tres agility.tres focus.tres greed.tres
scripts/camp/               NEW: attribute_data.gd attribute_registry.gd camp_shop.gd camp_attributes.gd
scripts/hub/camp_site.gd    NEW: the camp drawing (no click area)
scripts/ui/camp_screen.gd   NEW
scripts/ui/gold_counter.gd  NEW
scripts/systems/save_game.gd NEW
tests/camp/                 NEW: the tests of section 11 (run_all.sh also runs tests/camp/*.gd)
```
Edited: `game_session.gd`, `coin.gd`, `hud.gd`, `hub.gd`, `hub.tscn` (the new UI nodes), `main.gd`, `player.gd`,
`ability_caster.gd`, `spawn_director.gd`, `end_screen.gd` (banks on the death screen; "Gold earned" on both),
`tests/run_all.sh` (a per-test save file, and the new `tests/camp/*.gd` glob in its `for` line), `CLAUDE.md` (the render
note), `README.md`, `tests/README.md`. Run `godot --headless --path . --import` after adding the `class_name` scripts and
commit the generated `.uid` files.

## 11. Tests (`tests/camp/`)

New tests that name the new `class_name` types use `preload`, and ones that touch a Player use untyped variables and
`tests/fixture.gd` (the rules in `CLAUDE.md`). Randomised checks use 30 seeds.
- `camp_shop.gd` (pure): the cost table; buy needs gold and stops at 7; undo refunds exactly; reset refunds the total;
  nothing goes negative; over 30 seeds of random buy/undo sequences `gold + spent` never changes.
- `camp_save.gd`: round trip; a missing file; a corrupt file is moved to `.bad` and the game starts new; clamping of
  gold and levels; an unknown id is dropped; the temp file is not left behind; saving is off when headless with no
  path (the player's real file is never written).
- `camp_attributes.gd`: each attribute's total at levels 0, 1 and 7 against section 3.1 (max HP, HP regen, damage, auto speed, cooldown,
  move speed, mana, mana regen, coin chance); the data's `display_values` match `adds`/`scales`/`coin_chance`; `cooldown_of` for Q/E/R
  falls by 3% per Haste level and stacks with a per-ability upgrade, while the auto attack's cooldown divides by `1 + 0.04 x Fury` and ignores Haste; Recovery heals over time, stops at max HP and does nothing when dead; Agility raises the Player's velocity; a Player with no levels is unchanged; the
  hub Player has the bonuses and still has infinite mana; Might and the Power upgrade multiply; the director's coin
  chance with Greed is clamped to 1.
- `camp_gold.gd`: a coin raises `run_gold` and not `gold`; the death screen, abandon and victory each bank the purse once
  (before the hub is reached, and not twice when `go_to_hub` follows) and set `last_reward`; `take_reward` returns it once; the purse is 0 after banking and after `new_run`; nothing is banked on
  `complete_stage`; the HUD number and the victory summary use `run_gold`.
- `camp_site.gd` (hub scene): the camp exists at `CAMP_POS`, clear of the training area, the pedestals, the sign and
  the door lane; decor avoids its reserved rect; interact near it opens the screen; interact near a pedestal still
  goes back to browse; interact does nothing in browse mode; the prompt text near each target; the hub's lockout after
  the screen closes.
- `camp_screen.gd`: with the camp closed, Esc still opens the `PauseMenu` and Enter does not buy; buy, close, and the hub Player's `stats.value("damage")` has changed (the Player was rebuilt); a click on an unaffordable plus gives the `no_mana` blip and buys nothing; row keys do nothing while Reset has focus; a zero-length save file is a new game with no `.bad` file; rows for all eight attributes; buy and undo by mouse and by key (rows are not focus targets, Enter on
  Reset does not buy); the plus button is dimmed when the player cannot pay and the cost turns red; MAX at level 7;
  reset all refunds; **Esc with the camp open closes it, leaves `PauseMenu` hidden and `paused == false`**; the tree is
  paused while open; each change writes the save.
- Updated existing tests (found by reading them): `gold.gd` (lines 45 and 75 read `gold` and become `run_gold`; the
  persistence check at line 84 becomes the purse and banking), `run_progress.gd` (lines 33, 101, 106, 125 and 129 read or
  set `gold` / `run_start_gold`), `stage_flow.gd` (line 103, `_gs.gold += 0`, is a no-op to delete),
  `select_screen.gd` and `scene_flow.gd` (their abandon and hub paths now bank, which is harmless with a per-test save
  file). `hub_walk.gd` needs only a new camp case. The final list of changed tests is written into the decision log.
- Rendering is not covered by tests: render the hub and the camp screen to PNGs per `CLAUDE.md` and look at them.

## 12. Build order

1. **Data and logic:** `AttributeData`, the eight `.tres` files, `AttributeRegistry`, `CampShop`, `CampAttributes`;
   `camp_shop.gd` and the data checks of `camp_attributes.gd`.
2. **Saving:** `SaveGame`, the `GameSession` fields and methods (`gold` load, `attribute_levels`, buy, undo, reset),
   `run_all.sh` (per-test save file, the `tests/camp/*.gd` glob) and the render note; `camp_save.gd`.
3. **The purse and banking:** `run_gold`, `Coin`, `Hud`, `bank_run` at the run end, `take_reward`, `end_screen.gd`;
   `camp_gold.gd` and the updates to `gold.gd` and other existing tests.
4. **Effects in play:** `Player.attribute_levels` and `apply` (before `mana.configure`), `main.gd` and `hub.gd` pass the
   levels, the `cooldown`/`auto_speed` factors, the Recovery heal, Greed through the director; the rest of `camp_attributes.gd`.
5. **The camp in the hub:** `CampSite`, reserved area, interact, prompt text; `camp_site.gd`.
6. **The camp screen:** `CampScreen`, `GoldCounter`, the banner, controls, feedback, Esc handling in `_input`;
   `camp_screen.gd`.
7. **Render and tune:** render the hub with the camp and the screen at a few gold amounts, look at them, adjust
   positions and text; play a short run to see the banking; README and tests README; run the full suite.

## 13. Compatibility

- The in-run level-up pool, the upgrade data, the stage modifiers and spawn numbers are untouched.
- A new game has no save, so 0 gold and no attributes: the game plays exactly as before until something is bought.
- `GameSession.gold` still exists and still means "the gold the player has", now meaning banked gold; code that read it
  during a run (the HUD, the victory summary, tests) moves to `run_gold` (step 3).
- A Player created without `attribute_levels` (tests, the map preview, `fixture.gd`) is exactly as before.
- No new physics layer and no new collider: the camp is drawn only.

## 14. Open questions / assumptions to revisit

- **Costs and income are first guesses** (5.1). Tune after real play: the cost base, the growth, the coin value, or the
  per-level bonuses.
- **Closing the game mid-run loses that run's coins** (once the run has ended they are already banked and saved).
  It can feel harsh. Alternative: bank on every stage clear.
- **Death and abandoning keep all coins.** The easy choice; a penalty (for example half on abandon) is a later design
  decision.
- **Doc comments to update when built:** the `GameSession` header ("nothing is saved to disk") and the `gold` comment.
- **Removed attributes** drop out of the save without a refund. Fine while there are eight; a later version that removes
  one should refund its levels.
- **Haste is one factor for Q, E and R.** A per-ability version is possible later. Fury is the auto attack's own speed.
- **The info panel shows base stats.** It does not include attribute bonuses; the camp screen shows what each level
  gives. Worth revisiting once players ask "what are my stats now?".
- **Interact prompt:** `hub.tscn` has one fixed text, "F: Change character"; `hub.gd._process` now also sets it ("F: Camp" near the camp).
- **Placeholder camp art.** Drawn shapes, like the hub's sign; real sprites later.
- **No cap on total gold** and no gold sink beyond attributes yet; once everything is bought gold piles up until a
  later version adds more to buy.

## 15. Definition of Done for v0.7

- Eight attributes of 7 levels each, with the exact effects of section 3.1, are bought, undone and reset at a camp in
  the hub, shared by every character.
- The camp stands under the training dummies, does not overlap the pedestals, sign, door lane or dummies, and opens
  by interact in walk mode.
- The camp screen works with keyboard, mouse and gamepad, shows gold, level, next effect and cost, and closes on Esc
  without opening the pause menu.
- A coin picked up in a run goes to the run purse; when the run ends (death screen, abandoning or victory) the purse is
  added to gold exactly once and saved, and the hub then shows "+N gold" and a counter; nothing is banked between
  stages.
- Respec is free and exact: undo and reset return precisely the gold spent, and gold plus spent gold is conserved.
- Attribute bonuses apply to every character in runs and in the hub; a new game with no purchases is unchanged.
- Gold and levels survive closing and reopening the game; a corrupt or missing save never crashes; tests and tools never
  write the player's save.
- All tests of section 11 pass, the existing suite passes (the listed updates aside), and `tests/run_all.sh` passes on
  a fresh clone.
