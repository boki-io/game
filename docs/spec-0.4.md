# Spec v0.4: The Hub (in-game character selection)

Builds on `spec-0.1.md`, `spec-0.2.md` and `spec-0.3.md` (all built). Replaces the Main Menu and Character Select
screens with a walkable **hub**, in the style of the pre-run area in Halls of Torment: the characters stand on
pedestals, you look at each one's description and stats, pick one, walk around as them, practice on training
dummies, and walk through a door in the north wall to begin a run. Placeholder art and generated sounds remain
acceptable.

Revision 2: updated after an independent review of revision 1 against the code. Section 14 lists what changed.

Revision 3: the hub looks like a cave (section 15), added after the M26 review. Revision 4: the run's arena looks the
same and gets freestanding rock walls of varied length (section 15.1). Build order and Definition of Done
are updated to match.

## 1. Scope

**In v0.4:**
- The game boots straight into the hub. The Main Menu and Character Select scenes are removed.
- **Browse mode:** a camera moves between character pedestals; an info panel shows the focused character.
- **Walk mode:** after choosing, you control that character in the hub, with abilities, infinite mana and
  indestructible training dummies.
- A door in the north wall starts a run; a run ends back in the hub.
- Pause menu and end screen changes (section 8), and a regression test folder (section 11).

**Out of v0.4:** saving the last character between launches, locked or unlockable characters, settings
menus, a multi-room hub, shops or upgrades in the hub, real art, new characters or enemies, multiplayer.

**The question this version answers:** does choosing a character by walking through a world feel better than a
menu, and is the hub a good place to try a kit before a run?

## 2. Flow

```
Boot --> HUB (browse mode) --confirm--> HUB (walk mode, as the chosen character)
              ^                              |  interact at the pedestals: back to browse mode
              |                              |  walk into the door (north wall)
              |                              v
              +--- Return to Hub ---- RUN (main.tscn) ---- Restart (same character) --> RUN
```

- The hub scene is the project's main scene.
- **Browse mode:** no Player exists. You are a camera and a cursor.
- **Walk mode:** a normal Player exists, built from the chosen `CharacterData`, in "hub mode" (section 5).
- A run uses `main.tscn` with the small changes listed in section 7.
- Ending a run (death or win) offers **Restart** (a new run, same character) or **Return to Hub**. Returning puts
  you in the hub in **walk mode as the character you just played**, standing just south of the door.
- The last character is remembered only while the game is open (`GameSession.last_character`); nothing is saved.
- Every scene change fades out and in through `SceneFader` (section 6.5), including the first boot.

## 3. The hub room

A single room (placeholder art; all sizes are tunable constants).

- **Size:** 960 x 560 px interior (a multiple of the 16px ground tile). The room is built with the existing
  `Arena` node script so it gets walls, the checkerboard ground and the border for free; `Arena` gains an exported
  `size` (default 1600 x 896 as today) and the hub scene sets 960 x 560.
- **Walls:** solid colliders on the World layer on all four sides (like the arena). The door is **not** a gap in
  the collision: it is a doorway drawn in the north wall with a trigger area just inside it (section 6.1).
- **Pedestals:** one per character, in a row along y = 380, centered on x = 480, spaced 140px apart
  (with two characters: x = 410 and x = 550). The row is built from `CharacterRegistry`, so a third character
  needs no layout change.
- **Door:** the doorway is at x = 480 on the north wall (48px wide), drawn as a dark archway that lights up when a
  character has been chosen.
- **Training area:** north-west of the room: three dummies at (150, 140), (150, 200) and (210, 170).
- **Decor:** a sign near the pedestals reads the game's title; nothing else is required.
- **Pedestals do not block movement** (decoration, Y-sorted with everything else).
- **World size ownership:** `Arena.SIZE` (a constant) becomes a static `Arena.world_size`. The `Arena` node assigns
  it in `_enter_tree()` (which runs before any `_ready()` in the scene), always, from its `size` export, so a run
  after the hub (or the reverse) never reads a stale value. All users read `Arena.world_size`: `arena.gd`,
  `ground.gd`, `camera_follow.gd`, `enemy.gd` (clamp), `player_projectile.gd`, `meteor_behavior.gd`,
  `spawn_director.gd` and `main.gd` (twice). `Arena` must be the first child of its scene root so that `Ground` and
  `Camera` (siblings after it) read the value after it is set.

