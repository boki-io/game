class_name VacuumData
extends Resource
## Tuning of the vacuum magnet (spec 1.3): how often it drops, how long it lies on the ground and how the vacuum it starts
## behaves. One file: content/pickups/vacuum_magnet.tres.

## Chance per killed mob with xp_drop > 0 that a magnet drops (at most one on the map at a time).
@export_range(0.0, 1.0, 0.001) var drop_chance := 0.01
## Seconds the vacuum runs once the magnet is taken.
@export var effect_time := 5.0
## Seconds the magnet lies on the ground before it is gone.
@export var lifetime := 30.0
## The last seconds of the lifetime, in which the magnet blinks.
@export var flash_time := 10.0
## Blinks per second.
@export var flash_hz := 4.0
## How close (px) the player's body point must be to take it.
@export var pick_distance := 14.0
## Top speed (px/s) and acceleration (px/s^2) of XP gems and coins while the vacuum runs (normally 320 and 500).
@export var pull_speed := 1000.0
@export var pull_accel := 3000.0
