# Vision & Progress — TSA Video Game Design 2027

*Last updated: November 1, 2026. Written with Claude (AI) from Nilay's design notes and requests.*

---

## 1. The vision

**The game.** A top-down pixel-art game set on a spaceship that has lost all power. You play an
astronaut who restores power room by room by **carrying a live wire** from pad to pad, racing a
5-second timer. It's an electricity puzzle game: sparks, crackling wires, lights flickering back
on. It fits the 2026-27 TSA theme: *a deep space-themed RPG where progression comes from
puzzle-solving rather than combat.* Working title: **LIVE WIRE** (easy to change on the title screen).

**The core idea, in Nilay's words:** "you take the start and then pick up the wire and then take
it to the goal. There is a 5 second timer… When you unlock the goal, the door unlocks." It's
"like an electricity thing… the guy is carrying the wires."

**The story.** A solar storm has knocked out the ship's power. PIP, the ship's small, nervous
maintenance AI, wakes you up and talks you through it. Level 1 restores the Engineering Deck. In
Level 2 you reach the Main Deck, power the bridge, and PIP's diagnostic finds the real problem: a
micrometeoroid smashed the **main power coupling on the outer hull**. You go out the airlock and
do a **spacewalk** to rewire it, then come back in through a hatch.

**Level 1 — Engineering Deck (the tutorial).** It teaches the mechanic one piece at a time:

| Room | Teaches | What happens |
| - | - | - |
| 1 | Grabbing the wire | Spawn in the bottom-left room, grab the wire at the yellow START, run it to the blue GOAL. The door opens. |
| 2 | Nodes | Start at the lightning bolt; crates block the direct path. Touch the orange heart NODE (it gives you another 5 seconds), then reach the goal. |
| 3 | Bends | The purple BEND turns the wire 90°. START → bend → node → bend → GOAL. |
| 4 | Red tiles | Red tiles are a barrier: walk on one and you get shocked and the room restarts. Go to the left node first and follow the route to the goal. |

**Level 2 — Main Deck (the spacewalk).**

| Area | Teaches | What happens |
| - | - | - |
| The Bridge | Review | Node + bend + red tiles together. Powering it triggers PIP's diagnostic. |
| Airlock | Story moment | Stand on the pad: the door seals, the air hisses out, the outer door opens. |
| Hull Section A | **Drifting** | No floor between hull plates: walk off an edge and you drift straight across to the next plate. Two drifts reach the relay. |
| Solar Array | Wire angles | Floating debris blocks the wire. Hook the wire round a node first so it lines up with the gap. |
| Main Coupling | Everything | Drift up to a bend, fling right (left = sparks!), drift across to the node, drift down to the coupling. Then back inside through the hatch. |

