class_name OverworldRules
extends RefCounted
## The overworld's structural constants (spec 1.6): things that are structure, not tuning (tuning is data: content/overworld).

const CHUNK_TILES := 32  # a chunk is 32 x 32 tiles (512 px)
const LOAD_RADIUS := 1  # chunks around the player's chunk that exist (3 x 3)
const UNLOAD_RADIUS := 2  # chunks farther than this from the player's chunk are freed
const BUILDS_PER_FRAME := 1
const FREES_PER_FRAME := 2
const COLLIDER_DEPTH := 2  # blocked tiles up to this many tiles from a walkable one get colliders
const DRAW_DEPTH := 15  # blocked tiles up to this depth are drawn (the edge-depth cap)
const SAFE_RADIUS_TILES := 14  # the guide's rest radius around the start camp, checkpoints and gates (read by the enemy spec)
const INTERACT_RADIUS := 48.0  # px: how close the player must be to a marker to use it
const NAME_RADIUS := 120.0  # px: a marker shows its name this close
const REDRAW_RADIUS := 480.0  # px: markers farther than this do not redraw
const FOG_CELL_TILES := 8  # a fog cell is 8 x 8 tiles (250 x 250 cells)
const FOG_REVEAL_TILES := 30
const SAVE_INTERVAL := 30.0  # seconds between the overworld's autosaves while the player has moved
const SAVE_MIN_MOVE := 100.0  # px


## Whether the gate called `gate_name` is locked. Always open in spec 1.6; the boss spec turns the lock on through
## Journey.gate_open (which reads a flag it sets).
static func gate_locked(_gate_name: String) -> bool:
	return false
