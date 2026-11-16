# Spec v0.5: Stage Path (level select)

Builds on spec v0.4 (the Hub). Status: draft rev 3, after second review.

Terms: in this document columns are numbered 1 to 3. In code `current_column` is 0-based (0, 1, 2).

## 1. Scope

A run is no longer a single arena fight. It is a **path of three stages**. Before each stage the player sees a
**stage select screen** showing a branching map, and picks one stage from the ones their path allows. Beating the
stage returns them to the select screen. Beating the last stage wins the run.

**A stage is won by surviving 5 minutes** (the existing 300 s `RunManager.RUN_DURATION`). A full run is therefore
about 15 minutes.

In scope:
- The stage select screen (UI, input, preview cards).
- The path graph: 3 columns (3 + 3 + 1 stages), randomised each run.
- Per-stage arena modifiers (the arena scene is reused).
- Gold: a new currency that drops from mobs, is stored and is shown on the HUD.
- Run flow changes: door -> select screen -> stage -> select screen ... -> victory / death.
- `GameSession` state for the current path.

Out of scope (later): distinct map scenes per stage, spending gold (trade system), rewards or shops between stages,
saving progress to disk, swapping character mid-run, more than 3 columns, more than 3 stages per column.

## 2. Flow

```
HUB (walk mode) --door--> SELECT (column 1) --pick--> STAGE --win--> SELECT (column 2) --pick--> STAGE --win-->
SELECT (column 3) --pick--> STAGE --win--> VICTORY --> Return to Hub

STAGE --death--> DEATH screen --> HUB   (path is discarded)
Any SELECT screen or STAGE pause menu --abandon--> HUB   (path is discarded)
```

