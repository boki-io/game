class_name ItemData
extends Resource
## One piece of equipment (spec 1.4). One folder per item: content/items/<id>/item.tres, listed in ItemRegistry.PATHS.
## Its bonuses use the format of AttributeData: `adds` are added, `scales` multiply as 1 + fraction.

## Equals the folder name.
@export var id: StringName = &""
@export var display_name := ""
## An optional flavour line shown under the stat line on the inventory screen (at most 40 characters).
@export var description := ""
## The item type: helmet, chestplate, necklace, ring, pants or shoes (Inventory.TYPES). A ring fits either ring slot.
@export var slot: StringName = &"helmet"
## standard, epic or legendary (ItemData.RATINGS). Tints the item's frame and its drop.
@export var rating: StringName = &"standard"
## The relic a worn legendary item grants for the whole run, in an extra relic slot (RelicData.id); empty for none.
@export var relic_id: StringName = &""
## Optional, 32x32 (the screen draws it 1:1; the 18 items use regions of assets/32x32.png). Without it the screen draws a coloured square with the first letter of the name.
@export var icon: Texture2D
## Stats key -> amount (for example max_hp: 10).
@export var adds: Dictionary = {}
## Stats key -> fraction (for example damage: 0.1 for x1.1; negative lowers).
@export var scales: Dictionary = {}


const RATINGS: Array[StringName] = [&"standard", &"epic", &"legendary"]
const RATING_COLORS := {&"standard": Color("b8b0a0"), &"epic": Color("b070ff"), &"legendary": Color("ff9a3a")}
const RATING_NAMES := {&"standard": "Standard", &"epic": "Epic", &"legendary": "Legendary"}
## How a stats key reads in stat_text().
const STAT_LABELS := {&"max_hp": "max HP", &"hp_regen": "HP/s", &"damage": "damage", &"auto_speed": "attack speed",
	&"cooldown": "ability cooldowns", &"move_speed": "move speed", &"pickup_radius": "pickup range",
	&"max_mana": "max mana", &"mana_regen": "mana/s"}


static func rating_color(r: StringName) -> Color:
	return RATING_COLORS.get(r, RATING_COLORS[&"standard"])


static func rating_name(r: StringName) -> String:
	return RATING_NAMES.get(r, "Standard")


## The bonuses as one line, `adds` then `scales`, each in file order: "+1.0 HP/s, +20 max HP", "-4% ability cooldowns".
## "" for an item with none.
func stat_text() -> String:
	var parts: Array[String] = []
	for key: StringName in adds:
		parts.append("%s %s" % [_signed(adds[key], false), STAT_LABELS.get(key, String(key))])
	for key: StringName in scales:
		parts.append("%s %s" % [_signed(scales[key] * 100.0, true), STAT_LABELS.get(key, String(key))])
	return ", ".join(parts)


static func _signed(value: float, percent: bool) -> String:
	var sign_text := "+" if value >= 0.0 else "-"
	var mag := absf(value)
	var number := "%d" % roundi(mag) if is_equal_approx(mag, roundf(mag)) else "%.1f" % mag
	return "%s%s%s" % [sign_text, number, "%" if percent else ""]
