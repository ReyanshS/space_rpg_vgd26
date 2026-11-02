# light_preview.py - mock-up of the in-game lighting (dark ship, emergency lights,
# helmet lamp, glowing pads) using the same maths as Godot:
#     pixel = colour x (darkness + lights), glowing things added on top.
# Change DARK / the light numbers here to try ideas before changing level.gd.
#     python tools/light_preview.py      -> tools/out/light_preview.png
# Lighting preview: albedo x (darkness + lights) + glow items, using the same
# numbers as level.gd / puzzle_tile.gd / player.gd / light_fx.gd.
import sys, json, math, numpy as np
from PIL import Image
sys.path.insert(0,'tools')
import render as R
g=R.load('tools/out/level1.txt'); H,W=len(g),len(g[0]); TILE=32
DARK=np.array([0.2,0.21,0.3])   # level.gd -> darkness
albedo=R.render(g).convert('RGBA')
astro=Image.open('Assets/images/astronaut/astronaut.png').convert('RGBA')
puz=Image.open('Assets/images/tiles/puzzle_tiles.png').convert('RGBA')
chev=Image.open('Assets/images/ui/guide_chevron.png').convert('RGBA')
GLOW={'S':(1.0,0.85,0.3),'G':(0.35,0.65,1.0),'N':(1.0,0.55,0.2),'B':(0.75,0.45,1.0),'X':(1.0,0.25,0.25),'D':(0.4,1.0,0.55)}
PIDX=R.PIDX
def room_cells():
    seen={}; rooms=[]
    for r in range(H):
        for c in range(W):
            ch=g[r][c]
            if ch in '# D' or (r,c) in seen: continue
            cells=[]; st=[(r,c)]; seen[(r,c)]=len(rooms)
            while st:
                y,x=st.pop(); cells.append((x,y))
                for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
                    ny,nx=y+dy,x+dx
                    if 0<=ny<H and 0<=nx<W and g[ny][nx] not in '# D' and (ny,nx) not in seen:
                        seen[(ny,nx)]=len(rooms); st.append((ny,nx))
            rooms.append(cells)
    return rooms,seen
ROOMS,ROOM_OF=room_cells()
def light_field(acc,pos,radius,energy,color):
    x0,y0=int(pos[0]-radius),int(pos[1]-radius); x1,y1=int(pos[0]+radius)+1,int(pos[1]+radius)+1
    xa,ya=max(0,x0),max(0,y0); xb,yb=min(acc.shape[1],x1),min(acc.shape[0],y1)
    if xa>=xb or ya>=yb: return
    yy,xx=np.mgrid[ya:yb,xa:xb]
    t=np.hypot(xx+0.5-pos[0],yy+0.5-pos[1])/radius
    a=np.where(t<0.4,1-1.25*t,np.clip(0.5*(1-(t-0.4)/0.6),0,1))
    acc[ya:yb,xa:xb]+=a[...,None]*energy*np.array(color)
