# Vision & Progress — TSA Video Game Design 2027

*Last updated: November 1, 2026. Written with Claude (AI) from Nilay's design notes and requests.*

---

## 1. The vision

**The game.** A top-down pixel-art game set on a spaceship that has lost all power. You play an
astronaut who restores power room by room by **carrying a live wire** from pad to pad, racing a
5-second timer. It's an electricity puzzle game: sparks, crackling wires, lights flickering back
on. It fits the 2026-27 TSA theme: *a deep space-themed RPG where progression comes from
puzzle-solving rather than combat.*

**The core idea, in Nilay's words:** "you take the start and then pick up the wire and then take
it to the goal. There is a 5 second timer… When you unlock the goal, the door unlocks." It's
"like an electricity thing… the guy is carrying the wires."

**Level 1 is the tutorial.** It teaches the mechanic one piece at a time across four rooms:

| Room | Teaches | What happens |
| - | - | - |
| 1 | Grabbing the wire | Spawn in the bottom-left room, grab the wire at the yellow START, run it to the blue GOAL. The door opens. |
| 2 | Nodes | Start at the lightning bolt; crates block the direct path. Touch the orange heart NODE (it gives you another 5 seconds), then reach the goal. |
| 3 | Bends | The purple BEND turns the wire 90°. START → bend → node → bend → GOAL. |
| 4 | Red tiles | Red tiles are a barrier: walk on one and you get shocked and the room restarts. Go to the left node first and follow the route to the goal. |

**How it should feel and work:**
- **Free movement**: walk anywhere, as long as the wire stays a straight, tight line from the
  last pad you touched. Walls, crates and red tiles block the wire.
