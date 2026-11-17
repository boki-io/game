class_name CharacterRegistry
extends RefCounted
## All playable characters. Paths are listed explicitly so exported builds find them.

const PATHS := [
	"res://content/characters/knight/character.tres",
	"res://content/characters/wizard/character.tres",
	"res://content/characters/archer/character.tres",
]


static func all() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for path: String in PATHS:
		out.append(load(path))
	return out
