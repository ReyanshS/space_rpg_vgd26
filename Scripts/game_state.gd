# ---------------------------------------------------------------------------
# game_state.gd: remembers things between levels. It's an autoload named "Game".
#
# When you change scene (level 1 -> level 2), Godot throws the old scene away,
# with every variable in it. So anything that has to survive (power cells
# collected, retries, time) lives here instead. Godot creates this node once
# when the game starts and keeps it alive until you quit: that's an autoload
# (also called a "singleton"). It's listed in Project Settings > Globals > Autoload.
#
# Any script can use it by its name, e.g.  Game.o2_bonus()  or  Game.go_to_level(2)
#
# The RPG side (skill points and the skill tree) lives in its own autoload,
# SkillManager (skill_manager.gd). This script SAVES it, together with which
# levels you've finished, to one save file (save_game / load_game), so the
# title screen can offer "Continue".
# ---------------------------------------------------------------------------
extends Node

## The levels in the order you play them.
const LEVELS: Array[String] = [
	"res://Scenes/level_1.tscn",
	"res://Scenes/level_2.tscn",
	"res://Scenes/level_3.tscn",
]
const TITLE_SCENE := "res://Scenes/title.tscn"

## The music: the team's own tracks, as Assets/audio/music_<name>.ogg.
## The number is each track's volume in dB (0 = as loud as the file, -6 = about
## half as loud). The files were mixed at different loudness, so each one gets
## its own volume to make them sound about equally loud in the game. Change
## them to taste: closer to 0 = louder.
const MUSIC := {
	"title": -18.0,   # "Title theme dramatic": the title screen
	# The level tracks are set a little louder than the title, because in a level
	# they play under the sound effects (and the wire's hum while you carry it).
	"ship": -21.0,    # "Space theme bells": inside the ship
	"space": -19.0,   # "Space theme bells 2": out on the hull (spacewalks)
	"core": -16.0,    # "Space staccato": the rogue PIP fight in Level 3
	"ending": -20.0,  # "Title theme no dramatic": after PIP reboots, to the last results
}

## Extra seconds of oxygen on a spacewalk for every power cell you charged so far.
## A small RPG reward: exploring earlier levels makes later ones easier.
const O2_PER_CELL := 5.0

## The save file. "user://" is a folder Godot keeps for this game on the
## player's computer (in a web build: inside the browser's storage).
const SAVE_PATH := "user://save.cfg"

# One entry per level number, e.g. results[1] = {"time": 140.2, "cells": 7, ...}
var results := {}
## True once a level was loaded by the game (title -> level, or "next level").
## Stays false when you run one level scene straight from the editor with F6:
## that's the only time a level's TestStart marker is used.
var playing_through := false
# Tips PIP already gave (so he explains something only once, even across levels)
var _tips_seen := {}


## Forget everything and delete the save (the title screen's "new game").
func new_game() -> void:
	results.clear()
	SkillManager.reset()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _ready() -> void:
	# Buying a skill saves straight away, so quitting mid level doesn't lose it.
	SkillManager.skill_unlocked.connect(func(_id: String) -> void: save_game())


## The level calls this when you finish it. It also saves the game.
func record_level(number: int, stats: Dictionary) -> void:
	results[number] = stats
	save_game()


## True if you've finished level `number` before (in this save).
func has_finished(number: int) -> bool:
	return results.has(number)


## Power cells charged in every level finished so far.
func cells_collected() -> int:
	var n := 0
	for stats in results.values():
		n += int(stats.get("cells", 0))
	return n


## Seconds of oxygen each kept battery gives (CELL CHARGER skill adds to it).
func o2_per_cell() -> float:
	return O2_PER_CELL + SkillManager.bonus("o2_per_cell")


## Extra oxygen on spacewalks: from batteries you kept, and the Life Support skills.
func o2_bonus() -> float:
	return cells_collected() * o2_per_cell() + SkillManager.bonus("o2")


## True the first time it's asked about `tip`, false every time after that.
## e.g.  if Game.first_time("cell_kept"): hud.say(...)   -> PIP explains it once.
func first_time(tip: String) -> bool:
	if _tips_seen.has(tip):
		return false
	_tips_seen[tip] = true
	return true


## Loads music track `track_name` (a key of `MUSIC`) and makes it loop forever.
## Returns null if the file isn't there (the game just stays quiet).
func load_music(track_name: String) -> AudioStream:
	var path := "res://Assets/audio/music_%s.ogg" % track_name
	if not ResourceLoader.exists(path):
		return null
	var s = load(path)
	if s is AudioStreamOggVorbis:
		s.loop = true        # when it reaches the end, start again from the top
	return s


func has_level(number: int) -> bool:
	return number >= 1 and number <= LEVELS.size()


func go_to_level(number: int) -> void:
	get_tree().paused = false       # pausing survives a scene change, so make sure it's off
	if has_level(number):
		playing_through = true
		get_tree().change_scene_to_file(LEVELS[number - 1])
	else:
		go_to_title()


func go_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


## Values that story text can use: write {cells}, {o2_bonus} or {o2_per_cell} inside a line.
func story_values() -> Dictionary:
	return {"cells": cells_collected(), "o2_bonus": int(o2_bonus()), "o2_per_cell": int(o2_per_cell())}


# ------------------------------------------------------------------ the save file
# A ConfigFile is a simple text file with [sections] and key = value lines,
# like project.godot. Godot can store dictionaries and arrays in it directly.

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "results", results)
	var skills := SkillManager.to_save()
	cfg.set_value("skills", "points", skills["points"])
	cfg.set_value("skills", "unlocked", skills["unlocked"])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Couldn't save the game (error %d)" % err)


## Loads the save file if there is one. Returns false if there isn't.
func load_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	results = cfg.get_value("progress", "results", {})
	SkillManager.from_save({
		"points": cfg.get_value("skills", "points", 0),
		"unlocked": cfg.get_value("skills", "unlocked", []),
	})
	return true


## There's a game to continue: you finished at least one level.
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) and not results.is_empty()


## The level "Continue" goes to: the one after the last you finished
## (or the last level again, if you've finished them all).
func continue_level() -> int:
	var last := 0
	for n in results:
		last = maxi(last, int(n))
	return clampi(last + 1, 1, LEVELS.size())
