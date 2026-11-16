class_name SteadyAim
extends Node
## Archer trait. Arrows hit harder the further they have flown: 1.0x up to MIN_DISTANCE, rising linearly to BONUS
## at the full distance, BONUS beyond. The projectile applies it where damage is dealt (spec 1.1, sections 5 and 6),
## so this node only carries the numbers and the static multiplier (no autoload use, so a test can preload it).

const BONUS := 1.30
const FULL_DISTANCE := 160.0
const MIN_DISTANCE := 40.0

## Never true: Player.trait_active() reads it for the HUD's FOCUS label, which Steady Aim does not show.
var active := false


## Damage multiplier for an arrow whose launch point is `distance` px (straight line) from the enemy hit.
static func multiplier(distance: float, full_distance: float = FULL_DISTANCE) -> float:
	if full_distance <= MIN_DISTANCE:
		return BONUS if distance >= full_distance else 1.0
	var t := clampf((distance - MIN_DISTANCE) / (full_distance - MIN_DISTANCE), 0.0, 1.0)
	return lerpf(1.0, BONUS, t)
