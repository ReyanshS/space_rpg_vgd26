# ---------------------------------------------------------------------------
# game_state.gd  -  remembers things BETWEEN levels. It's an AUTOLOAD named "Game".
#
# When you change scene (level 1 -> level 2), Godot throws the old scene away,
# with every variable in it. So anything that has to survive - power cells
# collected, retries, time - lives here instead. Godot creates this node ONCE
# when the game starts and keeps it alive until you quit: that's an autoload
# (also called a "singleton"). It's listed in Project Settings > Globals > Autoload.
#
# Any script can use it by its name, e.g.  Game.o2_bonus()  or  Game.go_to_level(2)
# ---------------------------------------------------------------------------
extends Node

## The levels in the order you play them. Add Level 3 here when it exists.
const LEVELS: Array[String] = [
	"res://Scenes/level_1.tscn",
	"res://Scenes/level_2.tscn",
]
const TITLE_SCENE := "res://Scenes/title.tscn"

## Extra seconds of oxygen on a spacewalk for every power cell you charged so far.
## This is the RPG "upgrade": exploring earlier levels makes later ones easier.
const O2_PER_CELL := 5.0

# One entry per level number, e.g. results[1] = {"time": 140.2, "cells": 7, ...}
var results := {}
# Tips PIP already gave (so he explains something only once, even across levels)
var _tips_seen := {}


## Forget everything (the title screen calls this when you start a new game).
func new_game() -> void:
	results.clear()


## The level calls this when you finish it.
func record_level(number: int, stats: Dictionary) -> void:
	results[number] = stats


## Power cells charged in every level finished so far.
func cells_collected() -> int:
	var n := 0
	for stats in results.values():
		n += int(stats.get("cells", 0))
	return n


func o2_bonus() -> float:
	return cells_collected() * O2_PER_CELL


## True the FIRST time it's asked about `tip`, false every time after that.
## e.g.  if Game.first_time("cell_kept"): hud.say(...)   -> PIP explains it once.
func first_time(tip: String) -> bool:
	if _tips_seen.has(tip):
		return false
	_tips_seen[tip] = true
	return true


func has_level(number: int) -> bool:
	return number >= 1 and number <= LEVELS.size()


func go_to_level(number: int) -> void:
	if has_level(number):
		get_tree().change_scene_to_file(LEVELS[number - 1])
	else:
		go_to_title()


func go_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


## Values that story text can use: write {cells}, {o2_bonus} or {o2_per_cell} inside a line.
func story_values() -> Dictionary:
	return {"cells": cells_collected(), "o2_bonus": int(o2_bonus()), "o2_per_cell": int(O2_PER_CELL)}
