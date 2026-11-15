# Spec v0.5: Stage Path (level select)

Builds on spec v0.4 (the Hub). Status: draft for review.

## 1. Scope

A run is no longer a single arena fight. It is a **path of three stages**. Before each stage the player sees a
**stage select screen** showing a branching map, and picks one stage from the ones their path allows. Beating the
stage returns them to the select screen. Beating the last stage wins the run.

In scope:
- The stage select screen (UI, input, preview cards).
- The path graph: 3 columns, randomised each run.
- Per-stage arena parameters (the arena scene is reused).
- Run flow changes: door -> select screen -> stage -> select screen ... -> victory / death.
- `GameSession` state for the current path.

Out of scope (later): distinct map scenes per stage, spending gold (trade system), rewards or shops between stages, saving progress to disk,
swapping character mid-run, more than 3 columns.

## 2. Flow

```
HUB (walk mode) --door--> SELECT (column 1) --pick--> STAGE --win--> SELECT (column 2) --pick--> STAGE --win-->
SELECT (column 3) --pick--> STAGE --win--> VICTORY --> Return to Hub

STAGE --death--> DEATH screen --> HUB   (path is discarded)
```

- Walking into the hub door (v0.4 section 6.1) now opens the select screen instead of loading the run directly.
- Character is fixed for the whole run: the character chosen in the hub when the door was entered.
- A new door entry always generates a **new path** and starts at column 1.
- Death ends the run: the player returns to the hub (walk mode, as `last_character`) and the path is thrown away.
- Winning the final stage ends the run in victory; the player returns to the hub.
- Leaving through the run pause menu ("Return to Hub", v0.4) also discards the path (abandons the run).
- Nothing is saved to disk. The path lives in `GameSession` while the game is open.

## 3. The path graph

### 3.1 Shape
- 3 columns. Column 1 has **3** stages, column 2 has **2**, column 3 has **1** (the final stage).
- Edges only go from a stage to stages in the **next** column. No edges skip columns or go backward.

```
col 1       col 2       col 3
stage 1 --> stage A --> final
stage 2 --> stage A
stage 2 --> stage B
stage 3 --> stage B
        (stage A and B both lead to final)
```

(The edges shown are one possible roll, see 3.2. Stage 1 can only reach A; stage 2 can reach A and B.)

### 3.2 Randomisation
Each run rolls the **edges** and the **stage parameters** (section 4).

Edge rules (a generated graph must satisfy all of them, otherwise re-roll):
1. Every column 1 stage has between 1 and 2 outgoing edges.
2. Every column 2 stage has **at least one incoming** edge (nothing unreachable) and exactly one outgoing edge
   to the final stage (the final is always reachable from every column 2 stage).
3. At least one column 1 stage has 2 outgoing edges, so there is always one real choice in column 2.
4. At least one stage in column 1 has no edge to some column 2 stage (so the choice in column 1 matters).
5. Every column 1 stage is selectable at the start; selection in column 1 is never restricted.

Use a seeded `RandomNumberGenerator` stored in `GameSession.path_seed` so a path can be reproduced for tests.

### 3.3 Selecting
- In column 1 the player may pick any of the 3 stages.
- In column 2 the player may pick only stages **connected to the stage they just beat**.
- In column 3 there is only the final stage.
- Only one stage can be chosen at a time; there is no way to see-and-skip ahead or revisit a beaten column.

## 4. Stage parameters

Every stage reuses the existing cave arena (`main.tscn`) and the same map layout. Stages differ only by a
`StageData` resource (new) that is applied before the arena starts. Map layouts per stage are a later release.