## 4. Browse mode

- On launch the first character in the registry is focused; nothing is chosen yet.
- **The camera** moves smoothly (0.25s) to the focused pedestal. It is offset so the focused character appears
  left of center and the info panel has room on the right (section 10 describes the `CameraFollow` change).
- **Input actions** (added to `InputSetup`; keyboard actions are registered like the existing ones and gamepad
  buttons are added as joypad events on the same actions):
  - `hub_left` / `hub_right`: A / D, Left / Right arrows, D-pad left / right (a stick flick counts once per push).
  - `hub_confirm`: Enter, F, gamepad South.
  - `interact` (walk mode): F, gamepad South.
  - `hub_info` (walk mode): I, gamepad Back or Select.
  - `pause`: Esc, Start (existing).
  - Gamepad Q/E/R buttons (X, Y, right trigger) and the sticks keep their current meanings; South, Back and the
    D-pad are free.
- **Mouse:** each pedestal has a clickable area (`input_pickable`); clicking focuses it. The panel has a **Choose**
  button. The panel and hint bar are `Control`s that only catch the mouse over their own rectangles, so pedestal
  clicks elsewhere still work. The Choose button has `focus_mode` none, so Enter/South (which are also `ui_accept`)
  are handled once, by the hub, not twice.
- **Single handling of confirm:** the hub controller handles `hub_confirm` and `interact` as input events (not by
  polling `is_action_just_pressed`) and marks them handled. After any mode change it ignores `hub_confirm` and
  `interact` for 0.2s, so one F press cannot choose a character and immediately interact.
- Every pedestal shows its character standing idle (the Knight plays its idle animation; other characters show
  their placeholder body with a gentle one-pixel bob), a name label, and a spotlight ring that brightens on the
  focused one. Display figures have the debug aim marker turned off (`show_aim = false`).
- The door is shown dark and closed (nothing can use it).
- **Hint bar** at the bottom: "< > Browse   Enter Choose   Esc Menu" (gamepad icons are text for now).
- A focus change plays a soft tick; a confirm plays a chime (section 9).
- Because no Player exists in browse mode, `Enemy._physics_process` returns early for the dummies (it needs a
  target). That is fine: nothing can damage them in browse mode.

### 4.1 Info panel

