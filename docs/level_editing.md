# Building and testing levels yourself (in Godot)

Everything in a level can be changed in the Godot editor, without touching code:
the map, what PIP says and when, the tutorial, the yellow floor arrows, where
rogue PIP docks in Level 3, PIP's rule lines and the popup texts. Then you can
test it straight away from any room with **F6**.

Open a level: `Levels/level_1.tscn`, `level_2.tscn` or `level_3.tscn`.

**A new level:** duplicate a level in the FileSystem panel (right click > Duplicate) and call it
the next number, `level_4.tscn`, in the same `Levels` folder. Set its **Level Number** to 4 in
the Inspector. That's all: the game finds every `level_<number>.tscn` in `Levels` by itself,
so the level select, the dev menu and Continue show it straight away. The numbers must go 1, 2,
3, 4 with none missing (a file after a gap is left out, and the Output panel says why).

> If Godot says files changed on disk, always pick **Reload**, never Resave.

---

## 1. The map

Select the **Layout** node. The TileMap panel opens at the bottom. Pick a tile and
paint. What you paint is what you get, like a game's level editor: the finished
look (walls, floor plates, hull) redraws by itself, and every pad, door, battery
and pickup comes alive right where you put it. Pads glow, batteries bob, red floor
sparks, blinking grates run their wave, pillars stand on the poles. That's the
**Live Preview** switch on the level node (on by default). It uses the game's own
code, so it looks the same as when you play.

Tiles the game never draws get a small marker instead: SPAWN, EXIT, the TEST START
flag, and a few stars on open space. Tick **Show Layout In Editor** to also see the
flat palette icons on top (handy to check which tile is which). You can paint on the
Layout either way.

| Tile | Map char | What it does |
| - | - | - |
| floor / wall | `.` / `#` | walls (and doors, barriers) split the map into rooms |
| start | `S` | yellow pad: press E here to grab the wire. **One per room.** |
| goal | `G` | blue pad: touch it with the wire to power the room |
| node | `N` | orange: stand on it and press E (or click) to wrap the wire round it; adds Node Time (up to the START time) and holds the clock for Node Hold seconds |
| pole | `B` | support pillar (steel column with a purple ring): solid; the wire wraps round it when you walk past it. The column covers the tile above it, so don't put anything there players must see |
| discharge | `X` | red: zaps you, and the wire can't cross it |
| blinker | `x` | blinking grate: zaps only while lit |
| crate | `C` | blocks you and the wire |
| door | `D` | opens when the room before it is powered |
| barrier | `=` | cargo that sinks when a room next to it is powered (makes multistage rooms) |
| cell | `*` | battery: grab it while holding the wire for +2 s |
| spawn / exit | `P` / `E` | where you start / walking onto it finishes the level |
| hull / space / airlock | `,` / `~` / `A` | spacewalk tiles (Level 2) |
| core | `@` | Level 3: power the room by looping the wire all the way round it |
| fuse | `f` | pickup: walk over it. The console counts your fuses (no level uses fuses right now) |
| fuse door | `F` | amber door: walk into it with a fuse and it opens (uses the fuse) |
| main door | `M` | red lamp door: opens when every power link pointing at it has lit its lamp. One link = one lamp, so it also works as a small "powered from over there" door |
| socket | `o` | where the cable clamp can be set down (E next to it). In a socket the clamp works like a pole |
| clamp | `k` | the cable clamp lying on the floor: walk over it to pick it up (one per level) |
| movable crate | `c` | steel crate with yellow stripes: walk into it and it rolls one tile. Blocks you and the wire. Rolled onto a red tile, it shorts it out: that tile becomes safe for you and the wire |
| test start | (none) | green flag (the last tile in the palette): F6 starts you here, see section 7. In the game it's plain floor |

### The team's art tiles

The palette has more than one sheet now. In the TileMap panel, the list on the
left picks which one you paint from:

| Sheet | What's on it | Its rule (kind) |
| - | - | - |
| layout_tiles | the plain palette above | see the table |
| ground | floor plates in different sizes | floor: walk on it |
| wall | the front wall faces (power strip, windows, computers), 3 tiles tall | wall: solid |
| wall_strip | the power strip front wall without the lightning bolt, 6 x 3 | wall: solid |
| wall_sides | 47 wall pieces: every way a wall can touch floor (sides, corners, thin walls, solid dark) | wall: solid |
| objects | start, goal and extra time blocks, a grey block, a small and a big crate | start / goal / node; grey block and big crate = fixed cargo (solid); small crate = movable crate |
| start_anim, goal_anim, node_anim | one animated tile each: paint one square and the whole animation plays | start / goal / node |

