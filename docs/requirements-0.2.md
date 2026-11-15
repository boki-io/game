# Requirements capture for v0.2 (draft, not yet a spec)

Raw requirements as stated by the product owner, plus proposed defaults and open questions.
This becomes `spec-0.2.md` once the open questions are answered.

## 1. Stated requirements

### Main menu
- A main menu is the first screen shown when the game starts.
- For now it only offers starting a new game.

### Character select
- Starting a new game leads to a character select screen.
- For now there is one character (the Sword).
- The screen shows the character and their abilities.

### New enemy: Dasher
- Taller than the Grunt, walks slower, has more health.
- When the player comes within a certain range, it stops moving.
- It projects a dash path on the ground for about 1.5 seconds, then dashes along that path.
- The timing (1.5s) is a guess and should be adjusted to the existing pace of the game.
- It must be clearly visible that the player needs to dodge it.

### New enemy: Ranged
- Stops to shoot a projectile.
- About 1 shot per 2 seconds (a guess; adjust for pace).

### Spawn mix
- 60% standard enemy, 15% ranged, 15% dashers.
- NOTE: these sum to 90%. See open question 1.

## 2. Pace reference (v0.1 values the new enemies must feel right against)
- Player: 90 px/s, 100 HP, Dash & Slash covers 64px in 0.15s with invulnerability.
- Grunt: 20 HP, 45 px/s, 5 contact damage every 0.5s.
- Screen is 480x270; spawn ring radius is about 300px.
- A grunt dies to two Slashes (10 damage each).

## 3. Proposed defaults (change any of these)
- Dasher: 60 HP, 30 px/s, 36px-tall sprite. Triggers at 110px. Telegraph 1.0s (1.5s is a long time
  at this pace; the player can walk about 135px in that time). The line tracks the player for the first
  60% then locks, so the final 0.4s is a fair reaction window. Dash 140px at 300 px/s. 0.8s recovery
  where it stands still and is easy to punish. 15 damage on hit, once per dash.
- Ranged: 25 HP, 40 px/s. Walks toward the player until 130px away, then stops and fires every 2.0s.
  The shot has a 0.4s wind-up flash before it leaves. Projectile 8 damage, 110 px/s, travels in a straight
  line, disappears at walls or after 3s.
- Dash i-frames (Q) avoid both the dash and projectiles.
- A stunned enemy cancels its wind-up or telegraph. Knockback does not.
- XP drops: Grunt 1, Ranged 2, Dasher 3.
- Enemy HP scaling and the 300 alive cap apply to all types.
- New enemies reuse the existing placeholder rectangle art, in distinct colors.
- Character select shows the sprite, name, one-line description, and each ability's key, name,
  cooldown, mana cost, and damage. Navigable by mouse, keyboard, and gamepad.

## 4. Open questions
1. Spawn mix adds to 90%. Is the Grunt 70%, or is there a fourth type?
2. Do Dashers and Ranged enemies appear from 0:00 or phase in over time?
3. Should the pause menu and end screen get a "Main Menu" button?
4. Can the player destroy projectiles with Slash, Spin, or Slam?
