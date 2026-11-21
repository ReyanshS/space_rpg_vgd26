# solver2.py - checks that every room of a level can be solved, and HOW.
# Simulates the real rules (free walking, taut wire that can't cross walls/crates/red,
# nodes refill + pause the timer, bends fling you, walking off a hull edge makes you
# DRIFT across open space) on a 4 px grid and lists every route that finishes each
# 4 s segment in time. It also checks every POWER CELL: can you charge it with the
# live wire and still make it to the next pad in time?
# Use it after changing a room to make sure there's no shortcut and no impossible segment.
# The constants below must match player.gd (walk_speed, fling_speed, drift_speed)
# and level.gd (wire_time, pad radii, CELL_RADIUS).
#     python tools/map_from_scene.py
#     python tools/solver2.py tools/out/level1.txt
import math, heapq, sys
TILE = 32; FEET = (6, 4); WALK = 100.0; FLING = 260.0; DRIFT = 150.0; TIME = 4.0
R = {'N': 22.0, 'G': 22.0, 'B': 20.0}
CELL_R = 14.0
BODY_UP = 10.0          # pads count from the feet AND from 10 px higher (level.gd _touching)


def near(x, y, pc, r):
    return math.dist((x, y), pc) <= r or math.dist((x, y - BODY_UP), pc) <= r
STEP = 4
HANDS_UP = 9.0          # the wire ends at his hands, 9 px above his feet (player.gd hand_position)
CORE_MAX_TIME = 30.0    # core rooms: routes slower than this (seconds) aren't worth listing
WALK_SOLID = '# CD=~@'  # your feet can't go here (open space too: mag boots need hull)
HARD_SOLID = '# CD=@'   # you can't pass here at all, not even drifting
WIRE_SOLID = '# CD=EX@' # the wire can't cross these (it CAN cross open space)
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


def snap8(v):
    ang = math.atan2(v[1], v[0]); k = round(ang / (math.pi / 4)) % 8
    return [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)][k]


def norm(v):
    l = math.hypot(*v); return (v[0] / l, v[1] / l)


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


def explore(M, pads, cells, anchor, start, budget_px, used):
    """Dijkstra over the 4 px lattice while carrying the wire.
    Returns events {(pad, side): (cost, pos)} and cell_hits {cell: (cost, continue_pos)}."""
    sx, sy = start
    dist = {(round(sx), round(sy)): 0.0}
    pq = [(0.0, sx, sy)]
    events = {}; hits = {}

    def touching(x, y):
        return [(k, kind, pc) for k, (kind, pc) in pads.items()
                if k not in used and near(x, y, pc, R[kind]) and M.los(anchor, pc)]

    def note_cells(x, y, cost, cont):
        for c, cc in cells.items():
            if near(x, y, cc, CELL_R) and (c not in hits or hits[c][0] > cost):
                hits[c] = (cost, cont)

    while pq:
        g, x, y = heapq.heappop(pq)
        if g > dist.get((round(x), round(y)), 1e18) + 1e-6: continue
        note_cells(x, y, g, (x, y))
        touch = touching(x, y)
        if touch:
            for k, kind, pc in touch:
                for side in (('L', 'R') if kind == 'B' else (None,)):
                    if (k, side) not in events or events[(k, side)][0] > g:
                        events[(k, side)] = (g, (x, y))
            continue      # touching a pad ends this branch (it triggers)

        def push(nx, ny, ng):
            key = (round(nx), round(ny))
            if ng > budget_px or ng >= dist.get(key, 1e18): return
            dist[key] = ng; heapq.heappush(pq, (ng, nx, ny))

        for dx, dy in ((STEP, 0), (-STEP, 0), (0, STEP), (0, -STEP), (STEP, STEP), (STEP, -STEP), (-STEP, STEP), (-STEP, -STEP)):
            nx, ny = x + dx, y + dy; ng = g + math.hypot(dx, dy)
            if not M.box_ok(nx, ny): continue
            if M.cell(nx, ny) == 'X': continue
            if not M.los(anchor, (nx, ny)): continue
            push(nx, ny, ng)
        # walking off a hull edge (only straight up/down/left/right) = drift across the gap
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + d[0] * STEP, y + d[1] * STEP
            if M.box_ok(nx, ny) or not M.box_ok(nx, ny, HARD_SOLID): continue
            res = drift(M, anchor, x, y, d)
            if res is None: continue
            land, dd, pts = res
            cost = g + dd * WALK / DRIFT
            for i, p in enumerate(pts):
                note_cells(p[0], p[1], cost, land)
            push(land[0], land[1], cost)
    return events, hits, dist


