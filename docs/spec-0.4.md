# Spec v0.4: The Hub (in-game character selection)

Builds on `spec-0.1.md`, `spec-0.2.md` and `spec-0.3.md` (all built). Replaces the Main Menu and Character Select
screens with a walkable **hub**, in the style of the pre-run area in Halls of Torment: the characters stand on
pedestals, you look at each one's description and stats, pick one, walk around as them, practice on training
dummies, and walk through a door in the north wall to begin a run. Placeholder art and generated sounds remain
acceptable.

## 1. Scope

**In v0.4:**
- The game boots straight into the hub. The Main Menu and Character Select scenes are removed.
- **Browse mode:** a camera moves between character pedestals; an info panel shows the focused character.
- **Walk mode:** after choosing, you control that character in the hub, with abilities, infinite mana and
  indestructible training dummies.
- A door in the north wall starts a run; a run ends back in the hub.
- Pause menu and end screen changes (section 8).

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
- **Browse mode:** no player body exists. You are a camera and a cursor.
- **Walk mode:** a normal Player exists, built from the chosen `CharacterData`.
- A run uses the existing `main.tscn` unchanged, with the chosen character (as today).
- Ending a run (death or win) offers **Restart** (a new run, same character) or **Return to Hub**. Returning puts
  you in the hub in **walk mode as the character you just played**, standing just south of the door.
- The last character is remembered only while the game is open (`GameSession`); nothing is saved to disk.

## 3. The hub room

A single room (placeholder art; all sizes are tunable constants).

- **Size:** 960 x 560 px interior (1.5 screens wide, 1.55 screens tall at the 640x360 base resolution), ground
  drawn with the same checkerboard `TileMapLayer` approach as the arena (tile 16px, so the size is a multiple of 16).
- **Walls:** invisible colliders on the World layer around the room (like the arena) plus a visible stone border.
- **Pedestals:** one per character, in a row along y = 380, centered on x = 480, spaced 140px apart
  (with two characters: x = 410 and x = 550). The row is built from `CharacterRegistry`, so a third character
  needs no layout change.
- **Door:** a gap in the north wall at x = 480, y = 16, 48px wide. Drawn as a dark archway. A trigger area just
  inside it starts the run (section 6.4).
- **Training area:** north-west of the room: three dummies at (150, 140), (150, 200) and (210, 170).
- **Decor:** a sign near the pedestals reads the game's title; nothing else is required.
- **Pedestals do not block movement** (they are decoration, Y-sorted with everything else).
- **Camera:** limited to the room. In walk mode it follows the player like the run camera; the room is larger
  than the screen, so it scrolls.
- **World size:** the current `Arena.SIZE` constant is used by 8 scripts (arena, ground, camera, enemy clamp,
  player projectile, meteor clamp, spawn director, main). It becomes a static `Arena.world_size` that each scene
  sets on load (hub 960x560, run 1600x896), so projectiles, the camera and the ground adapt to the current room.

## 4. Browse mode

- On launch the first character in the registry is focused; nothing is chosen yet.
- **The camera** moves smoothly (0.25s) to the focused pedestal. It is offset so the focused character appears
  left of center and the info panel has room on the right.
- **Controls:**
  - Left / Right: A / D, arrow keys, the D-pad, or the left stick (with a short repeat delay).
  - Confirm: Enter, F, or the gamepad's South button, or the panel's **Choose** button.
  - Mouse: clicking a pedestal focuses it; the panel has a **Choose** button.
  - Pause: Esc / Start (Continue and Exit).
- Every pedestal shows its character standing idle (the Knight plays its idle animation; other characters show
  their placeholder body with a gentle one-pixel bob), a name label, and a spotlight ring that brightens on the
  focused one.
- The door is shown dark and closed (nothing can use it).
- **Hint bar** at the bottom: "< > Browse   Enter Choose   Esc Menu" (gamepad icons are text for now).
- A focus change plays a soft tick; a confirm plays a chime (section 9).

### 4.1 Info panel

A dark panel on the right (about 270px wide) with, for the focused character:
- Name and description (`CharacterData`).
- **Stats:** HP, move speed, max mana and mana regen per second (all from `CharacterData`).
- **Trait:** the trait's name and a one-line description. Knight: "None". Wizard: "Arcane Focus: +25% damage
  after standing still for 1s". (`CharacterData` gains `trait_name` and `trait_description`; the text is data.)
- **Abilities:** four rows (Auto, Q, E, R), each with the ability icon (if set), name, cooldown, mana, damage and
  one-line description, all read from `AbilityData` (the same content the old Character Select screen showed).