- Walking into the hub door (v0.4 section 6.1) now opens the select screen instead of loading the run directly.
- Character is fixed for the whole run: the character chosen in the hub when the door was entered.
- A new door entry always generates a **new path** and starts at column 1.
- Death ends the run: the player returns to the hub (walk mode, as `last_character`) and the path is thrown away.
- Winning the final stage ends the run in victory; the player returns to the hub.
- Abandoning (the stage pause menu's "Return to Hub", or "Abandon run" on a select screen) discards the path.
- Nothing is saved to disk. The path lives in `GameSession` while the game is open.

## 3. The path graph

### 3.1 Shape
- 3 columns. Columns 1 and 2 each have **3** stages, stacked top, middle and bottom. Column 3 has **1** stage (the
  final stage). That is 7 stages in all.
- Edges only go from a stage to stages in the **next** column. No edges skip columns or go backward.
- Every column 2 stage leads to the final stage.

### 3.2 Connections ("two nearest")
You can only reach the stages next to the one you beat. Connections are by **position** (top, middle, bottom)
between columns 1 and 2:

| Beaten stage | Can pick in the next column |
|---|---|
| Top | top and middle |
| Bottom | middle and bottom |
| Middle | the middle **plus one random neighbour** (top or bottom), rolled once per run |

```
col 1       col 2       col 3
top    ---> top
top    ---> middle
middle ---> middle
middle ---> bottom     (rolled once per run: could be top instead)
bottom ---> middle
bottom ---> bottom
                        every col 2 stage ---> final
```

- After column 1 a player always has exactly **2** options, never all 3 and never just 1.
- Every column 2 stage is reachable from at least one column 1 stage (top from top, bottom from bottom, middle
  from all), so nothing is unreachable.
- Tiers in a column are all different (section 4.1), so the two options offered always **differ in tier**. They
  are not guaranteed to include an Easy one or a Hard one (it can be Normal and Hard, or Easy and Normal).
- The middle stage's neighbour is the only random edge.
- **Seed:** `GameSession.path_seed` is chosen with `randi()` on each new run. The edge roll, the tier order, the
  stage values, the names and the thumbnails are **all** derived from one seeded `RandomNumberGenerator`, so a
  seed reproduces the whole path (used by tests).

### 3.3 Selecting
- In column 1 the player may pick any of the 3 stages.
- In column 2 the player may pick only the **2** stages connected to the stage they just beat (3.2). The third is locked.
- In column 3 there is only the final stage.
- Only one stage can be chosen at a time; there is no way to revisit a beaten column.

## 4. Stage parameters

Every stage reuses the existing cave arena (`main.tscn`) and the same map layout. Stages differ only by a
`StageData` resource (new) that is applied before the arena starts. Map layouts per stage are a later release.

All modifiers are stored as **whole percentages added to the base**, where 0% is today's behaviour. They are never
multiplied together: `+10%` means base plus 10.

| Field | Type | Effect |
|---|---|---|
| `name` | String | Display name, unique within a path, drawn from a list of at least 7 names |
| `thumbnail` | Texture | **Appearance.** A different thumbnail per stage; the only visual difference for now (see 4.4) |
| `tier` | enum | `EASY`, `NORMAL` or `HARD`. Drives the rolled values (4.1) and is shown on the card |
| `population` | int percent | **Population.** Spawn rate and alive cap change by this percent (`+20` = 20% more) |
| `difficulty` | int percent | **Difficulty.** A **display-only** value shown on the card (`+5%`). It changes no gameplay in v0.5 (see 4.3) |
| `experience` | int percent | **Experience.** XP gained from kills changes by this percent |
| `currency` | int percent | **Gold.** Percentage **points** added to the coin drop chance (4.2): `+10` takes 25% to 35% |

### 4.1 Rolling values
Harder stages pay more. There is no re-roll rule; the ranges below are chosen so a harder tier pays more experience
and gold than an easier one almost always (Easy and Normal gold can both be 0).

- Every stage rolls a **tier**, then rolls each value from that tier's range in steps of 5:

| Tier | Population | Difficulty | Experience | Gold |
|---|---|---|---|---|
| `EASY` | -20..-10 | -10..-5 | -15..-5 | -5..0 |
| `NORMAL` | -5..+5 | -5..+5 | 0..+10 | 0..+5 |
| `HARD` | +10..+20 | +5..+10 | +15..+30 | +10..+20 |

- Tier assignment:
  - **Column 1** (3 stages): one `EASY`, one `NORMAL`, one `HARD`, in a random order.
  - **Column 2** (3 stages): also one `EASY`, one `NORMAL`, one `HARD`, in a random order.
  - **Column 3** (final): always `HARD`, rolled from the HARD ranges. A single stage with no choice.
- Everything above is a first guess: tune the ranges while playing.

### 4.2 Gold
- Gold is a new, simple number: coins.
- When a mob dies there is a **25%** base chance it drops one coin at its position. The stage's gold value is
  **added** to this: chance = `25% + currency` (so `+10` gives 35%, `-5` gives 20%), clamped to 0..100%. Mobs
  that drop no XP (the hub training dummies) drop no coins either.
- A coin is worth **1** and adds to `GameSession.gold`.
- **Pickup system:** coins reuse the XP gem system rather than adding a new one. `Pickups` gains a second pool and
  `spawn_coin(pos)`; a `Coin` is a small `Area2D` like `XPGem` that implements `attract(player)`, so the player's
  existing `XPCollector` pulls it in with the same acceleration, and on arrival it adds to `GameSession.gold`
  and plays a coin sound.
  - `XPCollector` currently filters on `area is XPGem` (`xp_collector.gd`). Change that check to
    `area.has_method("attract")` so any pickup that implements `attract(player)` is pulled in.
  - `Coin` is its own scene (`coin.tscn`) and script on the same physics layer as gems (layer 16, which the
    collector's mask already covers). `Pickups` gets a `coin_scene` export and a separate coin pool. `Coin` does
    not extend `XPGem` (`XPGem.pool` is typed `Pickups` and its arrival code adds XP), but copies its movement.
- Coins that are not collected stay for the rest of the stage and are released back to the pool when it ends.
  Coins and XP gems on the ground or in flight when the stage ends are lost. This is intentional.
- **HUD:** a coin icon (a drawn yellow circle for now) and the gold number, in the run HUD at the right under the
  kills counter. It updates immediately. The hub HUD does not show gold in v0.5.
- No spending yet. A trade system comes in a later spec, and gold is only stored and shown.

### 4.3 Applying the modifiers (arena side)
`main.gd` reads `GameSession.current_stage` and passes it to the arena systems before the stage starts.
- **Population:** `SpawnDirector` multiplies both its spawn rate (`start_rate` and `end_rate`) and its `alive_cap`
  by (1 + `population`/100). The scaled `alive_cap` is **capped at the existing 300** so the crowd performance
  budget still holds. `hp_scale_per_minute` is not touched and restarts each stage.
- **Difficulty:** display only. It is rolled and shown on the card, but **no damage is modified**: there is no
  hook in `Hurtbox` and no multiplier on contact, dash or projectile damage. A real effect can be added later.
- **Experience:** in `SpawnDirector._on_enemy_died` the gem value is `maxi(1, roundi(xp_drop * (1 + experience/100)))`
  for any mob whose `xp_drop` is above 0. A mob with `xp_drop` 0 stays at 0.
- **Gold:** see 4.2.
- **Modifiers last for one stage only.** Every modifier (including Experience) applies only while the stage it
  belongs to is being played and is dropped when the stage ends. Only the *results* carry over (the extra XP and
  levels earned, the gold collected). The next stage uses only its own modifiers.
- With no `StageData` (running `main.tscn` from the editor) every modifier is 0%.

### 4.4 Thumbnails
- Tests only check that a path assigns 7 distinct thumbnail resource paths (headless tests do not render them).
- Seven placeholder thumbnails are generated by a script in `tools/` (like the sound generator), saved under
  `assets/stages/`, one per stage in a path. A path uses 7 different thumbnails taken from a pool of at least 7.

## 5. Stage select screen

### 5.1 Layout
- Full-screen UI on the cave-style background used by the hub. Three vertical columns, left to right, matching
  the path columns. Stages in a column are stacked vertically.
- Each stage is a **card**: thumbnail, name, a tier label (Easy / Normal / Hard) and the four modifiers as rows with
  a signed percentage (e.g. `Population +15%`, `Difficulty +5%`, `Experience +20%`, `Gold +10%`).
  Population and Difficulty are tinted red when positive (harder; Difficulty is only a label), Experience and Gold green when positive (better).
- Lines are drawn from each stage to the stages it connects to in the next column.

### 5.2 Card states
- **Beaten**: dimmed, with a check mark. Shown for the stage(s) on the path taken so far.
- **Available**: bright, selectable. In the current column, and reachable from the last beaten stage.
- **Locked**: dim and not selectable. Everything in the current column that is not reachable, and all later columns
  (later columns still show their cards and connection lines as a preview).
- Lines leading from the beaten stage to its available stages are highlighted; other lines are muted.

### 5.3 Input
- Input uses real project actions: `ui_up` / `ui_down` move the cursor, `hub_confirm` starts the stage, `pause`
  opens the abandon prompt. (New actions are not added.)
- `ui_up` / `ui_down` work through Godot's built-in defaults (arrows, D-pad, stick); also accept `move_up` / `move_down`
  so W and S work like A and D in the hub.
- The cursor moves between **available** cards only, skips locked cards, and wraps around. It starts on the first available card.
- Mouse: hovering an available card moves the cursor to it; a click starts the stage. A click on a locked card does nothing.
- `pause` (Esc) on a select screen at any column opens a prompt "Abandon this run?" with Yes / No. Yes calls
  `GameSession.abandon_run()`.
- The select screen ignores all input while `SceneFader.busy`.

### 5.4 Transitions
- Door -> select screen: fade out/in through `SceneFader` (v0.4 section 6.5).
- Select -> stage: fade out/in, then the arena starts with the chosen `StageData`.
- Stage win -> select screen: a "Stage cleared" banner for 2 s (the game is paused, input blocked), then
  fade out/in to the select screen. There are no buttons on this banner.

## 6. Run flow changes

- The arena ends in one of three ways: **win** (survive 5 minutes), **death**, or **abandon** (pause menu).
- **Stage state:** each stage starts a fresh arena: the run clock, kills and the spawn ramp restart.
  - **Carries over between stages of a run:** the player's **level, XP (progress to the next level) and the
    upgrades chosen at level-ups**. Gold also carries over (and beyond the run, section 7).
  - **Resets each stage:** HP, mana, cooldowns and position. The player starts each stage at full health.
  - Carried progress is stored in `GameSession` at the moment a stage is won (`GameSession.run_progress`) and
    applied to the new Player when `main.gd` builds it. It is cleared when the run ends (death, abandon, victory).
  - Stage-end sequencing is in 6.2, and how progress is restored is in 6.3.
- Win in column 1 or 2: the "Stage cleared" banner (5.4), `GameSession.complete_stage()` records the stage, then the
  select screen loads.
- Win in column 3: shows the **victory** screen with **Return to Hub** only. It shows stages cleared (3 of 3), total
  kills over the run, gold earned this run and the final level.
- Death: shows the **death** screen with **Return to Hub** only. It shows the stage reached (for example "Stage 2"),
  the kills in that stage, and the time survived and level as today. Return to Hub calls `fail_run()`. The existing
  1.2 s delay before the death screen still applies.
- Restart is removed everywhere (a restart would skip the path; the door starts a new run instead).

### 6.1 End screen and pause menu
- `end_screen.gd` gets a mode: `DEATH` or `VICTORY`. The Restart button and its focus code are removed, and focus
  goes to Return to Hub. The "Stage cleared" banner (5.4) is a separate, simpler control, not the end screen.
- `pause_menu.gd`'s "Return to Hub" (label kept) first asks "Abandon this run?" (Yes / No), the same prompt as the
  select screen, and on Yes calls `GameSession.abandon_run()` instead of `go_to_hub()`.
- The run HUD also shows the current stage (for example "Stage 2/3 - Mossy Hollow"), read from `GameSession`.

### 6.2 Stage end sequencing (who decides)
`RunManager` still emits `run_ended(true)` at 300 s, but **`main.gd` handles it**, not `end_screen`:
1. `main.gd` waits until the level-up menu is closed (`level_up_menu.active == false`; poll each frame or use a
   new `closed` signal). This covers a level-up pending or queued at the 300 s mark: no level is lost and the
   banner never appears on top of the menu.
2. It then asks `GameSession.is_last_stage()`:
   - **No (columns 1 and 2):** show the "Stage cleared" banner for 2 s using `get_tree().create_timer(2.0, true)`
     (the `true` makes the timer ignore pause; the tree is paused, so a default timer would never fire), then call
     `GameSession.complete_stage()`, which saves the progress and loads the select screen.
   - **Yes (column 3):** call `GameSession.finish_run()` (below) and show the VICTORY end screen.
3. The pause menu cannot open during the banner (`pause_menu._can_open` already blocks Esc while the tree is paused).
4. Death is unchanged: `RunManager` emits `run_ended(false)` after its 1.2 s delay and `main.gd` shows the DEATH screen.

Suggested approach for the victory data: `GameSession` accumulates `run_kills` (added to in `complete_stage()` and
`finish_run()` from `RunManager.kills`, which resets per stage) and records `run_start_gold` when the run starts, so
gold earned = `gold - run_start_gold`. `finish_run()` snapshots these into a small `run_summary` that the VICTORY
screen reads, then clears the path. Return to Hub on the victory screen just calls `go_to_hub()`.

### 6.3 Restoring carried progress
`run_progress` holds the level, XP, and a copy of the upgrade levels (`upgrades.levels`, id to level).
When `main.gd` builds the Player for a stage with saved progress:
- It restores **after** `add_child(player)`, because the upgrade pool is only set in `Player._ready`.
- XP: assign `xp.level` and `xp.xp` directly and emit only the `changed` signal. Do **not** call `xp.add()`, which
  would emit `leveled_up` and open the level-up menu. Do this before connecting `leveled_up`.
- Upgrades: replay `upgrades.apply(data)` once per saved level for each id, looked up in `upgrades.pool`. Stats are
  recomputed by `apply()`.
- Afterwards re-run `health.setup(stats.value(&"max_hp", max_hp))` (and mana) so HP and mana start **full at the
  upgraded maximum**.
- Test: a stat-changing upgrade survives a stage change, the HP maximum is correct, and no level-up menu opens on
  restore.

## 7. GameSession

New state (in-memory only):
- `path`: the generated graph (columns, stages, edges). `null` outside a run.
- `path_seed`: the seed used.
- `current_column`: 0, 1 or 2 (0-based).
- `beaten`: the stage taken in each column so far.
- `current_stage`: the `StageData` of the stage being played. `null` outside a run.
- `run_kills`: kills accumulated over the run's cleared stages. `run_start_gold`: gold when the run started.
  `run_summary`: the snapshot the VICTORY screen reads (see 6.2).
- `run_progress`: the player's carried level, XP and chosen upgrades (see 6). `null` at the start of a run
  and outside a run.
- `gold`: int. Unlike the path it is **not** reset when a run ends, so it will be there for the future trade system
  in the hub. It lives only while the game is open (nothing is saved to disk).
- New scene path constant `SELECT` for the select screen.

New or changed methods:
- `start_run(character)`: sets `character` and `last_character`, generates a new path, and loads the select screen
  instead of `main.tscn`.
- `available_stages()`: stages in `current_column` reachable from the last beaten stage.
- `select_stage(stage)`: sets `current_stage`, loads the arena.
- `is_last_stage()`: true when `current_column` is 2.
- `complete_stage()`: records the win, adds the stage's kills to `run_kills`, saves `run_progress` from the Player and
  advances the column (columns 1 and 2 only).
- `finish_run()`: used for the final stage: snapshots `run_summary` and clears the path and `run_progress`.
- `fail_run()` / `abandon_run()`: clear `path`, `current_stage` and `run_progress`, then call `go_to_hub()`.
- `go_to_hub()` is unchanged apart from being called by the two methods above.
- `restart_run()` from v0.4 is removed, and its caller in `end_screen.gd` is removed with it.
- `main.tscn` must still run on its own from the editor: if no `current_stage` is set, it uses a default
  `StageData` (all modifiers 0%), so the existing editor workflow and tests keep working.

## 8. Sounds
- Reuse the existing `hub_focus` (cursor move) and `hub_choose` (confirm).
- New sounds `stage_clear` and `coin`: each added in three places: the `SOUNDS` list in `audio.gd`, `tools/gen_sfx.py`,
  and the generated file in `assets/audio/` (missing files are skipped silently, so check all three).

## 9. Build order

1. `StageData` resource, default stage, and the arena modifiers: population and experience (4.3; difficulty is display only), with
   unit tests for the modifier math.
2. Gold: `Coin`, `Pickups.spawn_coin`, drop chance, `GameSession.gold`, HUD number, with a test for the drop chance
   clamping.
3. Path generator (pure logic, no UI) with tests for the connections in 3.2, the tier rules in 4.1 and seed
   reproducibility.
4. `GameSession` path state and methods (section 7), including `run_progress` (save on stage win, restore when
   the Player is built) and removing `restart_run()`. Test: level, XP and upgrades survive a stage change and are
   cleared when the run ends.
   **Existing tests that break are left broken for now** (`tests/scene_flow.gd` uses `restart_run()`, expects
   `start_run` to load the arena and looks for the pause menu button; the `tests/README.md` table is stale).
   They will be updated in a later pass.
5. End screen modes, pause menu rewire and the "Stage cleared" banner (section 6).
6. Select screen with static data, then hooked to the generator.
7. Wire the hub door to the select screen and the win/death/abandon flows (including section 6.2).
8. Thumbnails, polish: lines, card states, transitions, sounds.

## 10. Open questions / assumptions to revisit

- **Carried state** (confirmed): level, XP and upgrades carry over. HP, mana and cooldowns are assumed to reset
  to full each stage; say if HP should carry too.
- **Difficulty is display only:** it changes no damage in v0.5. Decide later whether it should scale enemy damage.
- **Difficulty curve:** because the player keeps getting stronger, later stages may need higher base difficulty.
  Tune the HARD ranges and the final stage after playing.
- **Gold persistence:** assumed gold carries across runs (and death) for the later trade system.
- **Gold value:** every coin is worth 1; no coin tiers.
- **Final stage as a boss:** the final stage is just the HARD tier with the normal 5 minute win.
- **Revisit and rewards:** no way to revisit a column, and no rewards for stage choice yet.
- **Middle stage neighbour:** the middle stage always reaches the middle stage of the next column plus one random
  neighbour. Revisit if more columns are added.
- **Final stage select:** the select screen still appears with one card before the final stage.
- **Run length:** about 15 minutes. Shorter stages may be wanted later; the duration is `RunManager.RUN_DURATION`.

## 11. Definition of Done for v0.5

- Walking into the hub door opens the select screen and shows all 7 stages (3 + 3 + 1) with connection lines.
- On the column 1 screen all 3 stages are selectable. On the column 2 screen only the 2 stages connected to the
  beaten stage are selectable and the third is visibly locked.
- Level, XP and chosen upgrades carry from one stage to the next; HP starts full. They reset on death, abandon
  and victory (a new run starts at level 1).
- Surviving 5 minutes in a stage shows "Stage cleared", then returns to the select screen with the next column
  active and the beaten stage marked.
- Beating the final stage shows victory and returns to the hub; the next door entry gives a **new** path.
- Dying returns to the hub and discards the path. Abandoning (pause menu, or Esc on a select screen) does the same.
- There is no Restart button anywhere.
- Each stage shows name, thumbnail, tier and its four modifiers on its card. Population, experience and gold are applied by the arena; difficulty is display only.
- Mobs drop coins at 25% plus the stage's gold value (clamped to 0..100%); picked-up coins increase the gold number
  on the HUD; gold survives death and a new run.
- Tests pass (except the old tests noted in the build order, which are left broken for now): the connections in 3.2, the tier assignment and value ranges in 4.1, seed reproducibility, additive
  percentage maths and drop chance clamping, over at least 1000 seeds where random.
- `main.tscn` still launches directly from the editor.
