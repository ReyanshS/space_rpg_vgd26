# Vision & Progress — TSA Video Game Design 2027

*Last updated: November 1, 2026. Written with Claude (AI) from Nilay's design notes and requests.*

---

## 1. The vision

**The game.** A top-down pixel-art game set on a spaceship that has lost all power. You play an
astronaut who restores power room by room by **carrying a live wire** from pad to pad, racing a
short timer. It's an electricity puzzle game: sparks, crackling wires, lights flickering back
on. It fits the 2026-27 TSA theme: *a deep space-themed RPG where progression comes from
puzzle-solving rather than combat.* Title: **STAR CIRCUIT** (the team's choice).

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
| 2 | Nodes | Start at the lightning bolt; crates block the direct path. Touch the orange heart NODE (it gives you another 4 seconds), then reach the goal. |
| 3 | Poles | Walk round the purple POLES so the wire wraps round them. START → pole → node → pole → GOAL. |
| 4 | Red tiles | Red tiles are a barrier: walk on one and you get shocked and the room restarts. Go to the left node first and follow the route to the goal. |

**Level 2 — Main Deck (the spacewalk).**

| Area | Teaches | What happens |
| - | - | - |
| The Bridge | Review | Node + pole + red tiles together. Powering it triggers PIP's diagnostic. |
| Airlock | Story moment | Stand on the pad: the door seals, the air hisses out, the outer door opens. |
| Hull Section A | **Drifting** | No floor between hull plates: walk off an edge and you drift straight across to the next plate. Two drifts reach the relay. |
| Solar Array | Wire angles | Floating debris blocks the wire. Hook the wire round a node first so it lines up with the gap. |
| Main Coupling | Everything | Drift up, wrap the wire round the pole (the right way!), drift across to the node, hop the stepping stone, drift down to the coupling. Then back inside through the hatch. |

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
| Bend: stop, pick an arrow, get flung (Nov 2026) | **Pole**: a post the wire wraps round as you walk past; nodes add time instead of a full refill, a max on the timer, nodes hold the clock only briefly; per-room START times | The team said it was too easy; poles feel like real rope, and the timer rules give real levers to tune with the solver |
| Hover/holo hint bubbles | **Guided tutorial**: one instruction at a time + arrow | Bubbles covered the pads; a guided flow fits a tutorial better |
| Fully lit rooms | Dark ship, red emergency lights; power restores the lights | Matches "a ship with no electricity" |
| New v2 astronaut sprite | **Original sprite restored**; v2 kept as a swappable option | Team preferred the original |
| Level 1 ended with "press R to play again" | Results screen with stars, then **on to Level 2** | Judges must get from Level 1 into Level 2; stars make finishing feel rewarding |
| No story or RPG elements | PIP (ship AI) dialogue, power cells that upgrade your suit's oxygen, a **skill tree** paid for with points from finishing levels | The theme requires RPG elements; story ties the levels together |
| Spacewalk = "fix something outside" | Zero-G **drift** across gaps + oxygen meter, rewiring three relays | A new mechanic that still uses the wire rules, so it's a puzzle, not a reflex test |
| Stuck players had no help | **H** shows the route in the harder rooms; PIP offers it after 2 fails | Judges must be able to finish; nobody should quit on one room |

---

## 3. What's built

### Gameplay
- Wire carrying with taut-wire line-of-sight, per-room START time, nodes that add time (capped)
  and briefly hold the clock, poles the wire wraps round, goals that power rooms and open doors,
  red tiles that shock (with or without the
  wire), timer-out wire snap, **R** to restart a room, respawn at the room's START.
- **Power cells**: charge them by touching them with the live wire (also mid-drift);
  kept once the room is powered, returned if you fail. 9 in Level 1, 10 in Level 2 — some on the
  route, some needing a small detour, a few only reachable by a sharp player. Drawn as a battery
  with a lightning bolt. PIP points at the first one and explains it at the start of Level 1; the
  first charge, keep and loss each get a one-time message; the results screen shows the suit upgrade.
- **Lights-on cutscene** when every room in a level has power: film bars slide in and the camera
  glides back through every room as it lights up at full power, while PIP talks over it.
- **Spacewalk**: hull plates and open space, drifting, floating debris, sparking hull tiles,
  gangways (catwalks that slide out when a section is powered), oxygen meter with refills,
  the airlock sequence, blinking hull beacons when a section is powered.
- **Results**: time, cells, retries and 1-3 stars per level; saved in `Game` between levels.
- **Hints** (H) for Level 1 rooms 3-4 and Level 2's bridge, solar array and main coupling.
- **Title screen** and **pause menu** (Esc) with every control listed.
- Level 1 (4 rooms) and Level 2 (bridge, airlock, 3 hull sections, exit hatch).

### Level editing
- Paint the map on the `Layout` layer (tiles: floor, wall, start, goal, node, pole, red, red-off,
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
- Sound effects generated in code; music is the team's own five tracks (title, ship, spacewalk,
  boss, ending), volumes in `Game.MUSIC`.
- HUD: timer bar, room-name toasts, flash and shake on shock, fades, power meter, cell counter,
  oxygen gauge, PIP's speech box with an animated face (it picks the top or bottom of the screen
  once and turns see-through when you walk behind it), results screen with stars, film bars for
  cutscenes.

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
  - after the team's first playtest: lights-on cutscene, a speech box that no longer jumps around,
    clearer power cells (battery art, PIP's explanation, suit-upgrade line on the results screen)
- **Nov 2-6**: team map touch-ups (extra red tiles and crates in both levels, a new node on the
  bridge); the game is renamed **STAR CIRCUIT**.
- **Nov 8**, after the team's second round of feedback:
  - failing no longer sends you back: you stay where you fell and walk back (R still jumps back)
  - multistage puzzles instead of separate rooms: a new BARRIER tile (cargo on a lift) sinks into
    the floor when its stage is powered; Level 1 is now one open deck in 4 stages, and Level 2's
    hull sections share one open camera space
  - new UI look ("less AI"): riveted metal frames with green terminal screens, LED meters
- **Nov 8**: teammate redesigned Level 2's Main Coupling (a bend floating in space).
- **Nov 9**, third round of feedback:
  - doors are back between Level 1's four rooms (the team's layout)
  - new **Generator Room** at the end of Level 1: a real multistage room. Powering stage A sinks a
    whole column of cargo, and stage B can only be solved by wrapping the wire round stage A's
    node through that gap. Stage C crosses **blinking grates** (a light wave you walk behind)
  - barriers now move in groups; later stages can reuse earlier stages' nodes and bends
  - the team's STAR CIRCUIT logo on the title screen; PIP and all game text rewritten to sound
    natural (no dashes, fewer exclamation marks)
