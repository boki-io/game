class_name LootData
extends Resource
## The item loot table (spec 1.5): how likely each rating is when an item drops, how near a player must come to take it
## and how many may lie on the ground at once. One file (content/items/loot.tres), so rarity is tuned in one place.

## Rating (ItemData.RATINGS) -> relative weight. A rating with no item left to drop is skipped and the rest rescale.
@export var weights: Dictionary = {&"standard": 70.0, &"epic": 25.0, &"legendary": 5.0}
## Distance in px from the player's body point at which a lying item is taken.
@export var pick_distance := 14.0
## At most this many item drops lie on the ground at once (a hopping one counts).
@export var max_lying := 6
