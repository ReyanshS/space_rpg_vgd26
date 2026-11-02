# render.py - draws a text map with the real tiles, to preview a level as one image.
#     python tools/render.py tools/out/level1.txt tools/out/map_preview.png
import sys, numpy as np
from PIL import Image
T='Assets/images/tiles/'
wall=Image.open(T+'wall_face.png').convert('RGBA')
floor=Image.open(T+'floor.png').convert('RGBA')
roof=Image.open(T+'roof.png').convert('RGBA')
puz=Image.open(T+'puzzle_tiles.png').convert('RGBA')
PIDX={'S':0,'G':1,'N':2,'B':3,'X':4,'x':5,'C':6,'D':7}
def load(p):
    rows=open(p).read().split('\n'); w=max(len(r) for r in rows)
    return [list(r.ljust(w)) for r in rows]
def walkable(ch): return ch not in ('#',' ')
def face_depths(g):
    H,W=len(g),len(g[0]); d=[[0]*W for _ in range(H)]
    for r in range(H-1,-1,-1):
        for c in range(W):
            if g[r][c]!='#': continue
            below=g[r+1][c] if r+1<H else ' '
            if walkable(below) and below!='D': d[r][c]=1
            elif below=='#' and r+1<H and 0<d[r+1][c]<3: d[r][c]=d[r+1][c]+1
    return d
def panel_slices(L):
    if L<=8: parts=[L]
    else:
        k=max(1,round(L/6)); base=L//k; parts=[base+(1 if i<L%k else 0) for i in range(k)]
    out=[]
    for n in parts:
        if n==1: out+= [1]; continue
        s=[1]*n; s[0]=0; s[-1]=5
        if n>=4:
            m=(n-2)//2; s[m]=2; s[m+1]=3
            for i in range(m+2,n-1): s[i]=4
        out+=s
    return out
def face_columns(g,d):
    H,W=len(g),len(g[0]); col=[[None]*W for _ in range(H)]
    for r in range(H):
        c=0
        while c<W:
            if d[r][c]==1:
                c1=c
                while c1+1<W and d[r][c1+1]==1: c1+=1
                sl=panel_slices(c1-c+1)
                for i,cc in enumerate(range(c,c1+1)):
                    col[r][cc]=sl[i]
                    for k in (1,2):
                        if r-k>=0 and d[r-k][cc]==k+1: col[r-k][cc]=sl[i]
                c=c1+1
            else: c+=1
    return col
def render(g, scale=1):
    H,W=len(g),len(g[0]); d=face_depths(g); col=face_columns(g,d)
    img=Image.new('RGBA',(W*32,H*32),(18,18,22,255))
    def wk(c,r): return 0<=r<H and 0<=c<W and walkable(g[r][c])
    for r in range(H):
        for c in range(W):
            ch=g[r][c]; x,y=c*32,r*32
            if ch==' ': continue
            if ch=='#':
                if d[r][c]:
                    sx=col[r][c]*32; sy=(3-d[r][c])*32
                    img.alpha_composite(wall.crop((sx,sy,sx+32,sy+32)),(x,y))
                else:
                    m=(wk(c,r-1))|(wk(c+1,r)<<1)|(wk(c,r+1)<<2)|(wk(c-1,r)<<3)
                    m|=(wk(c+1,r-1)<<4)|(wk(c+1,r+1)<<5)|(wk(c-1,r+1)<<6)|(wk(c-1,r-1)<<7)
                    img.alpha_composite(roof.crop(((m%16)*32,(m//16)*32,(m%16)*32+32,(m//16)*32+32)),(x,y))
                continue
            # floor
            above_face = r>0 and g[r-1][c]=='#' and d[r-1][c]==1
            if above_face:
                img.alpha_composite(wall.crop((0,96,32,128)),(x,y))
            else:
                h=(c*73856093 ^ r*19349663)&0xffff
                v=0 if h%100<70 else (1 if h%100<85 else 2)
                img.alpha_composite(floor.crop((v*32,0,v*32+32,32)),(x,y))
            if ch in PIDX:
                t=puz.crop((PIDX[ch]*32,0,PIDX[ch]*32+32,32))
                if ch=='D' and ((c>0 and walkable(g[r][c-1]) and g[r][c-1]!='D') or (c+1<W and walkable(g[r][c+1]) and g[r][c+1]!='D')):
                    t=t.rotate(90)
                img.alpha_composite(t,(x,y))
            if ch=='P':
                pass
    if scale!=1: img=img.resize((img.width*scale,img.height*scale),Image.NEAREST)
    return img
if __name__=='__main__':
    g=load(sys.argv[1])
    im=render(g)
    a=Image.open('Assets/images/astronaut/astronaut.png')
    for r,row in enumerate(g):
        for c,ch in enumerate(row):
            if ch=='P': im.alpha_composite(a.crop((0,0,32,40)),(c*32,r*32+32-40+4))
    im.save(sys.argv[2])
    print(im.size)
