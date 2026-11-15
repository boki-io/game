extends Node
## Autoload. Nothing else references "the player"; ask here instead.

var players: Array[Player] = []


func register(player: Player) -> void:
	if not players.has(player):
		players.append(player)


func unregister(player: Player) -> void:
	players.erase(player)


## Nearest living player, or null if there is none.
func nearest(from: Vector2) -> Player:
	var best: Player = null
	var best_dist := INF
	for p in players:
		if p.dead:
			continue
		var d := from.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


func random_alive() -> Player:
	var alive := players.filter(func(p: Player) -> bool: return not p.dead)
	if alive.is_empty():
		return null
	return alive.pick_random()


func all_dead() -> bool:
	return players.all(func(p: Player) -> bool: return p.dead)