A dark panel on the right, 270px wide and up to 330px tall, for the focused character:
- **Name** (large) and **description** (up to 2 lines), from `CharacterData`.
- **Stats row:** HP, move speed, max mana and mana regen per second, from `CharacterData`.
- **Trait:** name and a one-line description. `CharacterData` gains `trait_name` and `trait_description` (data
  strings; the Knight has none and shows "Trait: none"). The text is data, so a number in it (for example Arcane
  Focus's +25%) is typed in the data file; a test (section 11) checks it matches the trait script's constant.
- **Abilities:** four rows (Auto, Q, E, R). Each row is an icon (if set), then a name line, a stats line
  (cooldown, mana, damage) and a one-line description, all read from `AbilityData`. At the 8px font a row is about
  28px tall, so the whole panel (name 14, description 20, stats 10, trait 20, 4 rows 112, button 22, gaps) fits in
  about 220px of the 360px height.
- A **Choose** button.
- Ability and stat numbers are never typed into the UI code.

## 5. Walk mode

Confirming a character in browse mode:
1. Plays the chime and a short effect on the pedestal.
2. Spawns a normal `Player` built from that `CharacterData`, with `hub_mode = true`, standing 30px south of the
   pedestal. The pedestal's display figure is hidden while you are that character.
3. The camera blends (0.3s) from the browse position to following the Player. The info panel closes. The door
   lights up and `door_open` plays.

**Rules in the hub (`Player.hub_mode`):**
- **No damage.** The hub has nothing that hurts the Player, so no invulnerability is set (this also avoids Phase
  Shift, whose `end_phase` clears `hurtbox.invulnerable`).
- **Infinite mana, normal cooldowns.** `Mana` gets an `infinite` flag. The Player sets it after
  `Mana.configure` when it applies the character in hub mode. While set, `spend` does not reduce mana (it still
  emits `changed` and the blue cost number still appears), so `can_afford` is true and the bar stays full.
- **Abilities work.** Auto-attacks fire at the dummies (within each ability's `target_range`), and Q/E/R behave
  exactly as in a run. The hub scene therefore has the same helper nodes as a run: `Effects`, `DamageZones`,
  `PlayerProjectiles`, and a camera in group `camera`.
- **No progression.** No XP, gems, level-ups, upgrades, timer or kills. The Player's XP component stays idle and
  the hub has no `LevelUpMenu`.
- **Hud in the hub:** shows only the mana bar and the ability icons (cooldown sweeps work). `Hud.bind` takes an
  optional `RunManager`; with none, the HP bar, XP bar, timer and kill count are not drawn. `Hud` must also clear
  its player reference when the Player is freed and test `is_instance_valid(player)` before drawing.
- **Debug overlay (F3):** with no `RunManager` and no `SpawnDirector` it shows only the mana, cooldowns and fps.
- **Info on demand:** pressing `hub_info` toggles the info panel for the current character.

### 5.1 Changing character

- Whenever the Player is within **60px** of any pedestal (less than half the 140px spacing, so at most one
  qualifies), a prompt shows: "F: Change character".
- Pressing `interact` returns to browse mode with **the character you are playing** focused (regardless of which
  pedestal you stood beside). It: removes the Player immediately (unregistering it from `PlayerRegistry` and freeing
  it, not `queue_free`, so a same-frame spawn can never leave two players), re-shows that character's pedestal
  figure, and clears pending effects with new `clear()` methods on `Effects`, `DamageZones` and `PlayerProjectiles`
  (so a queued meteor, a damage field or a bolt in flight cannot land after the change). The orb belt is a child of
  the Player and goes with it.
- You can then choose another character or the same one again.

### 5.2 Training dummies

- Three dummies, indestructible: they never die and never move.
- They show damage numbers as normal and a small readout above each: "Last 22  Total 340  DPS 45".
  - The readout listens to the dummy's `Health.damaged` signal. *Last* is the most recent hit's damage.
  - A **burst** is a run of hits where each is within 3.0s of the previous. *Total* is the damage in the current
    burst; *DPS* is Total divided by the time from the burst's first hit to its last (at least 1.0s).
  - The readout keeps its numbers for 3.0s after the last hit, then clears.
  - Damage is counted per hit, independent of the merged damage numbers on screen.
- Implementation: dummies are `Enemy` instances so the enemy grid and every ability see them, built from
  `enemy.tscn` with a new `EnemyData` (`training_dummy.tres`: very high HP, speed 0, no contact damage,
  `immovable = true`) and a `DummyBrain` whose `can_contact()` returns false (so it never calls `receive_hit`).
  The hub controller must set `data` **before** adding the node and then call `activate(pos, 1.0)` (an inactive
  enemy ignores damage).
- `Enemy.apply_knockback` and `Enemy.stun` return immediately when `data.immovable`, so slams, meteors and
  Static Shock neither move nor tint the dummies. (`EnemyData` gains `immovable`; this is an `enemy.gd` change too.)
- The HP top-up: the dummy's `Health.damaged` handler restores HP to max when it falls below half, so the `died`
  signal can never fire. (`Enemy._on_died` does not deactivate the enemy, so a dead dummy would otherwise keep
  absorbing nothing.)
- Dummies are never released to a pool, never drop gems, and there is no `RunManager` to count kills.
- They do not attack, so there are no enemy projectiles in the hub.

## 6. Entering and leaving a run

### 6.1 The door
- A trigger `Area2D` just inside the north wall at the doorway (48 x 20px), on the Player's collision layer mask,
  detects the Player **body** with `body_entered` (the Player's body and its hurtbox are both on layer 2, so
  area signals would fire as well). It is enabled only in walk mode, and for 1.0s after the scene loads it ignores
  the Player (so a return from a run cannot re-trigger it).

### 6.2 Starting the run
- When the Player enters the trigger: `door_enter` plays, input is blocked (6.5) and the screen fades to black over
  0.3s. `GameSession.start_run(character)` sets `character` and `last_character` and loads `main.tscn`. The run
  fades in over 0.3s.

### 6.3 Returning
- **Return to Hub** (end screen or run pause menu) fades out, loads the hub, and fades in with the Player already in
  walk mode as `last_character`, standing 40px south of the door trigger.

### 6.4 GameSession
- `GameSession` loses `MAIN_MENU` and `CHARACTER_SELECT`; it gains `HUB` and `RUN` paths and the methods
  `start_run(character)`, `restart_run()` and `go_to_hub()`.
- `character` keeps its default (the first registered character) so that `main.tscn` still runs on its own from
  the editor. `last_character` is **null at boot** and is set when a run starts. The hub reads `last_character`:
  null means browse mode, set means walk mode.

### 6.5 SceneFader
- A new autoload with a full-screen black overlay on a high CanvasLayer, `PROCESS_MODE_ALWAYS`.
  `fade_to_scene(path)` blocks input, fades out (0.3s), sets `get_tree().paused = false` **at the moment of the
  scene change** (not before the fade), changes the scene, then fades in (0.3s) when the new scene is ready
  (`SceneTree.scene_changed`). The first boot fades in from black.
- **Blocking input:** `SceneFader.busy` is true from the start of the fade-out until the fade-in ends. While busy,
  `PlayerInput` returns no movement or ability input, and the hub controller, pause menu and end screen ignore
  input.
- The fade-out starts only from a deliberate action (the door, Restart, Return to Hub); a death during a run still
  waits its 1.2s end-screen delay first, and the end screen is the only thing that starts a fade after a run.

## 7. Removed and changed

- **Removed:** `scenes/main_menu.tscn`, `scenes/character_select.tscn`, `scripts/ui/main_menu.gd`,
  `scripts/ui/character_select.gd`. The project's main scene becomes `scenes/hub.tscn`. Their useful pieces (the
  ability row layout, the placeholder preview) move into the new info panel.
- **Changed (all need edits):**
  - `GameSession` (6.4), new `SceneFader`.
  - `main.tscn` and `main.gd`: read `Arena.world_size`, the pause menu gets its run mode, the end screen is wired to
    the new buttons, the `Arena` node sets its size export (default).
  - `PauseMenu` (modes, and a null-safe check of `end_screen`, which is absent in the hub) and `EndScreen`
    (Restart and Return to Hub).
  - `Hud` (optional run info, player validity), `DebugOverlay` (null-safe), `Mana` (`infinite`), `Player`
    (`hub_mode`), `PlayerInput` (blocked while the fader is busy), `Enemy` and `EnemyData` (`immovable`),
    `CharacterData` (trait text), `InputSetup` (new actions), `Effects`, `DamageZones`, `PlayerProjectiles`
    (`clear()`), `Audio` (new sound names), `CameraFollow` (browse mode), `Arena`, `ground.gd`, `enemy.gd`,
    `player_projectile.gd`, `meteor_behavior.gd`, `spawn_director.gd` (world size).
- The README's "Run it" and "Characters" text is updated.
- Note: a local, uncommitted edit to `main_menu.tscn` would be deleted along with the scene.

## 8. Menus

- **Hub pause menu (Esc / Start):** Continue, Exit.
- **Run pause menu:** Continue, **Return to Hub**, Exit.
- **End screen:** time, level and kills as today, then **Restart** (new run, same character) and
  **Return to Hub**.
- Return to Hub from the run pause menu abandons the run without confirmation (as "Main Menu" did).
- Pausing is ignored while `SceneFader.busy`.

## 9. Sounds

New generated sounds (`tools/gen_sfx.py`): `hub_focus` (soft tick), `hub_choose` (chime), `door_open`, `door_enter`.
Reuses `menu_click` for the buttons. They must be generated and imported (the `Audio` autoload skips a missing
file silently), and are added to its list.

## 10. Technical notes

- **Hub scene** (`scenes/hub.tscn`, script `hub.gd`): `Arena` first (size 960x560, ground, walls, door trigger),
  `World/Pedestals`, `World/Dummies`, `World/Players` (Y-sorted), `World/Effects`, `World/Zones`,
  `World/PlayerProjectiles`, a `Camera`, and a `UI` CanvasLayer (Hud, info panel, hint bar, pause menu). A
  `HubController` owns the two modes as a small state machine (`BROWSE`, `WALK`).
- **CameraFollow browse mode:** the camera currently sets `offset = Vector2.ZERO` every frame (it only uses `offset`
  for shake) and snaps `global_position` to the nearest player. It gains a `browse_target` (a world position) and a
  separate `base_offset`. With no Player it moves toward `browse_target` over 0.25s (a tween on its own
  `global_position`); `offset` is `base_offset + shake`. When a Player spawns it blends from the current position
  to following over 0.3s. Limits still come from `Arena.world_size`.
- **Info panel:** built in code like the other menus (`UiKit`), in `scripts/ui/hub_info_panel.gd`.
- **Pedestals:** `HubPedestal` nodes (a drawn platform, a display figure, a label, a click area).
- **Display figures** reuse the Knight's `sprite_frames` when present (the Player shares the same resource;
  setting animation loops is idempotent), else the placeholder sprite script.