They're shown exactly as you paint them, in the editor and in the game. Their
rules come from their kind, the same as the plain palette: a start block works
like a START pad (you stand on it), the big crate blocks you and the wire, the
small crate rolls when you walk into it. Paint all four quarters of the big crate.

How to lay out a room with them:
- Front wall: paint one of the wall faces along the top of the room (all 3
  rows). Drag across a whole panel in the palette to paint it in one click.
- Every other wall: a piece from `wall_sides`. Each piece has its light edge
  on the sides where floor touches it; the rest is the dark top of the wall. Pick
  the piece whose edge matches the floor next to it (the solid dark one for
  walls with no floor next to them, like above a front wall).
- Quicker for big changes: paint walls roughly (any wall piece, or the plain
  grey wall), then run `python3 tools/retile_walls.py Levels/level_N.tscn`
  with Godot closed. It repaints every wall of that level: front panels where
  a wall stands 3 tall above floor, the right piece everywhere else.
- Doors, spawn, exit and the other tiles still come from the plain palette.

To change a tile's rule, open `Assets/images/tiles/layout_tileset.tres`, pick the
sheet, select the tile and change **Custom Data > kind** (for example, give the
grey block a job). To change an animation's speed, select its tile and change
**Animation > Speed**.

Rules the game checks:
- Every room needs exactly **one START** and **one GOAL or CORE**, except a **hall**: a
  room with neither (a corridor, a hub). Halls never lock anything: their doors are open
  from the start.

**Room labels.** While you paint, every room shows a small label in the top left corner:
its number (the order you walk to it from the spawn), its name, its START time and how
many movable crates it has. Anything missing shows in red ("needs a START pad", "needs a
GOAL"). Paint a new room and the Room Titles and Room Wire Time lists (level node,
Inspector) get a new entry by themselves: rename "ROOM n" to what it should be called.
Don't want the labels? Untick **Show Room Info** on the level node.

## 1a. Movable crates

Paint them with the movable crate tile (`c`, the steel crate with yellow stripes). In the game:
- Walk straight into a crate and keep walking: after a moment it rolls one tile.
- It only rolls onto floor or a red tile, never onto a pad, a battery, a socket, an item,
  another crate, or across the wire you're carrying.
- Onto a **live red tile** it shorts it out and sinks: that tile is now safe for you, and
  the wire can cross it. That's the best trick: a red strip that blocks the wire, and
  crates to open the one tile the wire needs (see the Cable Store in Level 1).
- **R** puts the crates of the room back where they started (not once the room has
  power). In a hall, R puts its crates back and you at the door you came in by.

