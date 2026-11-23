# solver2.py: checks that every room of a level can be solved, and how.
# Simulates the real rules (free walking, taut wire that can't cross walls/crates/red,
# the START gives TIME seconds, each node adds NODE_TIME up to MAX_TIME, the wire
# wraps round purple poles like a rope round a post, walking off a hull edge makes
# you drift across open space) on a 4 px grid and lists every route that gets
# there in time. "lowest timer" = the least time you ever have left on that route:
# that's how tight it is. It also checks every power cell: can you charge it with
# the live wire and still make it to the next pad in time?
# Use it after changing a room to make sure there's no shortcut and no impossible segment.
# The constants below must match player.gd (walk_speed, drift_speed)
# and level.gd (wire_time, node_time, max_wire_time, pad radii, CELL_RADIUS).
#     python tools/solver2.py Scenes/level_1.tscn        (easiest: reads the map AND
#                                                         the level's Rules numbers)
#     python tools/solver2.py tools/out/level1.txt --time 3.5 --node 2.5 --max 4.5
#     (a text map from map_from_scene.py, with the numbers typed in; skills not counted)
import math, heapq, sys
TILE = 32; FEET = (6, 4); WALK = 100.0; DRIFT = 150.0
TIME = 4.0; NODE_TIME = 3.0; MAX_TIME = 5.0      # level.gd defaults (--time / --node / --max)
ROOM_TIME = {}                                   # stage number -> its own START time (room_wire_time)
R = {'N': 22.0, 'G': 22.0}
CELL_R = 14.0
BODY_UP = 10.0          # pads count from the feet AND from 10 px higher (level.gd _touching)


MARGIN = 0.0   # --margin m: touch pads m px deeper than needed (routes a bot can follow safely)


def near(x, y, pc, r):
    r -= MARGIN
    return math.dist((x, y), pc) <= r or math.dist((x, y - BODY_UP), pc) <= r
STEP = 4
HANDS_UP = 9.0          # the wire ends at his hands, 9 px above his feet (player.gd hand_position)
CORE_MAX_TIME = 30.0    # core rooms: routes slower than this (seconds) aren't worth listing
WALK_SOLID = '# CDFM=~@B' # your feet can't go here (open space too: mag boots need hull)
HARD_SOLID = '# CDFM=@B'  # you can't pass here at all, not even drifting
WIRE_SOLID = '# CDFM=EX@' # the wire can't cross these (it CAN cross open space)
# F fuse door and M main door are doors; f fuse, k clamp and o socket are floor. A room with
# sockets is also tried with the clamp in each socket (it then works like a pole, B).
# 'B' is a POLE: solid for your feet, but the wire crosses it and wraps round its centre.
# '@' is a CORE (Level 3): its room is solved by wrapping the wire all the way
# round it (the wire's angle round the core adds up to a full turn) - no goal pad.
# '=' is a BARRIER that hasn't moved yet. When a stage is checked, the barriers next
# to the stages you've already powered have sunk into the floor: they become '.'.


def load(p):
    rows = open(p).read().split('\n'); w = max(len(r) for r in rows)
    return [r.ljust(w) for r in rows]


def floating_cells(g):
    """Cells with open space on both sides (left+right or above+below) float in
    space: the tile is open space with a cell on it (same rule as level.gd).
    Returns the new grid + their spots."""
    def open_at(c, r):
        return not (0 <= r < len(g) and 0 <= c < len(g[r])) or g[r][c] in '~ *'
    spots = []
    for r, row in enumerate(g):
        for c, ch in enumerate(row):
            if ch != '*': continue
            if (open_at(c - 1, r) and open_at(c + 1, r)) or (open_at(c, r - 1) and open_at(c, r + 1)):
                spots.append((c, r))
    g = [list(row) for row in g]
    for c, r in spots: g[r][c] = '~'
    return [''.join(row) for row in g], spots