def scene(powered_rooms=(), player_at=(272,688), lit_scale=1.0):
    img=albedo.copy()
    fr=0   # frame 0 of the sheet = standing, facing the camera
    img.alpha_composite(astro.crop((fr*32,0,fr*32+32,40)),(player_at[0]-16,player_at[1]-19-20))
    A=np.asarray(img).astype(float)[...,:3]/255
    L=np.zeros_like(A)+DARK
    for i,cells in enumerate(ROOMS):
        xs=[c[0] for c in cells]; ys=[c[1] for c in cells]
        if any(g[y][x]=='E' for x,y in cells): continue
        mn=(min(xs),min(ys)); mx=(max(xs),max(ys))
        bx,by,bw=mn[0]-1,mn[1]-3,mx[0]-mn[0]+3
        if i not in powered_rooms:
            light_field(L,((bx+bw*0.5)*TILE,(by+4)*TILE),150,0.45,(1.0,0.18,0.12))
        else:
            sx,sy=mx[0]-mn[0]+1,mx[1]-mn[1]+1; nx,ny=max(1,math.ceil(sx/7)),max(1,math.ceil(sy/7))
            cs=set(cells)
            for j in range(ny):
                for k in range(nx):
                    spot=(int(mn[0]+(k+0.5)*sx/nx),int(mn[1]+(j+0.5)*sy/ny))
                    if spot not in cs: spot=min(cells,key=lambda c:(c[0]-spot[0])**2+(c[1]-spot[1])**2)
                    light_field(L,(spot[0]*32+16,spot[1]*32+16),210,0.75,(1.0,0.95,0.85))
    for r in range(H):
        for c in range(W):
            ch=g[r][c]
            if ch in GLOW and ch!='X':
                col=(1.0,0.3,0.25) if ch=='D' and ROOM_OF.get((r+1,c))not in powered_rooms and ROOM_OF.get((r-1,c)) not in powered_rooms and ROOM_OF.get((r,c-1)) not in powered_rooms and ROOM_OF.get((r,c+1)) not in powered_rooms else GLOW[ch]
                light_field(L,(c*32+16,r*32+16),44,0.5,col)
    light_field(L,(player_at[0],player_at[1]-18),100,0.85,(0.8,0.9,1.0))   # helmet lamp
    out=A*L*lit_scale
    # glow channel: drawn at full colour (0.16 + 0.85 ~ 1)
    for r in range(H):
        for c in range(W):
            ch=g[r][c]
            if ch in GLOW:
                a=0.4 if ch=='X' else 0.25
                spr=np.asarray(puz.crop((PIDX[ch]*32,0,PIDX[ch]*32+32,32))).astype(float)/255
                add=spr[...,:3]*np.array(GLOW[ch])*a*spr[...,3:]
                out[r*32:r*32+32,c*32:c*32+32]+=add
    return out
def draw_guide(out,pts,alpha=0.6):
    # Line2D TILE mode: texture height 10 -> width 10, repeats every 16 px
    ch=np.asarray(chev).astype(float)/255
    for (x0,y0),(x1,y1) in zip(pts,pts[1:]):
        L=math.hypot(x1-x0,y1-y0); ang=math.degrees(math.atan2(y1-y0,x1-x0))
        n=int(L//16)
        for i in range(n):
            t=Image.fromarray((ch*255).astype(np.uint8)).rotate(-ang,expand=True,resample=Image.NEAREST)
            tt=np.asarray(t).astype(float)/255
            cx=x0+(x1-x0)*(i*16+8)/L; cy=y0+(y1-y0)*(i*16+8)/L
            ox,oy=int(cx-tt.shape[1]/2),int(cy-tt.shape[0]/2)
            a=tt[...,3:]*alpha
            reg=out[oy:oy+tt.shape[0],ox:ox+tt.shape[1]]
            reg[:]=reg*(1-a)+tt[...,:3]*a
def crop(out,center,name):
    cx,cy=center; x0,y0=int(cx-240),int(cy-135)
    pad=np.zeros((out.shape[0]+600,out.shape[1]+600,3)); pad[300:300+out.shape[0],300:300+out.shape[1]]=out
    v=pad[y0+300:y0+300+270,x0+300:x0+300+480]
    im=Image.fromarray((np.clip(v,0,1)*255).astype(np.uint8)).resize((960,540),Image.NEAREST)
    im.save(name); return im
if __name__=='__main__':
    o=scene(); draw_guide(o,[(432,624),(112,624)]); draw_guide(o,[(240,464),(112,336),(240,208)])
    a=crop(o,(272,600),'tools/out/light_room1_dark.png')
    o2=scene(powered_rooms=(ROOM_OF[(19,3)],),player_at=(112,624)); draw_guide(o2,[(240,464),(112,336),(240,208)])
    b=crop(o2,(272,600),'tools/out/light_room1_powered.png')
    o3=scene(powered_rooms=(ROOM_OF[(19,3)],),player_at=(240,480)); draw_guide(o3,[(240,464),(112,336),(240,208)])
    c=crop(o3,(208,330),'tools/out/light_room2_dark.png')
    sheet=Image.new('RGB',(960,540*3+20),(255,255,255)); sheet.paste(a,(0,0)); sheet.paste(b,(0,550)); sheet.paste(c,(0,1100))
    sheet.save('tools/out/light_preview.png'); print('ok', ROOM_OF[(19,3)], len(ROOMS))