- **The tutorial is built into the level**, not popups: a guided instruction at the top
  ("Come here and press E!", "Run to the GOAL to wire up the ship and restore power to the
  lights and the door!") and an arrow pointing where to go. Only rooms 1-2 have it.
- **The ship is dark** until you power each room. Then the lights come back on and the
  astronaut's helmet lamp switches off.
- **The team can edit the map** in Godot's editor by painting tiles, not by changing code.
- **Text is readable**: pixel style, but clean (the m6x11 font).
- **Art**: 32x32 tiles, floors are the 4-screw plates, plus the team's astronaut sprite.

**How we work:** AI is allowed for TSA 2026-27, but the team has to *understand* everything in
the game. Every change gets explained, with "check yourself" tasks. School tiebreakers are due
late November.

---

## 2. How the design changed (and why)

| Started as | Now | Why |
| - | - | - |
| Wire locked to one straight direction after the start | Free movement; the wire is a taut line from the last pad | Felt too restrictive; free motion plays better |
| Timer started at every node | Timer starts only when you grab the wire at START; nodes refill it **and pause it** while you stand on them | Midway nodes shouldn't punish you for stopping to think |
| Small node hitbox | Node touch radius 22 px (bigger) | Nodes were hard to hit |
| Bend = sling around a pole, direction from your approach | Bend stops you, shows **two arrows**, you press one and get flung 90° (timer paused while choosing) | The automatic fling was hard to control ("option B") |
| Map written as text in code | Map **painted** on a Godot TileMapLayer; walls/floors build themselves live | Teammates can edit levels |
| Hover/holo hint bubbles | **Guided tutorial**: one instruction at a time + arrow | Bubbles covered the pads; a guided flow fits a tutorial better |
| Fully lit rooms | Dark ship, red emergency lights; power restores the lights | Matches "a ship with no electricity" |
| New v2 astronaut sprite | **Original sprite restored**; v2 kept as a swappable option | Team preferred the original |

---

## 3. What's built

### Gameplay
- Wire carrying with taut-wire line-of-sight, 5 s timer, node refill and pause, bend arrow choice
  and fling, goals that power rooms and open doors, red tiles that shock (with or without the
  wire), timer-out wire snap, **R** to restart a room, respawn at the room's START.
- Level 1: all 4 rooms, an exit corridor and a "Level complete" screen.
- Every room was checked with a solver: one intended route, with at least 1.7 s to spare per
  5-second segment, and no shortcuts.

### Level editing
- Paint the map on the `Layout` layer (tiles: floor, wall, start, goal, node, bend, red, red-off,
  crate, door, spawn, exit). Rooms, doors, wall panels, roof edges and floor variety all build
  automatically. The Output panel warns about mistakes (e.g. a room with no START).

### Look & feel
- Art from the team's sheets, cleaned up: wall panels, 4-screw floor plates, 8 puzzle-tile icons,
  and the astronaut (idle, walk down/left/right, carrying, shocked, burnt).
- Live wire with current pulses and sparks; it flickers hot when time runs low.
- Floor conduits from each goal to its door that light up when powered.
- Pads glow and pulse; red tiles crackle; doors flicker open.
- **Lighting**: dark-blue ship, pulsing red emergency light per room, small coloured light per
  pad, helmet lamp (only in unpowered rooms), yellow glow from the wire in your hands, ceiling
  lights flickering on when a room powers up.
- 10 sound effects (grab, hum, node zap, bend, shock, snap, power-up, door, complete, tick),
  generated in code.
- HUD: 5-second timer bar, room-name toasts, white flash and screen shake on shock, fades,
  m6x11 font.

### Tutorial (rooms 1-2)
7 steps: grab the wire → run to the goal → go through the door → grab again → touch the node →
reach the goal → on to the next room. There's an arrow on screen, or at the screen edge if the
target is off-screen. Moving yellow chevrons on the floor show the route. If you fail, the
tutorial rewinds to the start of that room. Steps are markers in the scene, editable in the
Inspector.

### Project setup
- `CLAUDE.md`: notes Claude Code reads automatically.
- `tools/`: Python helpers (level solver, map/lighting previews, sound and sprite generators).

### Timeline
- **Oct 8-10**: project created; early prototype (placeholder player, two electric boxes).
- **Oct 26**: Level 1 built (art, sounds, rules, 4 rooms), redesigned for free movement, the
  paintable map editor, m6x11 font, bend option B, hint bubbles and floor chevrons.
- **Nov 1**:
  - red-tile fix and floor chevron colour fix
  - dark-ship lighting
  - guided tutorial replacing the bubbles
  - helmet lamp off after power-up
  - original sprite restored (v2 kept separately)
  - Claude Code handoff (`CLAUDE.md`, `tools/`, this document)

---

## 4. What's verified — and what isn't

- Verified: every room's routes (solver); scripts checked against each other; the generators
  recreate the current sounds and sprite exactly; lighting checked in a mock-up render.
- **Not yet verified in Godot by the team after the Nov 1 changes**: the guided tutorial, the
  lighting, the red-tile fix and the lamp. Play through and report any red errors in the
  Output panel.

**Playtest checklist**
1. Room 1: the arrow points at START; press E; follow the chevrons; the lights come on, the lamp
   fades, the next instruction points at the door.
2. Let the timer run out: the wire snaps and the room restarts, and the tutorial rewinds.
3. Room 2: the node refills and pauses the timer; a crate blocks the direct line.
4. Room 3: both bends show arrows and fling correctly.
5. Room 4: step on red *while carrying the wire* and get shocked; then finish the level.

---

## 5. What's next

**Required for TSA (January, per the Washington TSA event page — check your own state's guide):**
1. **RPG elements.** The theme requires core RPG elements; none exist yet. Ideas to discuss:
   story or dialogue (e.g. the ship's AI guiding you), ship systems or the astronaut that upgrade
   as rooms are restored (longer timer, more wire), collectible parts, a map or log of
   restored rooms.
2. **Levels 2 and 3.** January needs at least 2 of 3 levels, with Level 1 well developed; judges
   must be able to finish Level 1 and get into Level 2. Not built: the level-to-level
   transition, and new mechanics like red-off tiles (already in the tile set).
3. **Web export.** Judges play from a link (if they can't open it, the team is disqualified).
   Browser builds use Godot's Compatibility renderer and the project is set to Forward+, so test a
   web export early, especially the lighting.
4. **Portfolio** (30 points): game directions and controls, work log, storyboard, plus AI-use
   documentation. This file is a start on the work log.
5. Get the official rubric from the advisor and save it as `docs/TSA_event_guide.pdf`.

**Cleanup:** delete `Scripts/hint_sign.gd` and `Scenes/hint_sign.tscn` (unused). The old prototype
(`main.tscn`, `electric_box.*`) can go once nobody needs it.

---

## 6. AI-use record (for the TSA portfolio)

Tool: Claude (Anthropic), in the Claude app; later Claude Code.
- **Code**: level system, player, wire, puzzle tiles, HUD, tutorial, lighting, floor guides —
  written by Claude to the team's design, then explained to the team.
- **Art**: the team's sprite sheets cleaned up and cut to 32x32 by Claude's scripts; the v2
  astronaut (not in use) was generated in code.
- **Sound**: all 10 effects synthesized in code by Claude (sine waves, noise, envelopes), with no
  outside sources. Script: `tools/sfx.py`.
- **Level design**: the room layouts follow the team's hand-drawn map; Claude adjusted Room 4 to
  remove shortcuts and verified every room with a solver (`tools/solver2.py`).
- **Design decisions** (rules, tutorial wording, look and feel) came from the team.