class Map:
    def __init__(s, g): s.g = g; s.H = len(g); s.W = len(g[0]); s._los = {}

    def ch(s, c, r):
        if r < 0 or r >= s.H or c < 0 or c >= s.W: return ' '
        return s.g[r][c]

    def cell(s, x, y): return s.ch(int(x // TILE), int(y // TILE))

    def box_ok(s, x, y, solid=WALK_SOLID):
        x0 = int((x - FEET[0]) // TILE); x1 = int((x + FEET[0] - 0.01) // TILE)
        y0 = int((y - FEET[1]) // TILE); y1 = int((y + FEET[1] - 0.01) // TILE)
        for yy in range(y0, y1 + 1):
            for xx in range(x0, x1 + 1):
                if s.ch(xx, yy) in solid: return False
        return True

    def los(s, a, b):
        # remembered: the same straight line gets checked many, many times
        key = (a, b)
        if key in s._los: return s._los[key]
        ok = True
        d = math.dist(a, b); n = max(1, int(d / 2))
        for i in range(n + 1):
            t = i / n; x = a[0] + (b[0] - a[0]) * t; y = a[1] + (b[1] - a[1]) * t
            if s.cell(x, y) in WIRE_SOLID: ok = False; break
        s._los[key] = ok
        return ok


def center(c, r): return (c * TILE + 16.0, r * TILE + 16.0)


def cross(a, b): return a[0] * b[1] - a[1] * b[0]
def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def sign(v): return (v > 0) - (v < 0)


def swept_over(p, a, frm, to):
    """Same as level.gd _swept_over: did the wire swinging round a from (a->frm)
    to (a->to) pass over p? Not if p was already on the old wire, and a swing of
    no width doesn't count."""
    turn = cross(sub(frm, a), sub(to, a))
    if abs(turn) < 0.001: return False
    s = 1 if turn > 0 else -1
    return (cross(sub(frm, a), sub(p, a)) * s > 0 and cross(sub(to, frm), sub(p, frm)) * s >= 0
            and cross(sub(a, to), sub(p, to)) * s >= 0)


def angle_between(u, v):
    return abs(math.atan2(cross(u, v), u[0] * v[0] + u[1] * v[1]))


def rewrap(M, poles, base, wraps, frm, to):
    """The same as level.gd _update_wraps: the wire runs base -> wraps... -> feet.
    Moving from `frm` to `to` may unwrap the last poles, then wrap a new one.
    wraps = tuple of (pole centre, side)."""
    if frm == to: return wraps
    wraps = list(wraps)
    while wraps:
        p, sd = wraps[-1]
        q = wraps[-2][0] if len(wraps) > 1 else base
        side = sign(cross(sub(p, q), sub(to, p)))
        if side == 0 or side == sd or not M.los(q, to): break
        wraps.pop()
    a = wraps[-1][0] if wraps else base
    best = None; best_ang = 1e9
    for pc in poles:
        if wraps and wraps[-1][0] == pc: continue
        if math.dist(pc, a) < 2.0 or not swept_over(pc, a, frm, to): continue
        ang = angle_between(sub(frm, a), sub(pc, a))
        if ang < best_ang: best_ang = ang; best = pc
    if best is not None:
        wraps.append((best, sign(cross(sub(frm, a), sub(to, a)))))   # which way the wire was swinging
    return tuple(wraps)


def drift(M, anchor, x, y, d):
    """Walk off a hull edge in direction d. Returns (landing, distance, points passed) or None."""
    px, py = x, y; crossed = False; dist = 0.0; pts = []
    for _ in range(600):
        px += d[0] * 2; py += d[1] * 2; dist += 2
        if not M.box_ok(px, py, HARD_SOLID): return None      # would crash into something
        if not M.los(anchor, (px, py)): return None            # the wire would snag
        if M.cell(px, py) == 'X': return None                   # sparks = shock
        pts.append((px, py))
        if not M.box_ok(px, py):
            crossed = True; continue
        if crossed: return (px, py), dist, pts
    return None


def explore(M, pads, poles, cells, anchor, start, budget_px, used):
    """Dijkstra over the 4 px lattice while carrying the wire from `anchor`.
    A state is (spot, wraps): the same spot with the wire wrapped round
    different poles is a different situation.
    Returns events {(pad, wraps): (cost, pos)}, cell_hits {cell: (cost, continue_pos)}
    and the best cost of every state reached."""
    sx, sy = start
    s0 = (round(sx), round(sy), ())
    dist = {s0: 0.0}
    parent = {s0: None}      # state -> the state it was reached from (to rebuild the path)
    pq = [(0.0, sx, sy, ())]
    events = {}; hits = {}

    def touching(x, y, a):
        return [(k, kind, pc) for k, (kind, pc) in pads.items()
                if k not in used and near(x, y, pc, R[kind]) and M.los(a, pc)]

    def note_cells(x, y, cost, cont):
        for c, cc in cells.items():
            if near(x, y, cc, CELL_R) and (c not in hits or hits[c][0] > cost):
                hits[c] = (cost, cont)

    while pq:
        g, x, y, wraps = heapq.heappop(pq)
        if g > dist.get((round(x), round(y), wraps), 1e18) + 1e-6: continue
        a = wraps[-1][0] if wraps else anchor
        note_cells(x, y, g, (x, y))
        touch = touching(x, y, a)
        if touch:
            for k, kind, pc in touch:
                if (k, wraps) not in events or events[(k, wraps)][0] > g:
                    events[(k, wraps)] = (g, (x, y), (round(x), round(y), wraps))
            continue      # touching a pad ends this branch (it triggers)
        here = (round(x), round(y), wraps)

        def push(nx, ny, ng, w):
            key = (round(nx), round(ny), w)
            if ng > budget_px or ng >= dist.get(key, 1e18): return
            dist[key] = ng; parent[key] = here; heapq.heappush(pq, (ng, nx, ny, w))

        for dx, dy in ((STEP, 0), (-STEP, 0), (0, STEP), (0, -STEP), (STEP, STEP), (STEP, -STEP), (-STEP, STEP), (-STEP, -STEP)):
            nx, ny = x + dx, y + dy; ng = g + math.hypot(dx, dy)
            if not M.box_ok(nx, ny): continue
            if M.cell(nx, ny) == 'X': continue
            if MARGIN and any(M.cell(nx + ex, ny + ey) == 'X' for ex in (-MARGIN, MARGIN) for ey in (-MARGIN, MARGIN)):
                continue                                  # --margin: keep clear of red tiles too
            if not M.los(a, (nx, ny)): continue           # the game asks this before the step...
            push(nx, ny, ng, rewrap(M, poles, anchor, wraps, (x, y), (nx, ny)))   # ...and wraps after it
        # walking off a hull edge (only straight up/down/left/right) = drift across the gap
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + d[0] * STEP, y + d[1] * STEP
            if M.box_ok(nx, ny) or not M.box_ok(nx, ny, HARD_SOLID): continue
            res = drift(M, a, x, y, d)
            if res is None: continue
            land, dd, pts = res
            cost = g + dd * WALK / DRIFT
            for i, p in enumerate(pts):
                note_cells(p[0], p[1], cost, land)
            push(land[0], land[1], cost, rewrap(M, poles, anchor, wraps, (x, y), land))
    return events, hits, dist, parent


def path_to(parent, key):
    """The feet positions walked to reach state `key`, first to last."""
    pts = []
    while key is not None:
        pts.append((key[0], key[1])); key = parent[key]
    return pts[::-1]


def sweep(core, a, b):
    """The angle (radians, with a sign) the straight wire a->b sweeps round the
    core, as seen from the core. Same as Vector2.angle_to in level.gd."""
    a1 = math.atan2(a[1] - core[1], a[0] - core[0])
    b1 = math.atan2(b[1] - core[1], b[0] - core[0])
    d = b1 - a1
    while d > math.pi: d -= 2 * math.pi
    while d <= -math.pi: d += 2 * math.pi
    return d


def name(key, kind): return f'{kind}({key[0]},{key[1]})'


def solve_room(M, pads, poles, cells, start_key, max_depth=12, core=None, start_time=None):
    """Every route from START to GOAL: (labels, lowest timer on the way, cells,
    total seconds). The timer carries on from pad to pad: START gives TIME,
    each node adds NODE_TIME (never above MAX_TIME). With `core` (a pixel
    position) there's no goal: a route is finished as soon as the wire (pads,
    poles + his hands) winds a full turn round the core."""
    sols = []

    def chain_wind(start_pt, wraps, end_pt):
        w = 0.0; prev = start_pt
        for pc, _sd in wraps:
            w += sweep(core, prev, pc); prev = pc
        return w + sweep(core, prev, end_pt)

    def rec(anchor, pos, time_left, used, labels, got, depth, ms, wind, el, trail):
        if depth > max_depth: return
        if core is not None and el > CORE_MAX_TIME: return    # far too slow: PIP would have cut it
        events, hits, dist, parent = explore(M, pads, poles, cells, anchor, pos, time_left * WALK, used)
        if core is not None:
            # the fastest spot (walking from this pad) where the loop closes
            best = None
            for (kx, ky, wraps), cost in dist.items():
                if abs(wind + chain_wind(anchor, wraps, (kx, ky - HANDS_UP))) >= 2 * math.pi - 1e-9:
                    if best is None or cost < best[0]: best = (cost, (kx, ky), wraps)
            if best is not None:
                poles_lab = [f'pole({int(pc[0] // TILE)},{int(pc[1] // TILE)})' for pc, _ in best[2]]
                sols.append((labels + poles_lab + [f'loop@({best[1][0]},{best[1][1]})'], min(ms, time_left - best[0] / WALK),
                             got, el + best[0] / WALK, trail + path_to(parent, (best[1][0], best[1][1], best[2]))))
                return    # the loop can close from here: going on to more pads isn't needed
            if abs(wind) > 2.5 * math.pi:
                return    # wound round more than once without closing: a dead end
        for (key, wraps), (g, p, sk) in events.items():
            tl = time_left - g / WALK
            # cells you could grab on the way: get there, then still reach this pad in time
            extra = set()
            for c, (hc, cont) in hits.items():
                if c in got: continue
                if near(cont[0], cont[1], pads[key][1], R[pads[key][0]] + 0.1):
                    extra.add(c); continue
                ev2, _, _, _ = explore(M, pads, poles, {}, anchor, cont, time_left * WALK - hc, used)
                if any(k == key for (k, _w) in ev2): extra.add(c)
            arrive(key, wraps, p, tl, used, labels, got | extra, depth, anchor, min(ms, tl), wind, el + g / WALK,
                   trail + path_to(parent, sk))

    def arrive(key, wraps, p, tl, used, labels, got, depth, prev_anchor, ms, wind, el, trail):
        kind, pc = pads[key]
        lab = [f'pole({int(w[0][0] // TILE)},{int(w[0][1] // TILE)})' for w in wraps] + [name(key, kind)]
        if core is not None:
            sw = chain_wind(prev_anchor, wraps, pc)
            # a loop that turns back round the core loses time it doesn't have:
            # skip pads that take the wire backwards (keeps the search fast)
            if abs(wind) > 0.3 and abs(sw) > 0.35 and (sw > 0) != (wind > 0):
                return
            wind += sw
        lab[-1] += f'@{el:.1f}s'
        if kind == 'G':
            sols.append((labels + lab, ms, got, el, trail)); return
        if kind == 'N':
            rec(pc, p, min(tl + NODE_TIME, MAX_TIME), used | {key}, labels + lab, got, depth + 1, ms, wind, el, trail)

    t0 = min(start_time or TIME, MAX_TIME)
    rec(pads[start_key][1], pads[start_key][1], t0, frozenset([start_key]), [name(start_key, 'S')], frozenset(), 0,
        t0, 0.0, 0.0, [])
    return sols


def rooms(g):
    H = len(g); W = len(g[0]); seen = {}; out = []
    for r in range(H):
        for c in range(W):
            if (c, r) in seen or g[r][c] in '# DFM=': continue
            stack = [(c, r)]; seen[(c, r)] = len(out); cells = []
            while stack:
                cc, rr = stack.pop(); cells.append((cc, rr))
                for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    n = (cc + dc, rr + dr)
                    if 0 <= n[1] < H and 0 <= n[0] < W and n not in seen and g[n[1]][n[0]] not in '# DFM=':
                        seen[n] = len(out); stack.append(n)
            out.append(cells)
    return out


def near4(c, r): return ((c + 1, r), (c - 1, r), (c, r + 1), (c, r - 1))


def barrier_groups(g, room_of):
    """Touching '=' tiles form one GROUP that moves together. Returns a list of
    (tiles, rooms next to the group) - same as level.gd's _barrier_groups."""
    seen = set(); out = []
    for r, row in enumerate(g):
        for c, ch in enumerate(row):
            if ch != '=' or (c, r) in seen: continue
            stack = [(c, r)]; seen.add((c, r)); tiles = []; near = set()
            while stack:
                t = stack.pop(); tiles.append(t)
                for n in near4(*t):
                    if n in room_of: near.add(room_of[n])
                    if 0 <= n[1] < len(g) and 0 <= n[0] < len(g[n[1]]) and g[n[1]][n[0]] == '=' and n not in seen:
                        seen.add(n); stack.append(n)
            out.append((tiles, near))
    return out


def walking_order(g, rms):
    """Rooms in the order you reach them from the spawn (P), through doors and
    barriers - the same numbering level.gd uses. Also returns the AREAS: rooms
    joined by barriers (they share nodes once powered)."""
    room_of = {cell: i for i, cells in enumerate(rms) for cell in cells}
    links = {i: set() for i in range(len(rms))}
    for r, row in enumerate(g):
        for c, ch in enumerate(row):
            if ch not in 'DFM': continue
            adj = {room_of[n] for n in near4(c, r) if n in room_of}
            for a in adj: links[a] |= adj - {a}
    groups = barrier_groups(g, room_of)
    area = list(range(len(rms)))
    def find(i):
        while area[i] != i: i = area[i]
        return i
    for tiles, near in groups:
        for a in near:
            links[a] |= near - {a}
            for b in near: area[find(a)] = find(b)
    first = next((room_of[(c, r)] for r, row in enumerate(g) for c, ch in enumerate(row) if ch == 'P'), 0)
    order = [first]
    for i in order:
        for n in sorted(links[i]):
            if n not in order: order.append(n)
    order += [i for i in range(len(rms)) if i not in order]
    return order, room_of, groups, [find(i) for i in range(len(rms))]


def open_barriers(g, groups, done):
    """The map as it is once the rooms in `done` are powered: every barrier group
    touching one of them has sunk into the floor."""
    g = [list(row) for row in g]
    for tiles, near in groups:
        if near & done:
            for c, r in tiles: g[r][c] = '.'
    return [''.join(row) for row in g]


if __name__ == '__main__':
    args = sys.argv[1:]
    paths_out = None
    if '--paths' in args:      # write the most forgiving route of each stage (feet positions) to a JSON file
        i = args.index('--paths'); paths_out = args[i + 1]; del args[i:i + 2]
    paths = {}
    for flag, var in (('--time', 'TIME'), ('--node', 'NODE_TIME'), ('--max', 'MAX_TIME'), ('--margin', 'MARGIN')):
        if flag in args:
            i = args.index(flag); globals()[var] = float(args[i + 1]); del args[i:i + 2]
    sys.argv = [sys.argv[0]] + args
    if sys.argv[1].endswith('.tscn'):
        # a level scene: make the text map with map_from_scene.py, and read the
        # level's Rules numbers (anything not set in the scene keeps level.gd's default)
        import re, subprocess, os
        here = os.path.dirname(os.path.abspath(__file__))
        txt = os.path.join(here, 'out', os.path.basename(sys.argv[1]).replace('.tscn', '.txt'))
        subprocess.run([sys.executable, os.path.join(here, 'map_from_scene.py'), sys.argv[1], txt],
                       check=True, stdout=subprocess.DEVNULL)
        scene = open(sys.argv[1], encoding='utf-8').read()
        root = scene[scene.index('[node '):]
        root = root[:root.index('[node ', 1)] if '[node ' in root[1:] else root
        for prop, var in (('wire_time', 'TIME'), ('node_time', 'NODE_TIME'), ('max_wire_time', 'MAX_TIME')):
            m = re.search(rf'^{prop} = ([\d.]+)', root, re.M)
            if m: globals()[var] = float(m.group(1))
        m = re.search(r'^room_wire_time = PackedFloat32Array\(([^)]*)\)', root, re.M)
        if m and m.group(1).strip():
            for i, v in enumerate(m.group(1).split(',')):
                if float(v) > 0: ROOM_TIME[i + 1] = float(v)
        sys.argv[1] = txt
    g, floating = floating_cells(load(sys.argv[1]))
    poles = [center(c, r) for r, row in enumerate(g) for c, ch in enumerate(row) if ch == 'B']
    print(f'Rules: START {TIME} s, node +{NODE_TIME} s, max {MAX_TIME} s' +
          (f', own START times {ROOM_TIME}' if ROOM_TIME else ''))
    rms = rooms(g)
    order, room_of, groups, area = walking_order(g, rms)
    only = {int(a) for a in sys.argv[2:]}          # e.g.  solver2.py map.txt 3  = only stage 3
    for k, ri in enumerate(order):
        if only and k + 1 not in only: continue
        cells_of_room = rms[ri]
        # only rooms with a START get powered (halls don't move barriers)
        done = set(o for o in order[:k] if any(g[r][c] == 'S' for (c, r) in rms[o]))
        M = Map(open_barriers(g, groups, done))
        pads = {}; cells = {}
        for (c, r) in cells_of_room:
            ch = g[r][c]
            if ch in 'SNG': pads[(c, r)] = (ch, center(c, r))
            if ch == '*' or (c, r) in floating: cells[(c, r)] = center(c, r)
        # nodes of stages you already powered in the same area still work
        for o in done:
            if area[o] != area[ri]: continue
            for (c, r) in rms[o]:
                if g[r][c] == 'N': pads[(c, r)] = (g[r][c], center(c, r))
        st = [k for k, v in pads.items() if v[0] == 'S']
        if not st: continue
        cores = [(c, r) for (c, r) in cells_of_room if g[r][c] == '@']
        core = center(*cores[0]) if cores else None
        # sockets: try the room with no clamp, and with the clamp in each socket
        # (the clamp is solid and the wire wraps round it, exactly like a pole)
        sockets = [(c, r) for (c, r) in cells_of_room if g[r][c] == 'o']
        sols = []
        clamp_of = {}                  # id(solution) -> socket used
        for sock in [None] + sockets:
            Mx, px = M, poles
            if sock is not None:
                gg = [list(row) for row in M.g]
                gg[sock[1]][sock[0]] = 'B'
                Mx, px = Map([''.join(row) for row in gg]), poles + [center(*sock)]
            for s in solve_room(Mx, pads, px, cells, st[0], max_depth=6 if core else 12, core=core,
                                start_time=ROOM_TIME.get(k + 1)):
                if sock is not None:
                    s = (s[0] + [f'(clamp in {sock})'],) + tuple(s[1:])
                clamp_of[id(s)] = sock
                sols.append(s)
        kind = f'CORE {cores[0]}: wrap the wire round it' if cores else 'goal'
        print(f'Stage {k + 1} (start {st[0]}, {kind}, START {min(ROOM_TIME.get(k + 1, TIME), MAX_TIME)} s): {len(sols)} solutions')
        if sockets and not any(clamp_of[id(s)] is None for s in sols) and sols:
            print('    needs the clamp: no route without it')
        if sols:
            top = max(sols, key=lambda x: (x[1], -x[3]))
            print(f'    most forgiving route: lowest timer {top[1]:.2f} s')
            paths[k + 1] = {'labels': top[0], 'lowest': top[1], 'points': top[4], 'start': list(st[0]),
                            'clamp': list(clamp_of[id(top)]) if clamp_of[id(top)] else None}
        best = {}
        for labels, spare, got, total, _trail in sols:
            key = ' -> '.join(labels)
            if key not in best or best[key][0] < spare or len(best[key][1]) < len(got):
                best[key] = (max(spare, best.get(key, (spare,))[0]), got, total)
        # fastest first: in a core room PIP's shutdown meter is racing you
        ranked = sorted(best.items(), key=lambda kv: kv[1][2])
        for key, (spare, got, total) in ranked[:12]:
            print(f'    {key}   (lowest timer: {spare:.2f} s, {total:.1f} s in all)')
        if cells:
            for c in sorted(cells):
                ok = [k for k, (s, got, _t) in best.items() if c in got]
                print(f'    cell {c}: ' + ('collectible' if ok else 'NOT collectible on any route'))
    if paths_out:
        import json
        json.dump(paths, open(paths_out, 'w'))
