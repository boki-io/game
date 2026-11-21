# Items

One folder per item: `content/items/<id>/item.tres` (an `ItemData`, `scripts/inventory/item_data.gd`) and, later, its
`icon.png` beside it. No item ships yet (spec 1.4 built the system; the items come next).

To add an item:
1. Make `content/items/<id>/item.tres` with `id` equal to the folder name, a `display_name`, a one-line `description`
   (at most 80 characters: the screen shows two lines), a `slot` (`helmet`, `chestplate`, `necklace`, `ring`, `pants` or
   `shoes`; a ring fits either ring slot) and its bonuses.
2. Bonuses: `adds` (stat key -> amount, added) and `scales` (stat key -> fraction, multiplied as `1 + fraction`), the same
   format and keys as `content/attributes/*.tres` and the upgrades: `max_hp`, `damage`, `move_speed`, `pickup_radius`,
   `hp_regen`, `mana_regen`, `max_mana`, `auto_speed`, `cooldown`. They are written to the hero's `Stats` when it is created.
3. An optional `icon` (24x24 or smaller); without one the screen draws a coloured square with the first letter of the name.
4. Add its path to `ItemRegistry.PATHS` (`scripts/inventory/item_registry.gd`) so exported builds find it.
5. To make the player own it, call `GameSession.inventory.unlock(&"<id>")` (the way the player gets items is not built yet).

Teach `tests/content_load.gd` about `ItemData` when the first items land; `tests/inventory/inventory_model.gd` already
checks every registered item's id, slot, description length and stat keys.