- **Nov 9**, fourth round ("PIP covers the game, bends get you stuck, it isn't fun yet"):
  - the HUD is now a console along the bottom; the room is framed above it, so nothing covers play.
    The wire timer floats above the astronaut's head
  - bends show a dotted preview of where each way throws you, and **E reels you back** to the
    last pad, so a wrong turn costs a second instead of a whole retry
  - power cells are full batteries: grabbing one adds 2 s to the wire right away
  - pads count as touched where the astronaut LOOKS like he's standing (fixes missed nodes/bends)

---

- **Nov 20**: the team found it too easy. Bends became **poles** the wire wraps round; nodes add
  time instead of refilling, the timer has a max, nodes only hold the clock briefly, and each
  room can have its own START time. Level 1 stays a gentle tutorial for its first 3 rooms; Levels
  2 and 3 are hard but fair (about 1 s to spare on a perfect route; PIP's meter is tighter).
  Level 1 room 4 and Level 2 room 5 were reworked for poles. Skills got stronger and new kinds
  (node time, timer max, node hold). Menus got real buttons and keycap hints. Quitting
  mid-level no longer throws errors.

## 4. What's verified — and what isn't

- **Nov 20 (latest):** the solver models poles and the new timer exactly like the game, and a bot
  walked the solver's route in every one of the 15 rooms in the real game: all solved, with the
  lowest timer within about 0.1 s of the solver's number. Bots also quit to the title at 54
  moments per level (3 ways), mashed random keys for 30 sessions, and started from TestStart in
  every room: no errors. Older notes below are from before the poles.

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
1. Title → Level 1: PIP's intro, then he points at the first power cell and explains it.
2. Charge cells with the wire; fail once on purpose: the cells come back and you stay where you fell.
3. Power stage 1: the cargo row sinks into the floor. Stages 3 / 4: PIP's warnings; fail twice in
   a stage: PIP offers a hint; press H.
4. Power the last stage: the lights-on cutscene. Finish Level 1: stars, then E → Level 2.
5. Bridge → airlock → Section A: drift across, watch the oxygen bar, try walking off where there's
   no plate (you should stay put).
6. Finish Level 2 and check the results screen, then E → Level 3.
7. Level 3: loop the wire round the pylon (watch the yellow ring). PIP malfunctions: red alert.
   In his chamber, grab the wire and stand still on a node: his red meter fills and he cuts it.
   Then beat all three phases; after the last one he reboots and the lights-on cutscene plays.

**Level 3 (The Core), added Nov 2026.** The team's idea from Discord: PIP malfunctions and you
have to surround him with wires fast enough, or he destroys them; doing it brings him back. How it
was built: a new `core` tile; a room with a core is powered by wrapping the wire a full turn round
it (the angles add up to 360 degrees). Room 1 teaches that on a harmless pylon; powering it
overloads PIP. Then three stages, one socket each, with a shutdown meter that cuts your wire if
you're too slow (18 / 15 / 19 s): an open ring, a socket behind cargo (with a bend to whip round),
and a socket between blinking grates. A bot played it start to finish (about 75 s, no retries)
and checked that the meter really cuts the wire.

---

## 5. What's next

**Required for TSA:**
1. **Playtest Level 3 with real people.** Is the loop rule clear from the pylon room? Are PIP's
   shutdown times fair (`shutdown_seconds` on the RoguePip node)? It's the ending, so it should feel
   tense but beatable in a few tries.
2. **Web export.** Judges play from a link (if they can't open it, the entry isn't judged).
   Browser builds use Godot's Compatibility renderer and the project is set to Forward+, so test a
   web export early, especially the lighting and the music loops.
3. **Portfolio** (50 points in the preliminary round): title page; purpose, audience, how to play +
   controls (draft in `docs/how_to_play.md`); hand-drawn storyboard; copyright checklist;
   Resources & AI Reflection. The demo video (< 5 min) needs a tutorial, a level played, and the
   code/engine shown.
4. Team decisions: PIP's name and personality, the difficulty of Level 2. Level 2's bridge is
   still a single stage - a second stage behind a barrier would make it feel like Level 1.

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
- **Sound effects**: synthesized in code by Claude (sine waves, noise, envelopes), with no outside
  sources. Scripts: `tools/sfx.py`, `tools/sfx_pip.py`.
- **Music**: the team's own tracks (replaced Claude's synthesized loops in Nov 2026). Claude only
  hooked them into the game.
- **Level design**: Level 1's layouts follow the team's hand-drawn map; Claude adjusted Room 4 to
  remove shortcuts, placed the power cells, and verified every room with a solver. Level 2
  (bridge + spacewalk) was designed by Claude from Nilay's request ("go out the airlock and do a
  spacewalk to fix something") and checked with the solver and automated playtests.
- **Writing**: PIP's dialogue, the title screen text and these docs were drafted by Claude.
- **Design decisions** (rules, tutorial wording, look and feel, what Level 2 should be about)
  came from the team; the spacewalk mechanics (drift, oxygen) were Claude's proposal.
- **Level 3**: the boss idea (PIP malfunctions, surround him with wire in time to bring him back)
  came from the team's Discord. Claude turned it into the loop rule, designed and solver-checked
  the rooms, wrote `rogue_pip.gd` and the dialogue, drew the core tile and made the boss sounds.