def sweep(core, a, b):
    """The angle (radians, with a sign) the straight wire a->b sweeps round the
    core, as seen from the core. Same as Vector2.angle_to in level.gd."""
    a1 = math.atan2(a[1] - core[1], a[0] - core[0])
    b1 = math.atan2(b[1] - core[1], b[0] - core[0])
    d = b1 - a1
    while d > math.pi: d -= 2 * math.pi
    while d <= -math.pi: d += 2 * math.pi
    return d


def fling(M, pads, cells, bend_key, pc, d, used):
    """Returns (result, pos, distance, cells passed). result = 'stop' | ('pad', key, kind) | 'shock'."""
    v = norm(d); x, y = pc; t = 0.0; got = set()
    while True:
        nx, ny = x + v[0] * 2, y + v[1] * 2
        if not M.box_ok(nx, ny): return 'stop', (x, y), t, got
        x, y = nx, ny; t += 2
        if M.cell(x, y) == 'X': return 'shock', (x, y), t, got
        for c, cc in cells.items():
            if near(x, y, cc, CELL_R): got.add(c)
        for key, (kind, pcc) in pads.items():
            if key in used or key == bend_key: continue
            if near(x, y, pcc, R[kind]) and M.los(pc, pcc):
                return ('pad', key, kind), (x, y), t, got


def name(key, kind): return f'{kind}({key[0]},{key[1]})'


def solve_room(M, pads, cells, start_key, max_depth=12, core=None):
    """Every route from START to GOAL: (labels, spare seconds on its tightest segment,
    cells, total seconds). With `core` (a pixel position) there's no goal: a route
    is finished as soon as the wire (pads touched + his hands) winds a full turn
    round the core."""
    sols = []

    def rec(anchor, pos, time_left, used, labels, got, depth, ms, wind, el):
        if depth > max_depth: return
        if core is not None and el > CORE_MAX_TIME: return    # far too slow: PIP would have cut it
        events, hits, dist = explore(M, pads, cells, anchor, pos, time_left * WALK, used)
        if core is not None:
            # the fastest spot (walking from this pad) where the loop closes
            best = None
            for (kx, ky), cost in dist.items():
                if abs(wind + sweep(core, anchor, (kx, ky - HANDS_UP))) >= 2 * math.pi - 1e-9:
                    if best is None or cost < best[0]: best = (cost, (kx, ky))
            if best is not None:
                sols.append((labels + [f'loop@({best[1][0]},{best[1][1]})'], min(ms, time_left - best[0] / WALK),
                             got, el + best[0] / WALK))
                return    # the loop can close from here: going on to more pads isn't needed
            if abs(wind) > 2.5 * math.pi:
                return    # wound round more than once without closing: a dead end
        for (key, side), (g, p) in events.items():
            tl = time_left - g / WALK
            # cells you could grab on the way: get there, then still reach this pad in time
            extra = set()
            for c, (hc, cont) in hits.items():
                if c in got: continue
                if near(cont[0], cont[1], pads[key][1], R[pads[key][0]] + 0.1):
                    extra.add(c); continue
                ev2, _, _ = explore(M, pads, {}, anchor, cont, time_left * WALK - hc, used)
                if any(k == key for (k, _s) in ev2): extra.add(c)
            arrive(key, side, p, tl, used, labels, got | extra, depth, anchor, min(ms, tl), wind, el + g / WALK)

    def arrive(key, side, p, tl, used, labels, got, depth, prev_anchor, ms, wind, el):
        kind, pc = pads[key]
        lab = name(key, kind) + (f'[{side}]' if side else '')
        if core is not None:
            sw = sweep(core, prev_anchor, pc)
            # a loop that turns back round the core loses time it doesn't have:
            # skip pads that take the wire backwards (keeps the search fast)
            if abs(wind) > 0.3 and abs(sw) > 0.35 and (sw > 0) != (wind > 0):
                return
            wind += sw
        if kind == 'G':
            sols.append((labels + [lab], ms, got, el)); return
        if kind == 'N':
            rec(pc, p, TIME + R['N'] / WALK, used | {key}, labels + [lab], got, depth + 1, ms, wind, el); return
        if kind == 'B':
            d = snap8((pc[0] - prev_anchor[0], pc[1] - prev_anchor[1]))
            nd = (d[1], -d[0]) if side == 'L' else (-d[1], d[0])
            res, pos, t, passed = fling(M, pads, cells, key, pc, nd, used | {key})
            tl2 = tl - t / FLING
            if res == 'shock' or tl2 <= 0: return
            if res == 'stop':
                rec(pc, pos, tl2, used | {key}, labels + [lab, f'fling->({pos[0]:.0f},{pos[1]:.0f})'], got | passed,
                    depth + 1, min(ms, tl2), wind, el + t / FLING)
            else:
                _, k2, kind2 = res
                for sd in (('L', 'R') if kind2 == 'B' else (None,)):
                    arrive(k2, sd, pos, tl2, used | {key}, labels + [lab, 'fling'], got | passed, depth + 1, pc,
                           min(ms, tl2), wind, el + t / FLING)

    rec(pads[start_key][1], pads[start_key][1], TIME, frozenset([start_key]), [name(start_key, 'S')], frozenset(), 0,
        TIME, 0.0, 0.0)
    return sols


