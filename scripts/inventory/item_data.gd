class_name ItemData
extends Resource
## One piece of equipment (spec 1.4). One folder per item: content/items/<id>/item.tres, listed in ItemRegistry.PATHS.
## Its bonuses use the format of AttributeData: `adds` are added, `scales` multiply as 1 + fraction.

## Equals the folder name.
@export var id: StringName = &""
@export var display_name := ""
## One short line shown on the inventory screen (at most 80 characters: two lines of the description label).
@export var description := ""
## The item type: helmet, chestplate, necklace, ring, pants or shoes (Inventory.TYPES). A ring fits either ring slot.
@export var slot: StringName = &"helmet"
## Optional, 24x24 or smaller. Without it the screen draws a coloured square with the first letter of the name.
@export var icon: Texture2D
## Stats key -> amount (for example max_hp: 10).
@export var adds: Dictionary = {}
## Stats key -> fraction (for example damage: 0.1 for x1.1; negative lowers).
@export var scales: Dictionary = {}