| Field | Type | Effect |
|---|---|---|
| `name` | String | Display name, rolled from a short list (e.g. "Mossy Hollow") |
| `thumbnail` | Texture | **Appearance.** A different thumbnail per stage; the only visual difference for now |
| `population` | float multiplier | **Population.** Scales the number of mobs the arena spawns (1.0 = today's amount) |
| `difficulty` | float multiplier | **Difficulty.** Scales the damage mobs deal to the player (above 1.0 = harder, below 1.0 = easier) |
| `experience` | float multiplier | **Experience.** Scales XP gained from kills |
| `currency` | float multiplier | **Currency.** Scales the coin drop chance (section 4.2) |

### 4.1 Rolling values
- Each field is rolled per stage when the path is generated, from a small set of steps so the cards stay easy to
  read: `0.75`, `1.0`, `1.25`, `1.5` (shown as -25%, base, +25%, +50%).
- The rolls are linked so a stage is a trade-off, not a free upgrade:
  - A stage's **risk score** is `population + difficulty` (each step above 1.0 counts as +1, below 1.0 as -1).
  - A stage's **reward score** is `experience + currency` (same counting).
  - Reward score must be within 1 of the risk score. Re-roll the stage until it is.
- Column bias: column 1 stages roll risk in -1..+1, column 2 in 0..+2, and the final stage in +1..+3.
- The final stage still uses the same fields; nothing special beyond the higher risk range.
- Exact step values and the bias are first guesses: tune them while playing.

### 4.2 Currency
- Currency is a new, simple number: gold coins.
- When a mob dies there is a **25%** base chance it drops one gold coin at its position. The stage's `currency`
  multiplier scales this: chance = `0.25 * currency` (so 1.25 gives 31.25%, 0.75 gives 18.75%). The chance is
  clamped to 100%.
- A coin is a small pickup: the player collects it by walking over it (same pickup range as other drops if any
  exist, otherwise a 12px radius). It is worth **1** and adds to `GameSession.gold`.
- Coins that are not collected stay for the rest of the stage and vanish when it ends. No magnet in v0.5.
- HUD: a gold number with a coin icon, placed in the HUD next to the kills counter. It updates immediately.
- No spending yet. A trade system comes in a later spec, and gold is only stored and shown.

### 4.3 Applying the multipliers (arena side)
- **Population:** multiplies the spawner's target mob count, rounding to the nearest whole mob, minimum 1.
- **Difficulty:** multiplies damage dealt to the Player by mobs (contact, projectiles, dasher dash). It does not
  change mob health or speed.
- **Experience:** multiplies XP granted per kill (rounding up, so any kill gives at least 1).
- **Currency:** see 4.2.
- With no `StageData` (running `main.tscn` from the editor) all multipliers are 1.0.

## 5. Stage select screen

### 5.1 Layout
- Full-screen UI on the cave-style background used by the hub. Three vertical columns, left to right, matching
  the path columns. Stages in a column are stacked vertically.
- Each stage is a **card**: thumbnail, name, and the four modifiers as rows with a signed percentage
  (e.g. `Population +25%`, `Difficulty -25%`, `Experience +50%`, `Currency base`). Harmful values are tinted red and
  beneficial ones green; for Population and Difficulty "more" is harder, for Experience and Currency "more" is better.
- Lines are drawn from each stage to the stages it connects to in the next column.

### 5.2 Card states
- **Beaten**: dimmed, with a check mark. Shown for the stage(s) on the path taken so far.
- **Available**: bright, selectable. In the current column, and reachable from the last beaten stage.
- **Locked**: dim and not selectable. Everything in the current column that is not reachable, and all later columns
  (later columns still show their cards and connection lines as a preview, per the request).
- Lines leading from the beaten stage to its available stages are highlighted; other lines are muted.

### 5.3 Input
- Keyboard/gamepad: up/down moves the cursor between available cards in the current column, `confirm` starts the
  stage. Locked cards are skipped by the cursor.
- Mouse: clicking an available card selects it, a second click (or `confirm`) starts it.
- `back` returns to the hub **after a confirmation prompt** ("Abandon this run?"), only on the first select
  screen; later screens cannot go back.
- The cursor starts on the first available card.

### 5.4 Transitions
- Door -> select screen: fade out/in through `SceneFader` (v0.4 section 6.5).
- Select -> stage: fade out/in, then the arena starts with the chosen `StageData`.
- Stage win -> select screen: fade out/in (no "return to hub" prompt in the end-of-stage screen; just a short
  "Stage cleared" banner before the fade).

## 6. Run flow changes

- The arena ends in one of three ways: **win** (clears the stage's win condition, same as today), **death**, or
  **abandon** (pause menu).
- Win in column 1 or 2: `GameSession.complete_stage()` records the stage, then loads the select screen.
- Win in column 3: shows the victory screen with **Return to Hub** (Restart is removed because a restart would
  skip the path; the door starts a new run instead).
- Death: shows the death screen with **Return to Hub** only. (v0.4 offered Restart; removed in v0.5 for the same reason.)
- Player state between stages: HP and other run state **reset** at the start of each stage in v0.5. (An easy
  default; carrying state over is an open question, section 10.)

## 7. GameSession

New state (in-memory only):
- `path`: the generated graph (columns, stages, edges).
- `path_seed`: the seed used.
- `current_column`: 0, 1 or 2.
- `beaten`: the stage taken in each column so far.
- `current_stage`: the `StageData` of the stage being played.
- `gold`: int, the player's currency. Unlike the path it is **not** reset when a run ends, so it will be there for the
  future trade system in the hub. It lives only while the game is open (nothing is saved to disk).

New or changed methods:
- `start_run(character)`: now generates a new path and loads the select screen instead of loading `main.tscn`.
- `available_stages()`: stages in `current_column` reachable from the last beaten stage.
- `select_stage(stage)`: sets `current_stage`, loads the arena.
- `complete_stage()`: records the win and advances the column, or ends the run on the last one.
- `fail_run()` / `abandon_run()`: discard the path and go to the hub.
- `restart_run()` from v0.4 is removed.
- `main.tscn` must still run on its own from the editor: if no `current_stage` is set, it uses a default
  `StageData` (all multipliers 1.0), so the existing editor workflow and tests keep working.

## 8. Sounds
- Reuse existing UI sounds for cursor move and confirm.
- New short sound for "stage cleared". If no asset exists yet, use a placeholder and note it in the build log.

## 9. Build order

1. `StageData` resource and applying population, difficulty and experience in the arena.
1b. Gold: coin drop on mob death, pickup, `GameSession.gold`, HUD number.
2. Path generator (pure logic, no UI) with tests for all the edge rules in 3.2 and seed reproducibility.
3. `GameSession` path state and methods.
4. Select screen with static data, then hooked to the generator.
5. Wire the hub door to the select screen; wire win/death/abandon flows (section 6).
6. Victory and death screens updated (Restart removed).
7. Polish: lines, card states, transitions, sounds.

## 10. Open questions / assumptions to revisit

- **Stage 3 connections:** your example only described stage 1 -> A and stage 2 -> A/B. Assumed stage 3 connects
  to B only; the generator rules in 3.2 produce this kind of structure but do not fix it.
- **Player state between stages:** HP resets each stage (assumed). Carrying HP or items over would make the
  path choice matter more and may be wanted next.
- **Gold persistence:** assumed gold carries across runs (and death) for the later trade system. Say if it should reset per run.
- **Currency scaling:** the stage `currency` multiplies the 25% base (25% x 1.25 = 31.25%) rather than adding points. Say if you want it additive.
- **Difficulty:** interpreted as damage mobs deal to the player. Mob health is untouched.
- **Gold value:** every coin is worth 1; no coin tiers.
- **Final stage as a boss:** the final stage is currently just difficulty 3 with the normal win condition.
- **Revisit and rewards:** no way to revisit a column, and no rewards for stage choice yet.
- **Edge rule 4** may feel too restrictive once there are more columns; revisit then.

## 11. Definition of Done for v0.5

- Walking into the hub door opens the select screen and shows all 6 stages (3 + 2 + 1) with connection lines.
- Only stages reachable from the last beaten stage are selectable; others are visibly locked.
- Beating a stage returns to the select screen with the next column active and the beaten stage marked.
- Beating the final stage shows victory and returns to the hub; the next door entry gives a **new** path.
- Dying anywhere returns to the hub and discards the path.
- Each stage shows name, thumbnail and its four modifiers (population, difficulty, experience, currency) on its card, and the arena actually applies them.
- The generator tests for the rules in 3.2 pass over at least 1000 seeds.
- `main.tscn` still launches directly from the editor.