- A **Choose** button.
- Numbers are never typed into the UI.

## 5. Walk mode

Confirming a character in browse mode:
1. Plays the chime and a short effect on the pedestal.
2. Spawns a normal `Player` built from that `CharacterData`, standing just south of the pedestal. The pedestal's
   display figure is hidden while you are that character (you are standing in for it).
3. The camera becomes a normal follow camera. The info panel closes. The door opens (its archway lights up).

**Rules in the hub:**
- **No damage.** There are no enemies that hurt you. The Player is invulnerable (including to Phase Shift's own
  immunity logic: nothing breaks if it is already invulnerable).
- **Infinite mana, normal cooldowns.** `Mana` gets an `infinite` flag: spending never reduces it, so
  `can_afford` is always true. The blue cost numbers still appear so the player can see what each cast would cost.
- **Abilities work.** Auto-attacks fire at the dummies; Q/E/R behave exactly as in a run. The hub scene
  therefore needs the same helper nodes as a run (`Effects`, `DamageZones`, `PlayerProjectiles`, a camera in group
  `camera`).
- **No progression.** No XP, gems, level-ups, upgrades, timer or kills. The Player's XP component stays idle.
- **HUD in the hub:** only the mana bar and the ability icons (cooldown sweeps work). The HP bar, XP bar, timer and
  kill count are hidden. `Hud` must work without a `RunManager`.
- **F3 debug overlay** still works (it shows the ability cooldowns and fps; the enemy fields are hidden).
- **Info on demand:** pressing I (or Select on a gamepad) toggles the info panel for the current character.

### 5.1 Changing character

- Near the pedestal row (within 80px of any pedestal) a prompt appears: "F: Change character".
- Pressing interact (F, or South on a gamepad) despawns the Player, shows that character's pedestal figure again,
  and returns to browse mode with that character focused. Any pending effects (projectiles in flight, damage
  fields) are cleared.
- You can then choose another character or the same one again.

### 5.2 Training dummies

- Three dummies, indestructible: they never die and never move (no knockback, no stun).
- They show damage numbers as normal and a small readout above each: "Last 22  Total 340  DPS 45".
  - *Last:* the most recent hit's damage.
  - *Total:* damage since the total was last reset.
  - *DPS:* total divided by the time from the first hit of the current burst to the last hit.
  - The total and DPS reset after 3.0s without a hit.
- Implemented as `Enemy` instances (so they register with the enemy grid and every ability works on them) using a
  new `EnemyData` (`training_dummy.tres`: very high HP, speed 0, no contact damage, `immovable = true`) and a
  `DummyBrain` that does nothing. They are never released to a pool and never count as kills.
- Their HP is topped up when it falls below half so it can never reach zero.
- They do not attack, so there are no enemy projectiles in the hub.

## 6. Entering a run

### 6.1 The door
- The door is in the north wall. It is open (lit) only in walk mode.
- A trigger area just inside the doorway (48 x 20px) detects the Player.

### 6.2 Starting the run
- When the Player enters the trigger: input is disabled, the screen fades to black over 0.3s (a new `SceneFader`
  autoload with a full-screen overlay), `GameSession` records the character, and `main.tscn` loads.
- The run scene fades in over 0.3s on load.

### 6.3 Returning
- **Return to Hub** (end screen or pause menu) fades out, loads the hub, and fades in with the player already in
  walk mode as the last character, standing 40px south of the door trigger (so they are not immediately
  re-triggered; the trigger ignores the player for 1.0s after load).

### 6.4 GameSession
- `GameSession` loses `MAIN_MENU` and `CHARACTER_SELECT`. It gains `HUB` and `RUN` scene paths and these methods:
  `start_run(character)`, `restart_run()`, `go_to_hub()`. `last_character` is set when a run starts.
- On boot the hub checks `GameSession.last_character`: null means browse mode; set means walk mode (this is how a
  return from a run lands in walk mode).

## 7. Removed and changed

- Removed: `scenes/main_menu.tscn`, `scenes/character_select.tscn` and their scripts
  (`main_menu.gd`, `character_select.gd`). `project.godot`'s main scene becomes the hub.
  Their useful pieces (the ability row layout, the placeholder preview) are reused by the new info panel.
- Changed: `GameSession`, `PauseMenu`, `EndScreen`, `Hud` (optional run info), `Mana` (infinite flag),
  `CameraFollow` and the world-size users (section 3), `EnemyData` (`immovable`), `CharacterData` (trait text).
- The README's "Run it" section stays accurate; its character-select mention is updated.
- Note: a local, uncommitted edit to `main_menu.tscn` would be deleted along with the scene.