- **Stale state across scenes:** `PlayerRegistry` unregisters on tree exit; `EnemyGrid` is rebuilt each physics
  frame, and also gets a `clear()` that each scene's controller calls at startup; `Effects`, `DamageZones` and
  `PlayerProjectiles` live in the scene and are freed with it; `Audio` and `SceneFader` persist by design.
- Training dummies must be excluded from anything that counts or spawns: no gems, no kills, not pooled.

## 11. Build order

1. **M23 Foundations:** `Arena.world_size` and the `size` export, `SceneFader`, `GameSession` flow, the
   `InputSetup` actions, `PauseMenu`/`EndScreen`/`Hud`/`DebugOverlay`/`CameraFollow` changes, an empty hub scene
   (room, walls, door trigger, camera) as the main scene, the two old screens removed. Create the **`tests/`**
   folder with a README and port the useful regression scripts (Double Dash chain, post-dash immunity, Dasher
   lane, Wizard abilities, Phase Shift and belt, Chain Lightning, crowd performance), each runnable with
   `godot --headless --path . --script tests/<name>.gd` (or `--path . --script` where rendering is needed) and
   printing PASS or FAIL. *The game boots into an empty hub; a run can be started with a temporary key and
   returned from.*
2. **M24 Pedestals and browse mode:** pedestals and display figures, the browse camera and input, the info panel,
   trait text in `CharacterData`, focus and confirm sounds. *Review stop: does choosing a character feel good?*
