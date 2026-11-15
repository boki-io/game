class_name GruntBrain
extends EnemyBrain
## Walks straight at the nearest player.


func think(_delta: float, target: Player) -> Vector2:
	return enemy.chase(target, enemy.data.speed)
