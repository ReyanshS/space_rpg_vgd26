# solver2.py - checks that every room of a level can be solved, and HOW.
# Simulates the real rules (free walking, taut wire that can't cross walls/crates/red,
# nodes refill + pause the timer, bends fling you) on a 4 px grid and lists every
# route that finishes each 5 s segment in time. Use it after changing a room to make
# sure there's no shortcut and no impossible segment. The constants below must match
# player.gd (walk_speed, fling_speed) and level.gd (wire_time, pad radii).
#     python tools/map_from_scene.py
#     python tools/solver2.py tools/out/level1.txt
import math, heapq, sys
TILE=32; FEET=(6,4); WALK=100.0; FLING=260.0; TIME=5.0
R={'N':22.0,'G':20.0,'B':16.0}
STEP=4
def load(p):
    rows=open(p).read().split('\n'); w=max(len(r) for r in rows)
    return [r.ljust(w) for r in rows]
class Map:
    def __init__(s,g): s.g=g; s.H=len(g); s.W=len(g[0])
    def ch(s,c,r):
        if r<0 or r>=s.H or c<0 or c>=s.W: return ' '
        return s.g[r][c]
    def cell(s,x,y): return s.ch(int(x//TILE),int(y//TILE))
    def walk_solid(s,ch): return ch in '# CD'
    def wire_solid(s,ch): return ch in '# CDEX'
    def box_ok(s,x,y):
        x0=int((x-FEET[0])//TILE); x1=int((x+FEET[0]-0.01)//TILE)
        y0=int((y-FEET[1])//TILE); y1=int((y+FEET[1]-0.01)//TILE)
        for yy in range(y0,y1+1):
            for xx in range(x0,x1+1):
                if s.walk_solid(s.ch(xx,yy)): return False
        return True
    def los(s,a,b):
        d=math.dist(a,b); n=max(1,int(d/2))
        for i in range(n+1):
            t=i/n; x=a[0]+(b[0]-a[0])*t; y=a[1]+(b[1]-a[1])*t
            if s.wire_solid(s.cell(x,y)): return False
        return True
def center(c,r): return (c*TILE+16.0, r*TILE+16.0)
def snap8(v):
    ang=math.atan2(v[1],v[0]); k=round(ang/(math.pi/4))%8
    return [(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1),(0,-1),(1,-1)][k]
def norm(v):
    l=math.hypot(*v); return (v[0]/l,v[1]/l)

def explore(M, pads, anchor, start, budget_px, used):
    """Dijkstra over the lattice; returns events [(kind,pad,g,pos)]"""
    sx,sy=start
    dist={ (round(sx),round(sy)):0.0 }
    pq=[(0.0,sx,sy)]
    events={}
    while pq:
        g,x,y=heapq.heappop(pq)
        if g>dist.get((round(x),round(y)),1e18)+1e-6: continue
        # touches
        for key,(kind,pc) in pads.items():
            if key in used: continue
            if math.dist((x,y),pc)<=R[kind] and M.los(anchor,pc):
                if kind=='B':
                    d=snap8((pc[0]-anchor[0],pc[1]-anchor[1])); left=norm((d[1],-d[0]))
                    side='L' if ( (x-pc[0])*left[0]+(y-pc[1])*left[1] )>=0 else 'R'
                    k=(key,side)
                else: k=(key,None)
                if k not in events or events[k][0]>g: events[k]=(g,(x,y))
                continue
        if any(math.dist((x,y),pc)<=R[kind] and M.los(anchor,pc) for key,(kind,pc) in pads.items() if key not in used):
            continue  # touching a pad ends this branch (it triggers)
        for dx,dy in ((STEP,0),(-STEP,0),(0,STEP),(0,-STEP),(STEP,STEP),(STEP,-STEP),(-STEP,STEP),(-STEP,-STEP)):
            nx,ny=x+dx,y+dy; ng=g+math.hypot(dx,dy)
            if ng>budget_px: continue
            key=(round(nx),round(ny))
            if ng>=dist.get(key,1e18): continue
            if not M.box_ok(nx,ny): continue
            if M.cell(nx,ny)=='X': continue
            if not M.los(anchor,(nx,ny)): continue
            dist[key]=ng; heapq.heappush(pq,(ng,nx,ny))
    return events

def fling(M,pads,bend_key,pc,d,used):
    """returns ('stop',pos,dist) | ('pad',key,kind,pos,dist) | ('shock',...)"""
    v=norm(d); x,y=pc; t=0.0
    while True:
        nx,ny=x+v[0]*2,y+v[1]*2
        if not M.box_ok(nx,ny): return ('stop',(x,y),t)
        x,y=nx,ny; t+=2
        if M.cell(x,y)=='X': return ('shock',(x,y),t)
        for key,(kind,pcc) in pads.items():
            if key in used or key==bend_key: continue
            if math.dist((x,y),pcc)<=R[kind] and M.los(pc,pcc):
                return ('pad',key,kind,(x,y),t)

def solve_room(M,pads,start_key,max_depth=10):
    sols=[]
    S=pads[start_key][1]
    def rec(anchor_key,anchor,pos,time_left,used,path,depth):
        if depth>max_depth: return
        ev=explore(M,pads,anchor,pos,time_left*WALK,used)
        for (key,side),(g,p) in ev.items():
            kind=pads[key][0]; tl=time_left-g/WALK
            label=f'{kind}{key}'+(f'[{side}]' if side else '')+f' t_left={tl:.2f}'
            handle(key,kind,side,p,tl,used,path+[label],depth,anchor)
    def handle(key,kind,side,p,tl,used,path,depth,prev_anchor):
        pc=pads[key][1]
        if kind=='G': sols.append(path); return
        if kind=='N':
            rec(key,pc,p,TIME+R['N']/WALK,used|{key},path,depth+1); return
        if kind=='B':
            d=snap8((pc[0]-prev_anchor[0],pc[1]-prev_anchor[1]))
            nd=(d[1],-d[0]) if side=='L' else (-d[1],d[0])
            res=fling(M,pads,key,pc,nd,used|{key})
            if res[0]=='shock': return
            if res[0]=='stop':
                _,pos,t=res; tl2=tl-t/FLING
                if tl2<=0: return
                rec(key,pc,pos,tl2,used|{key},path+[f'fling->{pos[0]:.0f},{pos[1]:.0f}'],depth+1)
            else:
                _,k2,kind2,pos,t=res; tl2=tl-t/FLING
                if tl2<=0: return
                handle(k2,kind2,None if kind2!='B' else ('L' if True else 'R'),pos,tl2,used|{key},path+[f'fling:{kind2}{k2}'],depth+1,pc) if kind2!='B' else \
                  [handle(k2,kind2,sd,pos,tl2,used|{key},path+[f'fling:{kind2}{k2}[{sd}]'],depth+1,pc) for sd in 'LR']
    rec(start_key,S,S,TIME,frozenset([start_key]),[],0)
    return sols

def rooms(g):
    H=len(g); W=len(g[0]); seen={}; out=[]
    for r in range(H):
        for c in range(W):
            if (c,r) in seen or g[r][c] in '# D': continue
            stack=[(c,r)]; seen[(c,r)]=len(out); cells=[]
            while stack:
                cc,rr=stack.pop(); cells.append((cc,rr))
                for dc,dr in ((1,0),(-1,0),(0,1),(0,-1)):
                    n=(cc+dc,rr+dr)
                    if 0<=n[1]<H and 0<=n[0]<W and n not in seen and g[n[1]][n[0]] not in '# D':
                        seen[n]=len(out); stack.append(n)
            out.append(cells)
    return out
if __name__=='__main__':
    g=load(sys.argv[1]); M=Map(g)
    for cells in rooms(g):
        pads={}
        for (c,r) in cells:
            ch=g[r][c]
            if ch in 'SNBG': pads[(c,r)]=(ch,center(c,r))
        st=[k for k,v in pads.items() if v[0]=='S']
        if not st: continue
        sols=solve_room(M,pads,st[0])
        print(f'Room start {st[0]}: {len(sols)} solutions')
        uniq=[]
        for s in sols:
            key=tuple(x.split(' ')[0] for x in s)
            if key not in uniq: uniq.append(key)
        for u in uniq[:12]: print('   ',' -> '.join(u))