3. **M25 Walk mode:** spawning as the chosen character, hub HUD, infinite mana, the interact prompt and returning to
   browse mode with `clear()` methods, the door trigger and fade, return-to-hub state.
4. **M26 Training dummies:** `immovable`, the dummy data and brain, the readout, the top-up. *Review stop (the
   full hub).*
5. **M27 Cave look:** section 15: dirt ground, rock walls, torches and decor, the vignette, a test for the new
   walls. *Review stop (does the hub read as a cave, and is everything still readable?).*
6. **M28 Polish and check:** sounds, door visuals, run all `tests/`, performance check, docs and README.
   *Final review.*

## 12. Definition of Done for v0.4

- The game launches into the hub; there is no Main Menu or Character Select scene in the project.
- In browse mode Left/Right and clicking move the camera between pedestals; the panel shows the right data for
  each character (a test compares the displayed numbers with the data files); Enter or the Choose button
  confirms exactly once.
- After choosing, exactly one Player of that character exists in the hub; abilities work; mana never decreases;
  cooldowns work; the door is lit; the HP, XP, timer and kill count are not drawn.
- Interact near the pedestals returns to browse mode with the Player's character focused; pending meteors, fields
  and bolts are gone; choosing another character works and leaves only one Player in the world; the same key press
  cannot choose and immediately interact.
