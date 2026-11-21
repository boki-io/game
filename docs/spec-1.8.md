# Spec v1.8: Hordes in the overworld (casual road hordes, harder dead-end dens, wake on sight)

Builds on the overworld (spec 1.6: `WorldData`, `Overworld`, the markers, `Journey`/`JourneySave`, `OverworldRules.SAFE_RADIUS_TILES`), the nature props (spec 1.7), the enemies (`Enemy`, `EnemyBrain`, `SpawnDirector`, `EnemyGrid`, `ObstacleMap`; specs 0.x to 1.2), the rewards (`Pickups`, `XPGem`, `Coin`, `ItemDrop`) and the world design in `/Users/bok/Documents/game-characters/map/map-instructions.md` ("the guide", section 9: camps, arenas, route patrols, the 14 tile safe radius). Branch `spec-1.8-overworld-enemies`, based on `main` at `5691569` (PRs #19 to #21 are merged, #21 is the blue door). Status: draft; rev 1.

Terms: a **horde** is a group of enemies that live together at a **home** and wake together as they see the player. A **site** is a place a horde can exist (data, built offline from the map). The horde **kinds**: **route** (beside the main road, casual), **big route** (an occasional larger one on the road), **trail** (along the side trail to a dead end), **guard** (at the mouth of a cave, dungeon or special site), **den** (the dead end itself: a camp or a cache, the biggest and hardest). A **dead end** is a side trail that ends at a camp or a cache. A **trail** is the shortest walkable way from the main route to a dead end. To **materialise** a horde is to create its enemies when the player gets near; to **dematerialise** it is to remove them when the player is far.

## Flow

You walk the road and meet small, spread-out groups of enemies beside it: four to seven grunts standing about, not moving. Most do nothing until you come into their view; when one sees you, it and its neighbours turn and come at you, and you fight a handful. Now and then (about one road site in six) the group is larger and has a shooter or two. Side trails are more crowded and harder, and at the end of a trail, in the camp clearing, the den holds a big spread-out horde of grunts, shooters and chargers. Enemies only attack once you are within sight (about 300 px and not behind a wall); if you run away they give up and walk home. A den you clear stays cleared; the road regrows. Killing gives XP, coins and (from chargers) item drops as in the arena; you level up in the overworld; dying sends you back to your last lit checkpoint. Resting points (the start camp, checkpoints, gates) are safe: no horde stands in their 14 tile radius, and enemies stop chasing you inside it.

## 1. Scope

In scope:
- Horde sites built from the map: along the main route, along each side trail, at dead ends and at cave, dungeon and special entrances (section 3).
- The horde plan: sizes, compositions by zone and kind, spread-out placement, from fixed seeds (section 4).
- Wake on sight, alert, leash and return home (section 5).
- Navigation for enemies on the world's tile walls, in place of the arena's `ObstacleMap` (section 6).
- The runtime `HordeDirector`: materialising and removing hordes near the player, pooling, rewards, den clearing (section 7).
- The overworld scene gains enemies, enemy shots, pickups, the level-up menu and death handling (section 8).
- Tuning as data (`HordeRules`, section 9), tests and docs.

Out of scope (later specs): bosses; the gates' lock; roaming patrols that walk between places; ambushes in the four arenas (their pockets are used as ordinary big route sites, section 3); enemies that respawn mid-fight; new enemy types or new art (the three types `grunt`, `ranged`, `dasher` (the charger art) exist; each zone's looks come from its `MapTheme` monster variants); the camp totem or banner; per-horde loot tables beyond a den bonus; enemies avoiding the nature props' trunk circles (they walk through them, O3); difficulty by player level.

## 2. Decisions taken (from the user's answers and the request)

- **Where:** beside the road, near camps, inside dead ends and along the trails to them. Dead ends hold a larger, harder horde (more shooters and chargers); the road is casual with an occasional larger horde.
- **Behaviour:** the group is spread out and grouped; enemies only attack once the player comes into view (radius plus line of sight); after that they leash: they give up when the player is far or out of sight and walk back home.
- **Scope:** all eight zones, tiered by data.
- **Respawn:** dens are cleared for good (saved per journey); everything else regrows whenever its area is entered again.
- **Rewards:** the arena's: XP gems and level-ups, coins, magnets, item drops.
- Assumed, not asked: death returns the hero to the last lit checkpoint with full health, keeping everything (section 8); guards at cave, dungeon and special mouths are medium hordes (O1).