def rooms(g):
    H = len(g); W = len(g[0]); seen = {}; out = []
    for r in range(H):
        for c in range(W):
            if (c, r) in seen or g[r][c] in '# D=': continue
            stack = [(c, r)]; seen[(c, r)] = len(out); cells = []
            while stack:
                cc, rr = stack.pop(); cells.append((cc, rr))
                for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    n = (cc + dc, rr + dr)
                    if 0 <= n[1] < H and 0 <= n[0] < W and n not in seen and g[n[1]][n[0]] not in '# D=':
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
    joined by barriers (they share nodes and bends once powered)."""
    room_of = {cell: i for i, cells in enumerate(rms) for cell in cells}
    links = {i: set() for i in range(len(rms))}
    for r, row in enumerate(g):
        for c, ch in enumerate(row):
            if ch != 'D': continue
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
    g, floating = floating_cells(load(sys.argv[1]))
    rms = rooms(g)
    order, room_of, groups, area = walking_order(g, rms)
    only = {int(a) for a in sys.argv[2:]}          # e.g.  solver2.py map.txt 3  = only stage 3
    for k, ri in enumerate(order):
        if only and k + 1 not in only: continue
        cells_of_room = rms[ri]
        done = set(order[:k])
        M = Map(open_barriers(g, groups, done))
        pads = {}; cells = {}
        for (c, r) in cells_of_room:
            ch = g[r][c]
            if ch in 'SNBG': pads[(c, r)] = (ch, center(c, r))
            if ch == '*' or (c, r) in floating: cells[(c, r)] = center(c, r)
        # nodes and bends of stages you already powered in the same area still work
        for o in done:
            if area[o] != area[ri]: continue
            for (c, r) in rms[o]:
                if g[r][c] in 'NB': pads[(c, r)] = (g[r][c], center(c, r))
        st = [k for k, v in pads.items() if v[0] == 'S']
        if not st: continue
        cores = [(c, r) for (c, r) in cells_of_room if g[r][c] == '@']
        core = center(*cores[0]) if cores else None
        sols = solve_room(M, pads, cells, st[0], max_depth=6 if core else 12, core=core)
        kind = f'CORE {cores[0]}: wrap the wire round it' if cores else 'goal'
        print(f'Stage {k + 1} (start {st[0]}, {kind}): {len(sols)} solutions')
        best = {}
        for labels, spare, got, total in sols:
            key = ' -> '.join(labels)
            if key not in best or best[key][0] < spare or len(best[key][1]) < len(got):
                best[key] = (max(spare, best.get(key, (spare,))[0]), got, total)
        # fastest first: in a core room PIP's shutdown meter is racing you
        ranked = sorted(best.items(), key=lambda kv: kv[1][2])
        for key, (spare, got, total) in ranked[:12]:
            print(f'    {key}   (tightest segment: {spare:.2f} s spare, {total:.1f} s in all)')
        if cells:
            for c in sorted(cells):
                ok = [k for k, (s, got, _t) in best.items() if c in got]
                print(f'    cell {c}: ' + ('collectible' if ok else 'NOT collectible on any route'))