- The three dummies take damage from every ability of both characters (including a meteor, Chain Lightning and Phase
  Shift's orbs), show numbers and the readout, and never die, move, tint or stun.
- Walking into the door fades out and starts a run as that character; the run is otherwise unchanged.
- A run's end screen offers Restart and Return to Hub; Return to Hub lands in walk mode as the same character near
  the door and does not re-enter the run; the Arena size is correct in both scenes in either order.
- The hub pause menu has Continue and Exit and does not crash on first Esc; the run pause menu has Return to Hub.
- Pausing or pressing keys during a fade does nothing harmful, and the game is unpaused in the new scene.
- All scripts in `tests/` print PASS, so both characters still play as before in a run.
- At least 60 FPS in the hub with both characters' abilities in use (measured with F3), and no regression in the
  run's performance numbers from the v0.3 status section.
- Keyboard-and-mouse is exercised in tests and play; gamepad is listed as untested unless a controller is available.

- The hub looks like a cave (section 15): dirt floor, rock walls you cannot walk into, torch light and a darkened
  edge, and the characters, dummies, readouts and HUD are still easy to read. The run's arena is unchanged.

## 13. Assumptions to Revisit Later

- The room size, pedestal spacing and the 60px interact radius are guesses.
- The Choose, interact and info keys (F/I/Enter) and using A/D for browsing may collide with muscle memory; browse
  mode has no movement, so this should be harmless.
- Infinite mana in the hub hides the real mana economy of a kit; that is deliberate, for practice.
- Indestructible dummies cannot show how fast a character clears enemies.
- "No character chosen" until the first choice means the door is unusable at boot; there is no quick-start.
- With few characters a row of pedestals fits one screen; with many, browsing scrolls the camera.
- No saved last character means every launch starts in browse mode.
- The info panel is dense at the 8px font; if it feels cramped, split it into tabs (Stats / Abilities).
- Auto-attacks fire constantly at nearby dummies, so a character standing by them casts continuously.

## 15. Cave look for the hub (revision 3)

Goal: the hub reads as a torch-lit cave or dirt chamber instead of a green checkerboard. Placeholder art drawn in
code, like everything else so far: no new image files are needed. The gameplay layout in section 3 does not
change.

- **Ground:** `Ground` gets a `look` (`GRASS`, the default, keeps today's checkerboard for the run; `DIRT` is new).
  `DIRT` builds the tile set at runtime from a handful of brown tile variants (light, dark, pebbled, cracked, with
  seeded speckles), placed with a seeded random pattern so the floor looks irregular but is identical every launch.
  A few darker patches and lighter paths (door to pedestals) are painted on top. The tile size stays 16px.
- **Rock walls:** a visible band of rock, one tile (16px) thick, along all four sides, with a ragged inner edge and
  darker rock behind it. The wall colliders move to the inner edge of the band so the band is solid and you can
  never walk into it. `Arena` gets an exported `wall_band` (0 by default, so the run is unchanged; the hub sets 16).
  `Arena.world_size` and the camera limits still describe the full room, so the numbers in section 3 hold; the
  walkable interior is simply 16px smaller on each side.
- **Door:** the doorway is carved into the north rock band (still 48px wide at x = 480). Its trigger and spawn
  points (6.1, 6.3) move down by the band thickness so they stay just inside the walkable floor.
- **Light:** torches on the walls (one each side of the door, one near each end of the south wall) and one
  by the training area, drawn as small flames with a soft warm glow (additive circles, with a slow flicker). A dark
  vignette toward the room's corners and edges, drawn as a screen overlay below the UI. No `Light2D` nodes, so
  sprites keep their normal colors and the cost is a handful of draws.
- **Decor** (non-blocking, Y-sorted with everything else, placed from a seeded random layout): stalagmites and rocks
  along the walls, small pebbles, bones, a few glowing mushrooms. Decor never lands on the pedestal row, the
  training area, the door lane or within 24px of any of them. Up to 60 decor items.
- **Sign:** the title sign keeps its section 3 position and becomes a wooden post sign.
- **Readability:** the floor stays mid-dark and low-contrast so characters, the tan dummies (they get a dark outline),
  damage numbers, the readout text and the HUD stand out. If the tan dummies blend into the dirt, the dummy color
  changes, not the floor.
- **Scope (revision 4):** the run's arena gets the same cave look: dirt floor, the rock band, 12 torches along the
  outer walls, the vignette and 110 decor items kept off the start. Section 15.1 adds freestanding rock walls.
- **Not in this version:** real tilesets or sprites, animated water or fog, dynamic shadows, sound ambience (a
  looping cave drip is a possible later addition).
- **Tests:** the existing `tests/` must still pass; a new test checks that the hub's walls block movement at the
  band's inner edge (the Player cannot enter the band, the door still triggers), that decor stays out of the
  reserved areas, and that the ground layout is the same on every load. Looks are checked by screenshot and play.
- **Cost:** about 2,100 ground cells (same as now), up to 60 decor nodes and 5 torches: static, so no measurable
  cost. The performance check in section 12 still applies.

### 15.1 Freestanding rock walls in the run (revision 4)

- 14 solid rock walls inside the run's arena, 16px thick and horizontal or vertical, with lengths picked from 48, 64,
  96, 128, 160, 208, 256 and 320px, so the arena has both short stubs and long barriers.
- Placed from a fixed seed (the same layout every run), at least 56px from the rock band and from each other (so
  there is always a passage), and never within 110px of the Player's start.
- Drawn as a flat rock slab with a darker south face, Y-sorted with the characters; the existing rock pillars
  (props) skip the walls and take the same cave colors.
- **Solid for the Player only**, like the pillars: enemies and projectiles pass through, so a wall is a hindrance for
  the Player and never a safe spot. (Making enemies path around walls is a bigger change and not in this version.)
- `Arena.wall_margin` (the rock band's thickness) keeps enemy positions, meteors and the spawn ring off the rock.
- Test: `tests/arena_cave.gd` (varied lengths, clear of the start and of each other, seeded, solid, enemies kept inside).

## 14. Changes from revision 1 (after review)

Fixed from the review: the world size is owned by the `Arena` node and set in `_enter_tree` (it was set too late to be
read by `Ground` and `Camera`, and went stale across scenes); `main.tscn` and `main.gd` are listed as changed; the
pause menu, HUD and debug overlay are made safe without a run; the camera gets a browse mode that no longer
zeroes its offset or snaps; Phase Shift's effect on hub invulnerability is removed by not using invulnerability
there; dummy requirements (set data first, activate, immovable, can_contact false, HP top-up, readout source);
input actions, single handling of confirm and the Choose button's focus; interact radius and focus target
(decided by the product owner: the character you are playing); `clear()` methods for pending effects and immediate
Player removal; `GameSession.last_character` null at boot; fade and pause handling and input blocking; the door
uses `body_entered` with solid walls; the dummy readout is defined; and the regression `tests/` folder is added
(decided by the product owner).

## 16. Changes from revision 2

Added the cave look (section 15), the M27 Cave look milestone (polish becomes M28) and its Definition of Done item.

Revision 4 (after the M27 review): the cave look and freestanding rock walls also apply to the run's arena (15, 15.1).
