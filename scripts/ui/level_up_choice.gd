class_name LevelUpChoice
extends RefCounted
## One card on the level-up menu: a stat upgrade or a relic (new or raised). `apply` does the work when picked.

var title := ""
## Small caps line under the title: the stat tag, or RELIC.
var tag := ""
var description := ""
## 0 on a relic card means a relic the player does not own yet (the card reads NEW).
var from_level := 0
var to_level := 1
var apply: Callable
## Draw weight against the other cards of a roll.
var weight := 1.0
var is_relic := false


## The card text under the title and tag: `NEW` or `Lv a -> b`.
func level_text() -> String:
	return "NEW" if is_relic and from_level == 0 else "Lv %d -> %d" % [from_level, to_level]