## 3. Sites: where hordes can be (`tools/overworld/build_horde_sites.py`)

The map data has the route (`main_path`, 841 points about 8 tiles apart, in `markers.json`) and the markers; it has no side trail geometry. The sites are therefore built offline and committed, the same way as the edge-depth map:

`tools/overworld/build_horde_sites.py` (`[--check]`, Python 3 with numpy and the same small PNG reader as the other tools):
1. Reads `collision.png` (walkable where > 127) and `markers.json`.
2. A multi-source breadth-first search (4 neighbours, level by level with numpy) from every route point gives, for every walkable tile, its distance to the route and a parent pointer. (Measured for zone 0: dead ends are 140 to 410 tiles from the route.)
3. **Trails:** for every marker of kind `camp`, `cache`, `cave`, `dungeon`, `special` that is more than 20 tiles from the route, the chain of parents from the marker back to the route is its trail (a polyline in tiles).
4. **Route sites:** every `route_stride` (8, so about 64 tiles) points of `main_path`, skipping those within `SAFE_RADIUS_TILES` (14) of the start camp, a checkpoint or a gate; each site records the tile, the zone, and `route_t` (0 to 1 along its zone, from the zone's `route_start_tile` and `route_end_tile`).
5. **Trail sites:** along each trail every `trail_stride` (24) tiles from the route end to the dead end, skipping the first 30 tiles (the junction with the road) and anything within 14 tiles of a safe marker; each records the tile, the marker index, `trail_t` (0 at the road, 1 at the end).
6. Writes `content/overworld/data/horde_sites.json`: `{"version": 1, "route": [{x, y, zone, t}], "trails": [{marker, kind, points: [{x, y, t}]}]}` (a few hundred entries, tens of KB), sorted for a stable diff. `--check` rebuilds and exits 1 on a difference. Run time under a minute.

Dens and guards are not site entries: they come from the markers themselves (the camp or cache marker for a den; the cave, dungeon or special marker for a guard), read by `WorldData`.

`HordeSites` (`scripts/overworld/horde_sites.gd`, a `RefCounted` with static loaders and a spatial grid by 512 px cell) loads the JSON (like `WorldData.markers`) and answers "which sites are near this point".

## 4. The plan: `HordePlan` (`scripts/overworld/horde_plan.gd`) and `HordeRules` (section 9)

A pure `RefCounted` with static functions, no nodes, seeded like `NatureLayout`.

`HordePlan.build(world, sites, rules) -> Array[Horde]` returns every horde of the world (a few hundred; each `Horde` is small data):

| Field | Meaning |
|---|---|
| `id` | stable string: `route:<n>`, `trail:<marker>:<n>`, `guard:<marker>`, `den:<marker>` |
| `kind` | `route`, `route_big`, `trail`, `guard`, `den` |
| `home` | world px, a walkable tile centre |
| `zone`, `tier` | zone index, and the strength tier (the zone index, plus `rules.kind_tier_bonus[kind]`) |
| `size` | member count |
| `radius` | spread radius in px |
| `members` | `Array[StringName]` of type ids, in order (the composition) |
| `hp_mult`, `xp_mult` | scaling |
| `seed` | an integer derived from the id and `rules.seed` |

How a horde is decided (every number is data, section 9; defaults here are first-pass and will be tuned by rendering):
- **Route sites:** each is a `route` horde of `route_size` (4 to 7) members; with probability `route_big_chance` (0.17, drawn from the site's own seeded stream) it is `route_big` with `route_big_size` (12 to 18). Composition: from the zone's `route` weights, with the shooters and chargers limited to the big ones (a small road horde is grunts only in the first zones).
- **Trail sites:** `trail` hordes of `trail_size` (5 to 9), heavier near the end: the size is scaled by `1 + trail_size_ramp * t` (0.6), the weights come from the zone's `trail` row, and `tier` gets `+1`.
- **Guards:** one `guard` horde of `guard_size` (6 to 10) placed 8 to 14 tiles from a cave, dungeon or special marker, on the trail side (towards the route), outside the 7 tile clearing the nature props already keep.
- **Dens:** one `den` horde at every camp and cache marker: `den_size` (18 to 28) for a camp, `cache_den_size` (14 to 22) for a cache; composition from the zone's `den` weights, which is where the shooters and chargers are (section 9's defaults: grunt 50 %, shooter 25 %, charger 25 % in zone 0, more of the latter two in later zones); `tier` gets `+2`. The den spreads over a radius of up to 18 tiles, inside the camp's clearing (the guide: about 44 tiles across).
- **Arenas:** each of the four arena markers gets a `route_big` horde at its centre (open pockets of 26 to 36 tiles radius: space for a spread-out group).
- **Safe radius:** no horde's home or member is within `SAFE_RADIUS_TILES` (14) of the start camp, a checkpoint or a gate; a candidate that fails is dropped (the site simply has no horde).
- **Scaling:** `hp_mult = 1 + hp_per_tier * tier + hp_per_route * route_t`, `xp_mult = 1 + xp_per_tier * tier` (rules).

**Spread and grouping** (`HordePlan.member_positions(world, horde) -> PackedVector2Array`, called when a horde materialises, deterministic from `horde.seed`):
- Members are divided into **squads** of 3 to 5; a squad centre is placed by Poisson-disc sampling inside the horde radius with a minimum spacing `squad_spacing_px` (72 for a small horde, scaled up with the radius); members stand around their squad centre within `squad_radius_px` (28) with at least `member_spacing_px` (18) between them. A route horde is one or two squads; a den is five or six squads scattered across the clearing, so it looks like a spread-out camp, not one blob.
- Every position is a walkable tile at least 2 tiles from a blocked tile, found by a few retries; a member that cannot be placed is dropped (the horde just has one fewer).
- Hordes never overlap: two homes closer than `min_home_gap_tiles` (18) keep only the stronger one; this is applied while building the plan, in a fixed order.

## 5. Behaviour: sleeping, waking, the leash

States of one enemy: **dormant** (stands at its post, idles, no attack, not chasing), **awake** (the arena brain: chases, shoots, dashes) and **returning** (walks home, harmless).

Rules (all numbers data):
- **Wake:** a dormant member wakes when the nearest player is within `wake_radius` (300 px, about the screen's half-width) **and** the line is clear (`ObstacleMap.segment_clear`-style, section 6; walls block it). Checked every `check_interval` (0.2 s), staggered by member so the cost spreads.
- **Alert:** a member that wakes also wakes dormant members of its horde within `alert_radius` (96 px), and those wake their neighbours the same way next check; so a squad wakes together and a den wakes progressively as you walk into it, not all at once from far away.
- **Chase:** an awake member runs its brain as in the arena: grunts chase, shooters hold and fire (only with a clear line: the brain already checks), chargers aim and dash. Contact damage and shots only happen while awake.
- **Leash:** an awake member that is farther than `leash_radius` (600 px) from the nearest player, or has had no clear line for `lose_sight_time` (6 s), or whose player is inside a safe radius, becomes **returning**.
- **Return:** it walks straight to its post at `return_speed_mult` (1.2) times its speed through the navigation (section 6), takes no part in fights, heals to full on arrival and becomes dormant. A returning member whose wake conditions are met again wakes again.
- **Stuck:** the existing stuck failsafe in `Enemy` teleports a stuck chaser to the arena spawn ring; in the overworld it instead sends the member home (`director.on_stuck`), so nothing teleports into the player's view.

`Enemy` change (small, in `scripts/enemy/enemy.gd`): a `state` (`CHASE` default, `DORMANT`, `RETURNING`), a `home` position, and in `_physics_process` the brain is asked only in `CHASE`; `DORMANT` stands still (separation only); `RETURNING` moves toward `home`; contact hits only happen in `CHASE`. The teleport-back at the end of `_physics_process` and `_check_stuck` are skipped when `director.teleport_distance` is `INF` (the overworld director's value) and call `director.on_stuck(enemy)` if the director has it. The arena behaviour is unchanged (state `CHASE`, a `SpawnDirector` with a finite `teleport_distance`).

## 6. Navigation: `WorldObstacles` (`scripts/overworld/world_obstacles.gd`)

The arena's `ObstacleMap` holds wall rectangles and pillar circles and a flow field over the whole arena; a 32,000 px world is far too big for that. `WorldObstacles extends ObstacleMap` and overrides the queries `Enemy` and the brains use so they read the world's walkable mask instead: `has_obstacles()` (true), `blocked(pos, radius)`, `push_out(pos, radius)`, `segment_clear(a, b, radius)`, `ray_distance(from, dir, max_len, radius)` and `flow_direction(pos)`. It joins the `obstacles` group the way `ObstacleMap` does (`ObstacleMap.get_for(node)`), so enemies find it without changes.
- **Blocked** is a non-walkable tile (`WorldData.collision` <= 127), the same rule that builds the wall colliders (the colliders cover depth 1 to 2; deeper tiles cannot be reached anyway). A circle of radius up to 16 (the queries' stated limit) is tested against the tile rectangles it overlaps; `push_out` moves it out along the shortest axis, up to 4 passes (like `ObstacleMap.push_out`'s contract: the nearest clear position).
- **segment_clear** samples every 8 px along the segment; **ray_distance** steps the same way to the first blocked sample.
- **Flow field:** a local breadth-first field over walkable tiles in a window of 96 x 96 tiles (about 1,500 px) centred on the nearest player, from the player's tile outward, rebuilt when the player has moved to another tile and at least `SEARCH_INTERVAL` (0.25 s) has passed, expanding at most `SEARCH_BUDGET` (1000) cells per physics frame so a rebuild spreads over a few frames (the arena's `FlowField` contract). `flow_direction(pos)` returns the unit vector towards the lowest neighbouring cell, or zero outside the window. `RETURNING` members use a second, per-horde target (their home) with the straight-line-or-flow rule: while the home is outside the window they walk straight and rely on `push_out` (a leash of 600 px keeps them inside the window in practice).
- The window covers the leash (600 px), so a chaser always has a field. A member outside it, or on a cell with no gradient, walks straight and slides along walls (`push_out`), which is what the arena's enemies do without a path.
- Cost: the window has 9,216 cells; a rebuild is under 10 ms in GDScript spread over frames; the target is under 2 ms per frame including the line-of-sight sampling for the live enemies (checked in section 11).

## 7. Runtime: `HordeDirector` (`scripts/overworld/horde_director.gd`)

`HordeDirector extends SpawnDirector` so it reuses the `Enemy` hooks (`director`, `release`, pooling) and the reward code, with the arena's timed ring spawning switched off. `SpawnDirector` gets two small changes: its `_physics_process` returns at once when `run_manager` is null (so a subclass or a scene without a run manager is safe) and `_on_enemy_died` counts kills only if `run_manager` exists.

- **Streaming:** the director holds the plan (built once at load; a few hundred hordes) in a 512 px spatial grid. Each physics frame it looks at the player's neighbourhood: a horde within `materialise_radius` (800 px, which is farther than the view's half diagonal, 367 px, plus the horde's radius, so enemies do not pop in on screen) and not cleared and not already live is **materialised**, at most `materialise_per_frame` (1) per frame: its members are placed (section 4), pulled from the pool for their type and zone, activated `DORMANT` at their posts with the horde's `hp_mult`. A live horde whose members are all dormant at their posts and farther than `dematerialise_radius` (1,200 px) is **dematerialised** (its enemies released to the pool; no state is kept: hordes regrow). A horde with awake or returning members is kept until they are home or dead.
- **Pools and looks:** one pool per (type, zone). Each pooled `Enemy` is dressed with the zone's `MapTheme` monster variant (`MapRegistry.by_id(zone id).variant_for(type id)`), as `SpawnDirector._acquire` does for the arena (it uses the stage's theme; the director overrides `_acquire` with the zone's).
- **Cap:** `max_alive` (120). A materialisation that would pass it waits (nearest hordes first). The live count is expected to stay about 40 to 90: a few small hordes in range and at most one or two big ones.
- **Rewards:** on a kill, as `SpawnDirector._on_enemy_died`: an XP gem worth `data.xp_drop * horde.xp_mult`, a coin by chance, magnet and item rolls (`Pickups`); `horde.members_left` goes down. The coin chance and bonuses read `CampAttributes` as the arena does.
- **Dens and clearing:** when the last member of a `den` dies the director calls `journey.mark_den_cleared(marker index)`, shows the banner "Camp cleared" (the overworld's banner), drops `den_bonus_coins` (data, 8) around the marker, and the den is never materialised again for this journey. The cleared list is saved with the journey (section 10). Partial kills are not saved: a den reloaded half-killed is whole again.
- **Death or teleport of the player:** when the hero respawns or the overworld otherwise moves the player far, `director.reset()` dematerialises everything at once.
- It does not touch the cave and dungeon runs, which use `main.tscn` and the arena `SpawnDirector`.

## 8. The overworld scene

`scenes/overworld.tscn` and `scripts/overworld/overworld.gd` gain what a fight needs (the arena scene `main.tscn` has them; today the overworld has none of them):
- `World/Enemies` (y-sorted, so enemies sort with the hero and the props), `World/Projectiles` (the enemy shot pool, `scripts/systems/projectiles.gd`, with `enemy_projectile.tscn`), a `Pickups` node configured as in `main.tscn` (gem, coin, vacuum magnet, loot data and item drop scenes), `HordeDirector` (a `Node` with the enemy scene and the three enemy types), `UI/LevelUpMenu`, and a `WorldObstacles` node.
- `Overworld._ready`: gives the director the world, the plan, the obstacles, the enemies root and the pickups; `$Pickups.inventory = GameSession.inventory` and its item signal as in `main.gd` (an item found shows the same banner, through the overworld's existing banner label); `player.xp.leveled_up` queues the level-up menu; the pause menu is given the level-up menu (`pause_menu.level_up_menu`).
- **Coins:** coins add to `GameSession.run_gold` as in the arena; the overworld banks them (`GameSession.bank_run()`) when you rest at a checkpoint, return to the hub, enter a cave or dungeon (a dungeon's own end already banks), or die.
- **Death:** `player.died` is connected. The death animation plays, the screen fades (`SceneFader`), the hero is placed at the last lit checkpoint (`journey.respawn` holds its name; the position is `WorldData.marker_world(world.marker_named(journey.respawn))`) with full health and mana, the director resets, the level, XP, upgrades and relics are kept, the gold is banked and the journey saved, then the screen fades in. Nothing is lost. A death screen is not shown (the arena's end screen is for runs).
- **Rest points:** `OverworldRules.SAFE_RADIUS_TILES` is read here (it was reserved for this spec); the director tells awake enemies to return while the player is inside the safe radius of a rest marker.
- `Hud.bind(player)` is unchanged (the HUD binds a run manager only in the arena).
- Dungeon and cave entry stay as they are; entering one dematerialises the hordes (the scene changes).

## 9. Tuning as data

`HordeRules` (`scripts/overworld/horde_rules.gd`, a `Resource` with typed `@export` fields) and `content/overworld/hordes.tres`: `seed`; for each of `route`, `route_big`, `trail`, `guard`, `den`: size ranges (`Vector2i`), spread radius, and per zone a `Dictionary` of type id to weight (so zone 0's road row is `{grunt: 1}`, its den row `{grunt: 0.5, ranged: 0.25, dasher: 0.25}`, and later zones shift weight towards shooters and chargers); `route_big_chance`, `route_stride`, `trail_stride`, `trail_size_ramp`, `kind_tier_bonus`, `hp_per_tier`, `hp_per_route`, `xp_per_tier`, `squad_size`, `squad_spacing_px`, `squad_radius_px`, `member_spacing_px`, `min_home_gap_tiles`; the behaviour numbers `wake_radius`, `alert_radius`, `leash_radius`, `lose_sight_time`, `return_speed_mult`, `check_interval`; the streaming numbers `materialise_radius`, `dematerialise_radius`, `materialise_per_frame`, `max_alive`; `den_bonus_coins`. The structural constants stay in `OverworldRules` (`SAFE_RADIUS_TILES`, the chunk numbers). Enemy stats stay in `content/enemies/*.tres`. Defaults are first-pass numbers for the first draw and are tuned by playing and rendering in build step 6; the final values go in this spec's build notes.

## 10. The journey save

`Journey` gets `cleared_dens: Array[String]` (keys like `camp:12` by marker index, since camp names are not unique: the 108 names have duplicates, verified) with `is_den_cleared(index)` and `mark_den_cleared(index)`; `JourneySave` writes it as `cleared_dens` and loads it leniently (a missing key is an empty list; old journeys load unchanged; the file's version number is not bumped). Cleared caves and dungeons keep using `cleared` (names).

## 11. Tests (in `tests/overworld/` unless noted)

- `horde_sites`: the committed JSON loads; every route site is walkable, in its zone, outside the safe radius; every trail starts within a few tiles of the route and ends within a few tiles of its marker, consecutive points are within `trail_stride` plus a few tiles, `t` is monotonic; there is a trail for every camp, cache, cave, dungeon and special more than 20 tiles from the route (and for none within it); `build_horde_sites.py --check` is listed in the build notes (the suite has no Python).
- `horde_plan` (pure, no nodes): the plan is identical across two builds; ids are unique; every home is walkable and outside the safe radius; there is a den at every camp and cache marker and no den elsewhere; den sizes are in range and larger than any trail horde which are larger than any small route horde in the same zone (a rule of the data); the share of `route_big` among route hordes of zone 0 is within 8 to 28 % (the data says 17 %); zone 0's small route hordes are all grunts and its dens hold at least one shooter and one charger; members are spread (the mean nearest-neighbour distance of a den's members is at least `member_spacing_px`, and the members of a den cover at least 5 tiles of radius); every member position is walkable and 2 tiles from a wall; no two homes are closer than `min_home_gap_tiles`; the plan for 30 seeds obeys all of the above.
- `world_obstacles`: `blocked`, `push_out`, `segment_clear` and `ray_distance` agree with the wall colliders on sampled tiles (a circle that `push_out` returns is not blocked; a segment across a wall is not clear; a clear straight segment is clear); the flow field leads a point around a wall to the target (follow `flow_direction` for up to 400 steps from 30 chosen starts and reach the target); a window rebuild stays within the per-frame budget.
- `horde_behavior` (scene or fixture with the real `Enemy` and a Player): a dormant enemy stays put and deals no damage even touching the hero; it wakes at 300 px with a clear line and not behind a wall at the same distance; alert wakes neighbours within 96 px and not those farther; an awake chaser beyond 600 px, or without sight for 6 s, returns, heals and goes dormant; the arena `SpawnDirector` enemies still teleport and chase as before (the state default); a stuck member goes home, not to the ring.
- `horde_director`: hordes materialise at 800 px and not before, never inside the view rectangle, at most one per frame; dematerialise beyond 1,200 px when dormant, not while awake; the cap holds; pools reuse enemies per (type, zone) with the zone's look; a kill drops XP with the horde's `xp_mult`; killing a den marks it cleared and it does not materialise again (also after reloading the journey); a non-den horde regrows after leaving and returning; `reset()` clears all; total alive stays below the cap while walking the whole zone 0 route.
- `overworld_scene` / `overworld_walk` (existing): the walk test keeps working (the route may now have fights: the walk test places the hero along the route with enemies disabled by a `GameSession.scene_hook`-style flag, `OverworldRules`-free: the overworld has a `hordes_enabled` property the test sets to `false`); a new `overworld_fight` test walks into a zone 0 route horde with the real scene, kills it and sees XP; dies and sees the respawn at the last lit checkpoint with progress kept and gold banked; levels up and sees the level-up menu queued.
- `journey_save` (existing): `cleared_dens` round-trips; an old file loads with an empty list.
- Performance: in a rendered or headless run, 100 live enemies (a den plus two big hordes) around a hero cost under 4 ms per physics frame in the navigation and wake checks (a regression bound, not a promise).
- Seeded tests use 30 seeds (`SEED_COUNT`) and the rules' own seed.

## 12. Files

New: `docs/spec-1.8.md`; `tools/overworld/build_horde_sites.py`; `content/overworld/data/horde_sites.json`, `content/overworld/hordes.tres`; `scripts/overworld/horde_sites.gd`, `horde_rules.gd`, `horde_plan.gd`, `world_obstacles.gd`, `horde_director.gd` (+ `.uid`); `tests/overworld/horde_sites.gd`, `horde_plan.gd`, `world_obstacles.gd`, `horde_behavior.gd`, `horde_director.gd`, `overworld_fight.gd`.

Changed: `scripts/enemy/enemy.gd` (state, home, teleport guard); `scripts/systems/spawn_director.gd` (the null-run-manager guards); `scripts/overworld/overworld.gd`, `scenes/overworld.tscn` (section 8); `scripts/overworld/journey.gd`, `journey_save.gd` (section 10); `scripts/overworld/world_data.gd` (marker lookup helpers for dens and guards, if needed); `README.md`, `tests/README.md`, `content/overworld/README.md`, `docs/spec-1.6.md` (the pointer: O-items about enemies now point here).

Existing tests touched: `overworld_scene` and `overworld_walk` (the `hordes_enabled` switch, section 11), `journey_save` (a case), and every test that instantiates `Enemy` with a `SpawnDirector` must still pass unchanged (the state default is `CHASE`).

## 13. Build order

1. `build_horde_sites.py`, `horde_sites.json`, `HordeSites`, the `horde_sites` test. Commit.
2. `HordeRules`, `hordes.tres`, `HordePlan` (plan and member positions), the `horde_plan` test. Commit. (1 and 2 need no scene; 3 is independent of both: these three can run as parallel worktree subagents.)
3. `WorldObstacles` and its test. Commit.
4. `Enemy` states, `SpawnDirector` guards, `HordeDirector` (streaming, pools, wake and leash, rewards), the `horde_behavior` and `horde_director` tests. Commit.
5. The overworld scene and script wiring (enemies, shots, pickups, level-up, death and respawn, gold banking, `hordes_enabled`), `Journey` and `JourneySave` dens, den clearing and banner, the `overworld_fight` test, the updated `overworld_scene` / `overworld_walk` / `journey_save` tests. Commit.
6. Render and play: the road, a big route horde, a trail, a den, a wake and a leash; tune `hordes.tres`; update the numbers here, the READMEs and the build notes; run the whole suite. Commit.

Each step is one commit with its tests; the existing suite's only known failure is `crowd_bone_warren`.

## 14. Open questions / assumptions

- **O1.** Guards at cave, dungeon and special mouths are an addition (the user said dead ends, camps and the way to them; those sites sit on trail ends too). They can be set to size 0 in the data.
- **O2.** "Charger" is the `dasher` type (its art is the charger sheet). Dens in zone 0 already include chargers and shooters; whether zone 0 should be gentler is a tuning call in step 6.
- **O3.** Enemies ignore the nature props' trunk circles (the player collides with them, enemies walk through). A later step can feed the trunk circles to `WorldObstacles` if it looks wrong.
- **O4.** The wake radius of 300 px is about half the screen width, and shooters (hold 130 px, shots 110 px/s) can only fire inside it; the leash of 600 px is two wake radii. Both are data.
- **O5.** A den that is cleared stays cleared per journey; there is no reset. Camps' guide suggestion of a totem or banner is not built.
- **O6.** Rewards equal the arena's per kill; with hordes around, XP in the overworld may out-level the dungeons. Tuned in step 6 through `xp_per_tier` and the horde sizes; no difficulty scaling to the player's level is built.
- **O7.** The four arena markers hold a big route horde (no ambush trigger).
- **O8.** Enemy stats are unchanged; the horde `hp_mult` is the only scaling (no damage scaling), so later zones are harder through composition and health, as in the arena.
- **O9.** Performance: the arena's `crowd_bone_warren` test (300 enemies) already fails its frame-time limit; the overworld's cap of 120 is chosen below that, but only a rendered run shows the real cost.

## 15. Definition of Done

- The sites tool and data, the plan, `WorldObstacles`, the director, the enemy states and the scene wiring exist; `build_horde_sites.py --check` passes on the committed data.
- In zone 0 you meet small grunt hordes beside the road, an occasional bigger one with a shooter, crowded trails and a big den of grunts, shooters and chargers at each camp and cache; none within 14 tiles of a rest point.
- Enemies stay put until a member sees you (300 px, clear line), alert their neighbours, chase, and give up and walk home when you get away; chargers and shooters behave as in the arena; nothing attacks while dormant or returning.
- Kills give XP (with level-ups), coins, magnets and item drops; dying returns you to the last lit checkpoint with progress kept; a cleared den stays cleared after saving and reloading; the road regrows.
- Live enemy count stays within the cap while walking the zone 0 route; all new tests pass, earlier tests still pass (known failure: `crowd_bone_warren`), the READMEs and this spec's build notes are updated.
- A rendered check of a route horde, a den, a wake and a leash was looked at by the builder, and what was not checked by hand (a real play-through, balance) is said plainly in the PR.
