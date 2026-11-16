class_name StagePath
extends RefCounted
## The graph of one run: columns of stages and the edges between neighbouring columns. Built by PathGenerator.

## columns[c][i] is the StageData at row i (top to bottom) of column c.
var columns: Array = []
## edges[c][i] is the rows of column c + 1 that the stage at row i of column c leads to.
## The last column has no edges.
var edges: Array = []
var path_seed := 0


func column_count() -> int:
	return columns.size()


func stage_count() -> int:
	var n := 0
	for column: Array in columns:
		n += column.size()
	return n


func stage_at(column: int, row: int) -> StageData:
	return columns[column][row]


## Rows of `column` + 1 reachable from the stage at (`column`, `row`).
func next_rows(column: int, row: int) -> Array[int]:
	var out: Array[int] = []
	if column < edges.size():
		for r: int in edges[column][row]:
			out.append(r)
	return out


func all_stages() -> Array[StageData]:
	var out: Array[StageData] = []
	for column: Array in columns:
		for s: StageData in column:
			out.append(s)
	return out