## 8. Menus

- **Hub pause menu (Esc / Start):** Continue, Exit.
- **Run pause menu:** Continue, **Return to Hub**, Exit.
- **End screen:** time, level and kills as today, then **Restart** (new run, same character) and
  **Return to Hub**.
- Return to Hub from the run pause menu abandons the run without confirmation (as "Main Menu" did).

## 9. Sounds

New generated sounds (`tools/gen_sfx.py`): `hub_focus` (soft tick), `hub_choose` (chime), `door_open`, `door_enter`.
Reuses `menu_click` for the buttons. Added to the `Audio` autoload list.

## 10. Technical notes

- **Hub scene** (`scenes/hub.tscn`, script `hub.gd`): `HubRoom` (ground, walls, door), `World/Pedestals`,
  `World/Dummies`, `World/Players` (Y-sorted), `World/Effects`, `World/Zones`, `World/PlayerProjectiles`, a
  `Camera`, and a `UI` CanvasLayer (Hud, info panel, hint bar, pause menu). A `HubController` node owns the two
  modes as a small state machine (`BROWSE`, `WALK`).
- **Info panel** is built in code like the other menus (`UiKit`), in `scripts/ui/hub_info_panel.gd`.
- **Pedestals** are `HubPedestal` nodes (a drawn platform, a display figure, a label, and a click area).
- **Display figures** reuse the Knight's `sprite_frames` when present, else the placeholder sprite script.
- `Hud.bind` takes an optional `RunManager`; with none it draws only mana and the icons.
- `PauseMenu` takes a mode (hub or run) to choose its buttons.
- Entering and leaving walk mode must free the Player and clear `PlayerRegistry` (the registry already unregisters
  on tree exit).
- Training dummies must be excluded from anything that counts or spawns: no gems, no kills, not pooled.

## 11. Build order

1. **M23 Foundations:** `Arena.world_size` refactor, `SceneFader`, `GameSession` hub flow, empty hub scene (room,
   walls, door, camera) as the main scene, remove the two old screens, update the pause menu and end screen.
   *The game boots into an empty hub and a run can be started and returned from.*
2. **M24 Pedestals and browse mode:** pedestals and display figures, browse camera and input, the info panel,
   `CharacterData` trait text, focus and confirm sounds. *Review stop: does choosing a character feel good?*
3. **M25 Walk mode:** spawning as the chosen character, hub HUD, infinite mana, the interact prompt and returning
   to browse mode, the door trigger and fade, return-to-hub state.
4. **M26 Training dummies:** `immovable`, the dummy data and brain, the readout. *Review stop (the full hub).*
5. **M27 Polish and check:** sounds, door visuals, tests, performance check, docs and README. *Final review.*

## 12. Definition of Done for v0.4

- The game launches into the hub; there is no Main Menu or Character Select scene in the project.
- In browse mode Left/Right and clicking move the camera between pedestals; the panel shows the right data for
  each character (numbers match the data files); Enter or the Choose button confirms.
- After choosing, a Player of that character exists in the hub; abilities work; mana never decreases; cooldowns
  work; the door is lit.
- Interact near the pedestals returns to browse mode with that character focused; choosing another character
  works and leaves only one Player in the world.
- The three dummies take damage from every ability of both characters, show numbers and the readout, and never
  die or move.
- Walking into the door fades out and starts a run as that character; the run is unchanged apart from the menus.
- A run's end screen offers Restart and Return to Hub; Return to Hub lands in walk mode as the same character
  near the door and does not immediately re-enter the run.
- The hub pause menu has Continue and Exit; the run pause menu has Return to Hub.
- The Knight and Wizard play exactly as before in a run (the existing scripted checks still pass).
- About 60 FPS in the hub with both characters' abilities in use, and no regression in the run.
- Gamepad and keyboard-and-mouse both work for every step (untested hardware items are listed as such).

## 13. Assumptions to Revisit Later

- The room size and pedestal spacing are guesses.
- The Choose, interact and info keys (Enter/F/I) and the use of A/D for browsing may collide with muscle memory
  for movement; browse mode has no movement, so this should be harmless.
- Infinite mana in the hub hides the real mana economy of a kit; that is deliberate, for practice.
- Indestructible dummies cannot show how fast a character clears enemies.
- Showing "no character chosen" until the first choice means the door is unusable at boot; there is no "quick
  start" shortcut.
- With few characters, a row of pedestals fits one screen; with many, browsing scrolls the camera.
- No saved last character means every launch starts in browse mode.
