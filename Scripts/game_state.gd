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
#
# It also holds the RPG side of the game: your XP, your level (LV) and the suit
# upgrades you picked. The level gives XP (level.gd _award_xp), and when you
# level up it opens the LEVEL UP screen (hud.gd pick_upgrade). Upgrades change
# the rules through the small helpers here: wire_bonus(), cell_bonus_extra(),
# walk_multiplier(), o2_bonus() and perk("boots").
# ---------------------------------------------------------------------------
extends Node

## The levels in the order you play them.
const LEVELS: Array[String] = [
	"res://Scenes/level_1.tscn",
	"res://Scenes/level_2.tscn",
	"res://Scenes/level_3.tscn",
]
const TITLE_SCENE := "res://Scenes/title.tscn"

## Extra seconds of oxygen on a spacewalk for every power cell you charged so far.
## This is the RPG "upgrade": exploring earlier levels makes later ones easier.
const O2_PER_CELL := 5.0

# ---- RPG: experience (XP), levels and suit upgrades --------------------------
# You earn XP for what you do well. Enough XP = LEVEL UP: you pick one upgrade
# for your suit, and it stays with you for the rest of the game. Change the
# numbers here to make levelling faster or slower.
const XP_ROOM := 30         ## for powering a room
const XP_CLEAN := 15        ## extra, if you powered it without failing there first
const XP_CELL := 10         ## for each battery you keep
const XP_FINISH := 50       ## for reaching the exit of a level
const XP_FIRST_LEVEL := 100 ## XP needed to go from LV 1 to LV 2...
const XP_MORE_PER_LEVEL := 60  ## ...and each level after that needs this much more

## The upgrades you can pick when you level up. "max" = how many times you can take it.
## The level reads these through the helper functions below (wire_bonus() etc.).
const UPGRADES := {
	"wire": {"name": "LONGER WIRE", "text": "+0.5 s on the wire timer", "max": 2},
	"cells": {"name": "SUPER CELLS", "text": "Batteries add 1 s more", "max": 2},
	"servos": {"name": "LEG SERVOS", "text": "Walk 10% faster", "max": 2},
	"boots": {"name": "RUBBER BOOTS", "text": "Shrug off the first zap in each room", "max": 1},
	"tank": {"name": "BIG TANK", "text": "+15 s of air on spacewalks", "max": 2},
}

var xp := 0                 # all the XP you've earned this game
var lv := 1                 # your level (shown as LV in the console)
var upgrades_waiting := 0   # level ups you haven't picked an upgrade for yet
var perks := {}             # upgrade id -> how many times you took it

# One entry per level number, e.g. results[1] = {"time": 140.2, "cells": 7, ...}
var results := {}
## True once a level was loaded BY THE GAME (title -> level, or "next level").
## Stays false when you run one level scene straight from the editor with F6:
## that's the only time a level's TestStart marker is used.
var playing_through := false
# Tips PIP already gave (so he explains something only once, even across levels)
var _tips_seen := {}


## Forget everything (the title screen calls this when you start a new game).
func new_game() -> void:
	results.clear()
	xp = 0
	lv = 1
	upgrades_waiting = 0
	perks.clear()


# ------------------------------------------------------------------ XP and levels

## XP needed to get from level `level` to the next one: 100, 160, 220, 280...
func xp_for_next(level: int) -> int:
	return XP_FIRST_LEVEL + XP_MORE_PER_LEVEL * (level - 1)


## Add XP. Returns how many times you levelled up (usually 0 or 1).
## Each level up also leaves an upgrade waiting to be picked.
func add_xp(amount: int) -> int:
	xp += amount
	var ups := 0
	while xp >= xp_total_for(lv + 1):
		lv += 1
		ups += 1
		upgrades_waiting += 1
	return ups


## Total XP you need to REACH level `level` (LV 2 = 100, LV 3 = 260, ...).
func xp_total_for(level: int) -> int:
	var total := 0
	for l in range(1, level):
		total += xp_for_next(l)
	return total


## How far you are towards the next level: 0 = just levelled up, 1 = about to.
func level_progress() -> float:
	var start := xp_total_for(lv)
	return clampf(float(xp - start) / float(xp_for_next(lv)), 0.0, 1.0)


## Up to `count` different upgrades you could still take, in a random order.
func upgrade_choices(count := 3) -> Array:
	var open: Array = []
	for id in UPGRADES:
		if perk(id) < int(UPGRADES[id]["max"]):
			open.append(id)
	open.shuffle()
	return open.slice(0, count)


func take_upgrade(id: String) -> void:
	perks[id] = perk(id) + 1
	upgrades_waiting = maxi(0, upgrades_waiting - 1)


## How many times you took upgrade `id` (0 = not at all).
func perk(id: String) -> int:
	return int(perks.get(id, 0))


## "LONGER WIRE x2, RUBBER BOOTS" - for the pause menu.
func perks_text() -> String:
	var parts: PackedStringArray = []
	for id in UPGRADES:
		var n := perk(id)
		if n > 0:
			parts.append(UPGRADES[id]["name"] + (" x%d" % n if n > 1 else ""))
	return ", ".join(parts) if not parts.is_empty() else "no upgrades yet"


# What each upgrade does - the level asks these:
func wire_bonus() -> float:        ## extra seconds on the wire timer
	return 0.5 * perk("wire")


func cell_bonus_extra() -> float:  ## extra seconds a battery adds
	return 1.0 * perk("cells")


func walk_multiplier() -> float:   ## 1.0 = normal walking speed
	return 1.0 + 0.1 * perk("servos")


## The level calls this when you finish it.
func record_level(number: int, stats: Dictionary) -> void:
	results[number] = stats


## Power cells charged in every level finished so far.
func cells_collected() -> int:
	var n := 0
	for stats in results.values():
		n += int(stats.get("cells", 0))
	return n


## Extra oxygen on spacewalks: from batteries you kept, and the BIG TANK upgrade.
func o2_bonus() -> float:
	return cells_collected() * O2_PER_CELL + 15.0 * perk("tank")


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
		playing_through = true
		get_tree().change_scene_to_file(LEVELS[number - 1])
	else:
		go_to_title()


func go_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


## Values that story text can use: write {cells}, {o2_bonus} or {o2_per_cell} inside a line.
func story_values() -> Dictionary:
	return {"cells": cells_collected(), "o2_bonus": int(o2_bonus()), "o2_per_cell": int(O2_PER_CELL)}