**How it should feel and work:**
- **Free movement**: walk anywhere, as long as the wire stays a straight, tight line from the
  last pad you touched. Walls, crates and red tiles block the wire (open space doesn't).
- **The tutorial is built into the level**, not popups: a guided instruction at the top and an
  arrow pointing where to go (Level 1 rooms 1-2, and the airlock + first drift in Level 2).
  PIP adds short lines at the bottom when something new appears.
- **The ship is dark** until you power each room. Then the lights come back on and the
  astronaut's helmet lamp switches off. Outside, the sun lights the hull.
- **Rewarding**: power cells to collect with clever routes, a ship power meter, a results screen
  with stars, and the cells carry over as extra oxygen for the spacewalk.
- **The team can edit the maps** in Godot's editor by painting tiles, not by changing code.
- **Text is readable**: pixel style, but clean (the m6x11 font).

**How we work:** AI is allowed for TSA 2026-27, but the team has to *understand* everything in
the game. Every change gets explained, with "check yourself" tasks.

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
| Level 1 ended with "press R to play again" | Results screen with stars, then **on to Level 2** | Judges must get from Level 1 into Level 2; stars make finishing feel rewarding |
| No story or RPG elements | PIP (ship AI) dialogue, power cells that upgrade your suit's oxygen | The theme requires RPG elements; story ties the levels together |
| Spacewalk = "fix something outside" | Zero-G **drift** across gaps + oxygen meter, rewiring three relays | A new mechanic that still uses the wire rules, so it's a puzzle, not a reflex test |
| Stuck players had no help | **H** shows the route in the harder rooms; PIP offers it after 2 fails | Judges must be able to finish; nobody should quit on one room |

---

## 3. What's built

### Gameplay
- Wire carrying with taut-wire line-of-sight, 5 s timer, node refill and pause, bend arrow choice
  and fling, goals that power rooms and open doors, red tiles that shock (with or without the
  wire), timer-out wire snap, **R** to restart a room, respawn at the room's START.
- **Power cells**: charge them by touching them with the live wire (also mid-fling and mid-drift);
  kept once the room is powered, returned if you fail. 9 in Level 1, 10 in Level 2 — some on the
  route, some needing a small detour, a few only reachable by a sharp player.
- **Spacewalk**: hull plates and open space, drifting, floating debris, sparking hull tiles,
  gangways (catwalks that slide out when a section is powered), oxygen meter with refills,
  the airlock sequence, blinking hull beacons when a section is powered.
- **Results**: time, cells, retries and 1-3 stars per level; saved in `Game` between levels.
- **Hints** (H) for Level 1 rooms 3-4 and Level 2's bridge, solar array and main coupling.
- **Title screen** and **pause menu** (Esc) with every control listed.
- Level 1 (4 rooms) and Level 2 (bridge, airlock, 3 hull sections, exit hatch).

### Level editing
- Paint the map on the `Layout` layer (tiles: floor, wall, start, goal, node, bend, red, red-off,
  crate, door, spawn, exit, **cell, hull, space, airlock**). Rooms, doors, wall panels, roof edges,
  floor variety and hull plates all build automatically. The Output panel warns about mistakes.
- Story lines are **StoryBeat** markers under the `Story` node (pick a trigger, type the lines).
  Hints are FloorGuides with **Hint Only** ticked.

### Look & feel
- Art from the team's sheets, cleaned up: wall panels, 4-screw floor plates, puzzle-tile icons,
  and the astronaut. New: hull plates with edges, gangway and airlock pad, a gas-giant planet, a
  nebula and a parallax starfield.
- Live wire with current pulses and sparks; it flickers hot when time runs low.
- Lighting: dark ship, emergency lights, helmet lamp, ceiling lights on power-up; sunlit hull outside.
- 20 sound effects + 2 ambient music loops (ship / space), all generated in code.
- HUD: timer bar, room-name toasts, flash and shake on shock, fades, power meter, cell counter,
  oxygen gauge, PIP's speech box with an animated face, results screen with stars.

### Tutorial
Level 1: 7 steps (rooms 1-2) with arrows and floor chevrons, rewinds on failure. PIP explains bends
(room 3) and red tiles (room 4) when you walk in. Level 2: 5 steps (airlock, grab, drift, relay, on
to the next section). Steps only appear once you're in their room.

### Timeline
- **Oct 8-10**: project created; early prototype (placeholder player, two electric boxes).
- **Oct 26**: Level 1 built (art, sounds, rules, 4 rooms), redesigned for free movement, the
  paintable map editor, m6x11 font, bend option B, hint bubbles and floor chevrons.
- **Nov 1**:
  - red-tile fix and floor chevron colour fix; dark-ship lighting; guided tutorial; helmet lamp
  - original sprite restored (v2 kept separately); Claude Code handoff (`CLAUDE.md`, `tools/`)
  - Level 1 made more rewarding: power cells, power meter, results + stars, hints, PIP's story
  - Level 2 + spacewalk: bridge, airlock, drifting, oxygen, three hull sections; title screen,
    pause menu, music, level-to-level flow

---

## 4. What's verified — and what isn't

- **Solver** (`tools/solver2.py`, now understands drifting and power cells): every room in both
  levels has one intended route. Level 1's tightest segments keep >= 1.55 s spare (unchanged);
  Level 2: Section A 1.75 s, Bridge 1.20 s, Coupling 1.64 s, Solar Array 2.27 s. Every power cell
  can be charged in time.
- **Automated playtest**: a script played both levels in the real game with simulated key presses
  (walk, grab, flings, drifts, reading PIP's lines): Level 1 with all 9 cells and 3 stars, Level 2
  with 9 of 10 cells, no errors. A second script checked failure paths: timeout, hint offer + H,
  pause menu, red-tile shock, running out of oxygen, refused drift.
- **Not yet verified by the team**: how it *feels* to a human (difficulty, readability of PIP's
  lines, music volume), the editor view of Level 2, and a **web export**.

**Playtest checklist**
1. Title → Level 1: PIP's intro, then the tutorial. Touch a cell without the wire: PIP explains.
2. Charge cells with the wire; fail once on purpose: the cells come back.
3. Room 3 / 4: PIP's warnings; fail twice in a room: PIP offers a hint; press H.
4. Finish Level 1: stars, then E → Level 2.
5. Bridge → airlock → Section A: drift across, watch the oxygen bar, try walking off where there's
   no plate (you should stay put).
6. Finish Level 2 and check the results screen.

---

## 5. What's next

**Required for TSA:**
1. **Level 3.** The official guide says judges play *to the third level*, and play time must be
   over 3 minutes (a careful first-time player should already pass that with Levels 1-2). Add it to
   `Game.LEVELS` in `game_state.gd`; until then Level 2's results screen returns to the title.
2. **Web export.** Judges play from a link (if they can't open it, the entry isn't judged).
   Browser builds use Godot's Compatibility renderer and the project is set to Forward+, so test a
   web export early, especially the lighting and the music loops.
3. **Portfolio** (50 points in the preliminary round): title page; purpose, audience, how to play +
   controls (draft in `docs/how_to_play.md`); hand-drawn storyboard; copyright checklist;
   Resources & AI Reflection. The demo video (< 5 min) needs a tutorial, a level played, and the
   code/engine shown.
4. Team decisions: the game's name, PIP's name and personality, the difficulty of Level 2.

**Cleanup:** the old prototype (`main.tscn`, `main.gd`, `electric_box.*`, `Assets/images/Player`)
can go once nobody needs it.

---

## 6. AI-use record (for the TSA portfolio)

Tool: Claude (Anthropic), in the Claude app; later Claude Code.
- **Code**: level system, player (incl. drifting), wire, puzzle tiles, HUD, tutorial, story/
  dialogue system, power cells, results and hints, game state between levels, starfield, title
  screen, lighting, floor guides — written by Claude to the team's design, then explained to the team.
- **Art**: the team's sprite sheets cleaned up and cut to 32x32 by Claude's scripts; the v2
  astronaut (not in use), the hull plates, gangway, airlock pad, planet and nebula were drawn in
  code by Claude (`tools/astro2.py`, `tools/art_space.py`).
- **Sound and music**: all effects and both music loops synthesized in code by Claude (sine waves,
  noise, envelopes), with no outside sources. Script: `tools/sfx.py`.
- **Level design**: Level 1's layouts follow the team's hand-drawn map; Claude adjusted Room 4 to
  remove shortcuts, placed the power cells, and verified every room with a solver. Level 2
  (bridge + spacewalk) was designed by Claude from Nilay's request ("go out the airlock and do a
  spacewalk to fix something") and checked with the solver and automated playtests.
- **Writing**: PIP's dialogue, the title screen text and these docs were drafted by Claude.
- **Design decisions** (rules, tutorial wording, look and feel, what Level 2 should be about)
  came from the team; the spacewalk mechanics (drift, oxygen) were Claude's proposal.
