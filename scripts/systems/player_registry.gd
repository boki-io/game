extends Node
## Autoload. Nothing else references "the player"; ask here instead.

var players: Array[Node2D] = []


func register(player: Node2D) -> void:
	if not players.has(player):
		players.append(player)


func unregister(player: Node2D) -> void:
	players.erase(player)


func nearest(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for p in players:
		var d := from.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best