Good crate puzzles: few crates (1 to 3), and a clear job for them (open a line for the
wire, short out the right red tile, clear the way to a node). Keep the doors of a room
clear: a crate pushed in front of a door you need is a dead end (R fixes it, but it
isn't fun). The solver tries the crates in every place you can push them, so it can
take a minute on a room with crates.

## 1b. Dungeon parts: halls, fuses, the main door, the clamp, power links

Level 1 is built like a small dungeon: the Reactor Hall is a hub with three wings you
can do in different orders, and the main door only opens when all three are powered.
Two chains, in any order:
- the **reactor ring** in the hub (roll a crate onto it) holds the **cable clamp**, which
  **Coolant Pumps** needs;
- the **Cable Store** is open, and powering it lights the one lamp of the red door to the
  **Service Duct**, the way to **Reactor Access**.
Keep it that way when you change things: every item is found in one place and used in
another, and every locked door shows what opens it (lamps).
- **Power links** are the switches. Add a **PowerLink** (right-click Links > Add Child
  Node > PowerLink), drag it onto a room's goal, give it Marker2D children and drag
  each onto a tile it should change. **Action**: OPEN or CLOSE a door or barrier,
  RED_OFF or RED_ON a red floor (the whole patch touching the marker), or UNLOCK
  (lights one lamp of a main door). **Show Camera** glides the camera over so the
  player sees what changed. The editor draws a dotted line from the link to each target.
- A **main door** has one lamp per UNLOCK link pointing at it. Walk into a shut one and
  the popup counts its lamps (**Popup Lamps**).
- **Fuses** open fuse doors. Make sure there are never more fuse doors on the way than
  fuses the player can reach (or they get stuck).
- The **clamp**: put a few **sockets** in a room, only one in the right place. That's a
  "think first" puzzle: the solver says "needs the clamp" when there's no route without it.
  Walk up to a socket without the clamp and PIP says where to look: write that in **Pip
  Socket Empty** (level node, Inspector > PIP's dungeon lines).
- **Walkthrough** (level node, Inspector > Level): the room numbers in the order PIP's
  autopilot does them (judge mode). Halls are skipped.
- Press **M** in the game for the deck map.
- Rooms are numbered in the order you walk to them from the spawn. That number is
  what "room" means everywhere else (room names, PIP's beats, `malfunction_room`...).

## 2. What PIP says, and when (story beats)

Open the **Story** node. Each child is a **StoryBeat**: one thing PIP says. In the
editor each one shows as a speech bubble with its trigger and first line.

- **Add one:** select a beat, press **Ctrl+D**, drag the copy into the right room.
  The room it sits in matters: "ENTER_ROOM" means "when you enter THIS room".
- **Trigger:** when it plays (it plays once):

| Trigger | When |
| - | - |
| LEVEL_START | as soon as the level starts (any room) |
| ENTER_ROOM | you walk into the beat's room |
| SOLVE_ROOM | you power the beat's room |
| REACH_HERE | you walk close to the marker |
| GRAB_WIRE | you grab the wire in the beat's room |
| FAIL_IN_ROOM | you fail in the beat's room for the first time |
| AIRLOCK | the airlock in the beat's room starts |
| ALL_POWERED | after the lights-on cutscene (any room) |
| FIRST_DRIFT | you first drift across space in the beat's room |
| TOUCH_EMPTY_CELL | you touch a battery without the wire (any room) |
| SHIP_LIGHTS_UP | during the lights-on cutscene (any room) |

- **Speaker:** `PIP` (green), `P!P` (the malfunctioning PIP: red, angry face), or any name.
- **Lines:** one entry = one speech bubble. The console fits two rows (about 70 letters,
  counting "PIP> "). A longer line gets split in two, and people miss half of it, so the
  editor writes **TOO LONG** in red under the beat: shorten it.
  `{cells}`, `{o2_bonus}` and `{o2_per_cell}` become real numbers.
- **Pause Game:** freeze the player until they press E through the lines. (Never
  happens while they're holding the wire.)
- **Point Here:** PIP's blue arrow points at the marker while the lines play. To point
  somewhere ELSE, right-click the beat > **Add Child Node > Marker2D** and drag that
  child onto the thing. The editor draws a dotted line from the beat to it.

## 3. PIP's rule lines and the popups

Some lines aren't story, they come from the rules (the first time the wire stops
you, "Stuck? Press H", oxygen low...). Select the **level node** (Level1, Level2...)
and open the Inspector groups:
- **PIP's rule lines**: change the text. Leave one empty and PIP stays quiet there.
- **Popup texts**: the short messages at the top ("POWER ON", "ZAP!"...).

The same level node also has **Level** (name, results message), **Rules**,
**Lighting**, **Blinking grates**, **Spacewalk** (oxygen) and **Room names**.

**Rules** is where the difficulty lives:
- **Wire Time**: seconds from the START. **Room Wire Time**: one number per room (in
  walking order, like Room Names) to give a room its own START time; 0 = use Wire Time.
- **Node Time**: seconds a node adds. The timer never goes above the START time (Wire Time): a node or battery only tops it back up.
- **Node Hold**: how long standing on a node holds the clock.
- **Cell Bonus**: seconds a battery adds.
After changing any of them (or the map), check every room still works:
`python tools/solver2.py Levels/level_2.tscn`. Look at "most forgiving route: lowest
timer": the least time a perfect player has left. About 1 s is hard, 2 s+ is easy.

## 4. The tutorial

Open the **Tutorial** node. Each **TutorialStep** is one instruction. They run top to
bottom in the scene tree (drag to reorder). A step shows only once you're in its
room, and its position is where the yellow arrow points.
- **Text**: the instruction.
- **Advance When**: what moves it on (grab the wire, touch a node, power the room,
  reach the marker...).

## 5. The yellow floor arrows (chevrons)

Open the **Hints** node. Each child is a **FloorGuide** (a Line2D).
- Select one. Drag its points in the 2D view; the toolbar above the view has tools
  to add and delete points. (Or edit **Points** in the Inspector.) The FIRST point
  decides which room it belongs to.
- **Hint Only** ticked: hidden until the player presses **H** (PIP offers it after
  two fails). Unticked: always visible, like a tutorial path.
- **New one:** right-click Hints > **Instantiate Child Scene** > `Scenes/floor_guide.tscn`.

## 6. Rogue PIP (Level 3)

You don't place PIP himself. **Paint CORE tiles** (`@`):
- The core in room number `malfunction_room` is the sync pylon. Powering it turns PIP.
- The cores in the rooms after it are his sockets, in walking order.

The editor shows a preview: "SYNC PYLON" on the pylon, and a PIP on each socket with
its number, his shutdown time and a dotted flight path. On the **RoguePip** node:
- **Shutdown Seconds**: one number per socket. How long his red lights take to fill.
  Check the solver's "s in all" for that stage and give players extra on top.
- **Lines**: what he says when the surge hits, right after turning, when he escapes
  each socket, after the reboot, and when he cuts your wire.

## 6b. The RPG side: batteries and the wire upgrade

- Every **cell** tile you paint is a battery: worth 0.5 s on the wire when it's charged
  (level node, Rules > **Cell Bonus**), and one battery to spend once its room has power.
- The upgrade's numbers are in `Scripts/game_state.gd`: **UPGRADE_COSTS** (3, 5, 7: add a
  number for a fourth upgrade) and **UPGRADE_STEP** (1 s each).
- The START time is the level's **Wire Time** (Rules group, 3 s), or a room's own entry in
  **Room Wire Time**. That's also the most the timer holds. Each upgrade adds 1 s to it.
- The upgrade screen shows after a room you power, when the player can afford the next
  upgrade. Its first PIP line is the level's
  **Pip Upgrade** (Inspector, PIP's rule lines).
- The save file is `user://save.cfg`. To start clean while testing, press **N** on the title
  screen (or delete it: Project > Open User Data Folder).

## 7. Test it straight away: the test start tile + F6

1. Paint the **test start** tile (the green flag, last in the palette) where you
   want to start. It shows as a green flag with "TEST START (F6)".
2. Press **F6** (Run Current Scene).

You start on the flag. Every room before it already counts as powered: doors open,
cargo sunk, PIP already turned and on the right socket. Paint only one: with two,
both flags turn red and the game uses the first one it finds. Erase it (or leave it:
it's plain floor in the real game) when you're done.

**The old way still works:** every level also has a **TestStart** node. Drag it
into a room, tick **Active**, press F6. A painted test start tile wins over it.

With the node you start on the flag. Every room before it already counts as powered: doors open,
cargo sunk, PIP already turned and on the right socket. Options:
- **Skip Earlier Rooms**: untick to start there with nothing powered.
- **Play Intro**: tick to hear PIP's LEVEL_START lines anyway.

It only works with F6 from the editor. **F5** (the whole game from the title) and
the exported web game ignore it, so a forgotten flag can't break the real game.

**Quicker: the dev menu.** While the game runs from the editor (F5 or F6), press
**`** (the key left of 1) or **F1** at any time, even on the title screen. It lists
every room of every level: pick one and that level loads with you on the room's
START pad and every room before it powered (the same as a TestStart flag, nothing
to drag). Room 1 is the normal start with PIP's intro. **Esc** or **`** closes it.
New rooms show up in the list by themselves. Exported and web builds don't have it.

At the top of the dev menu is **NODE REST: OFF/ON**, a rule we're trying out. When it's
on: while the wire is latched on a node (the node is the last thing it touched) and you
stay close to it (about a tile and a half, **Node Rest Radius** in Rules), the timer
waits. Time to look round the room before you go. Flip it and keep playing, it works
straight away. Every run starts with it off. If the team likes it, it can become a real rule.

## 8. Check the puzzle with the solver

After changing a room's map:

```
python tools/map_from_scene.py Levels/level_1.tscn tools/out/level1.txt
python tools/solver2.py tools/out/level1.txt
```

It lists every route that works in time, and whether each battery can be reached.
"0 solutions" = nobody can solve that room. With movable crates it also says how many
pushes the room needs at least. On a Mac type `python3` instead of `python`. More in
`tools/README.md`.

**Then update PIP's autopilot routes** (judge mode walks these), or he powers the
changed room without walking it:

```
python tools/solver2.py Levels/level_1.tscn --paths Data/routes/level_1.json --margin 3
```

## 9. Judge mode (for the TSA judges)

On the title screen, top left: **JUDGE MODE**. When it's on:
- LEVEL 1 / 2 / 3 buttons appear, so a judge can jump straight to any level.
- In a level, **R** makes PIP take over: he walks to the next room, sets the clamp
  down if it's needed, grabs the wire and walks the route (no timer, no zaps). Then
  you get the controls back. R again for the next room. After two fails PIP says
  "Press R and I'll walk you through it" instead of offering a hint.
- If the Output panel says **"Autopilot couldn't walk room N"**, PIP gave up and just
  powered the room. Almost always the map changed: make the routes again (section 8).
- Blinking grates: PIP waits at the edge until he can cross while every grate under him
  is dark, then walks in the gap behind the wave, like a player should. You don't have to
  do anything for this in a new room with grates.

## Common mistakes

- **A beat never plays:** its marker is on a wall (no room) or in the wrong room. Move it onto floor.
- **The tutorial gets stuck:** a step's Advance When can't happen in its room.
- **A line is cut off:** it's too long. Two lines in the console is about 72 letters.
- **Your change vanished:** Godot saved its old copy over it. Reload, never Resave.
