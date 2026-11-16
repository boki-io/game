class_name RicochetBehavior
extends AbilityBehavior
## Ricochet Volley: fire and forget, like Meteor. The cast is instant, so the caster is never busy and Q or R can
## be pressed during the volley; a RicochetVolley node on the Player fires the arrows one after another.
## Upgrades: More Arrows (ricochet.extra), Bouncier (ricochet.bounces), Armour Piercing (ricochet.hits).


func cast(c: AbilityCaster, _aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	var volley := c.player.get_node_or_null("RicochetVolley") as RicochetVolley
	if volley == null:
		volley = RicochetVolley.new()
		volley.name = "RicochetVolley"
		c.player.add_child(volley)
	volley.start(c, d)
