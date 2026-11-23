# Building and testing levels yourself (in Godot)

Everything in a level can be changed in the Godot editor, without touching code:
the map, what PIP says and when, the tutorial, the yellow floor arrows, where
rogue PIP docks in Level 3, PIP's rule lines and the popup texts. Then you can
test it straight away from any room with **F6**.

Open a level: `Scenes/level_1.tscn`, `level_2.tscn` or `level_3.tscn`.

> If Godot says files changed on disk, always pick **Reload**, never Resave.

---

## 1. The map

Select the **Layout** node. The TileMap panel opens at the bottom. Pick a tile and
paint. The finished look (walls, floor plates, hull) redraws by itself while you
paint. Untick **Show Layout In Editor** on the level node to see it without the icons.

| Tile | Map char | What it does |
| - | - | - |
| floor / wall | `.` / `#` | walls (and doors, barriers) split the map into rooms |
| start | `S` | yellow pad: press E here to grab the wire. **One per room.** |
| goal | `G` | blue pad: touch it with the wire to power the room |
| node | `N` | orange: wraps the wire, adds Node Time, holds the clock for Node Hold seconds |
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
| fuse | `f` | pickup: walk over it. The console counts your fuses |
| fuse door | `F` | amber door: walk into it with a fuse and it opens (uses the fuse) |
| main door | `M` | big red door: opens when every power link pointing at it has lit its lamp |
| socket | `o` | where the cable clamp can be set down (E next to it). In a socket the clamp works like a pole |
| clamp | `k` | the cable clamp lying on the floor: walk over it to pick it up (one per level) |

Rules the game checks:
- Every room needs exactly **one START** and **one GOAL or CORE**, except a **hall**: a
  room with neither (a corridor, a hub). Halls never lock anything: their doors are open
  from the start. The Output panel warns you if a puzzle room is missing something.

## 1b. Dungeon parts: halls, fuses, the main door, the clamp, power links

Level 1 is built like a small dungeon: the Reactor Hall is a hub with three wings you
can do in different orders, and the main door only opens when all three are powered.
- **Power links** are the switches. Add a **PowerLink** (right-click Links > Add Child
  Node > PowerLink), drag it onto a room's goal, give it Marker2D children and drag
  each onto a tile it should change. **Action**: OPEN or CLOSE a door or barrier,
  RED_OFF or RED_ON a red floor (the whole patch touching the marker), or UNLOCK
  (lights one lamp of a main door). **Show Camera** glides the camera over so the
  player sees what changed. The editor draws a dotted line from the link to each target.
- A **main door** has one lamp per UNLOCK link pointing at it.
- **Fuses** open fuse doors. Make sure there are never more fuse doors on the way than
  fuses the player can reach (or they get stuck).
- The **clamp**: put a few **sockets** in a room, only one in the right place. That's a
  "think first" puzzle: the solver says "needs the clamp" when there's no route without it.
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
- **Node Time**: seconds a node adds. **Max Wire Time**: the timer never goes above this.
- **Node Hold**: how long standing on a node holds the clock.
- **Cell Bonus**: seconds a battery adds.
After changing any of them (or the map), check every room still works:
`python tools/solver2.py Scenes/level_2.tscn`. Look at "most forgiving route: lowest
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

## 6b. The RPG side: skill points and the skill tree

- **Points per level**: select the level's root node, Inspector > Level > **Skill Points**.
  You only get them the first time you finish that level.
- **Skills** are files in `Data/skills/` (one `.tres` each). Double-click one to edit it in
  the Inspector:
  - **Cost**: points to unlock it. **Amount**: how strong it is.
  - **Parent Id**: the `id` of the skill you need first (empty = top of its branch).
  - **Branch**: which column (Wire, Suit, Life Support).
  - **Short Name**: the word under its box on the tree. **Description**: shown when selected.
  - **Effect**: what it changes (`wire_time`, `cell_bonus`, `walk_speed`, `boots`, `o2`,
    `o2_per_cell`). Skills with the same effect add up.
- **New skill**: right-click a skill file > **Duplicate**, then give it a new **Id** and a
  Parent Id. The tree places it by itself. A brand new kind of effect needs code
  (search for `SkillManager.bonus`).
- Never make a puzzle that NEEDS a skill: run the solver, which uses no skills.
- The save file is `user://save.cfg`. To start clean while testing, press **N** on the title
  screen (or delete it: Project > Open User Data Folder).

## 7. Test it straight away: TestStart + F6

Every level has a **TestStart** node (a flag in the editor).
1. Drag it into the room you want to test.
2. Tick **Active**.
3. Press **F6** (Run Current Scene).

You start on the flag. Every room before it already counts as powered: doors open,
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

## 8. Check the puzzle with the solver

After changing a room's map:

```
python tools/map_from_scene.py Scenes/level_1.tscn tools/out/level1.txt
python tools/solver2.py tools/out/level1.txt
```

It lists every route that works in time, and whether each battery can be reached.
"0 solutions" = nobody can solve that room. More in `tools/README.md`.

**Then update PIP's autopilot routes** (judge mode walks these), or he powers the
changed room without walking it:

```
python tools/solver2.py Scenes/level_1.tscn --paths Data/routes/level_1.json --margin 3
```

## 9. Judge mode (for the TSA judges)

On the title screen, top left: **JUDGE MODE**. When it's on:
- LEVEL 1 / 2 / 3 buttons appear, so a judge can jump straight to any level.
- In a level, **R** makes PIP take over: he walks to the next room, sets the clamp
  down if it's needed, grabs the wire and walks the route (no timer, no zaps). Then
  you get the controls back. R again for the next room. After two fails PIP says
  "Press R and I'll walk you through it" instead of offering a hint.

## Common mistakes

- **A beat never plays:** its marker is on a wall (no room) or in the wrong room. Move it onto floor.
- **The tutorial gets stuck:** a step's Advance When can't happen in its room.
- **A line is cut off:** it's too long. Two lines in the console is about 72 letters.
- **Your change vanished:** Godot saved its old copy over it. Reload, never Resave.
