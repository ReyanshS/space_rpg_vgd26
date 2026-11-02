# astro2.py - builds the v2 astronaut sheet (Assets/images/astronaut/astronaut_v2.png).
# Each body part is drawn as a small text picture (one letter = one colour in PAL),
# parts are stacked per frame (bobbing, swinging legs...), then a dark outline is
# added automatically. Run from the project folder:  python tools/astro2.py
# Frame order is saved to tools/out/astronaut2_anims.json; astronaut_v2_frames.tres
# expects 29 frames of 32x40 in that order.
# New astronaut sprite: drawn from ASCII part templates, composited per frame,
# then outlined automatically so every frame shares the same clean outline.
import numpy as np, json
from PIL import Image
PAL={
 'W':(238,234,226),'w':(196,192,198),'v':(150,146,162),
 'D':(30,36,68),'d':(46,58,104),'L':(160,190,240),'l':(96,122,182),
 'B':(140,140,152),'b':(98,98,112),
 'G':(124,112,152),'g':(88,78,116),
 'S':(160,160,170),'s':(110,110,124),
 'R':(206,52,66),'r':(132,26,42),
 'Y':(255,214,64),'y':(160,112,20),
}
OUT=(24,20,34)
def P(rows): return [r for r in rows]

HELMET_F=P(["......WWWW......","...WWWWWWWWWW...","..WWWWWWWWWWWW..",".WWWWWWWWWWWWWW.",
 ".WWWdDDDDDDdWWW.","WWWdDDDDDDDLLdWW","WWWDDDDDDDDDLDWW","WWWDDDDDDDDDDDWW","WWWDDDDDDDDDDDWW",
 "wWWdDDDDDDDDDdWw",".wWWdDDDDDDDdWw.",".wwWWWWWWWWWWww.","..wwwWWWWWWwww..","....wwwwwwww...."])
HELMET_B=P(["......WWWW......","...WWWWWWWWWW...","..WLWWWWWWWWWW..",".WLWWWWWWWWWWWw.",
 ".WWWWWWWWWWWWWw.","WWWWWWWWWWWWWWww","WWWWWWWWWWWWWWww","WWWWWWWWWWWWWWww","WWWWWWWWWWWWWWww",
 "wWWWWWWWWWWWWWww",".wWWWWWWWWWWWww.",".wwWWWWWWWWWWww.","..wwwwwwwwwwww..","....wwwwwwww...."])
HELMET_S=P([".....WWWWW.....","...WWWWWWWWW...","..WWWWWWWWWWW..",".WWWWWWWWWWWWW.",
 ".WWWWWWWdDDDDW.","WWWWWWWdDDDLLDW","WWWWWWWDDDDDLDW","WWWWWWWDDDDDDDW","WWWWWWWDDDDDDDW",
 "wWWWWWWdDDDDDdW",".wWWWWWWdDDDdW.",".wwWWWWWWWWWWw.","..wwwwWWWWwww..","....wwwwwww...."])
TORSO_F=P(["..WWWWWWWWWW..",".WWWWWWWWWWWW.",".WWWWWRRWWWWW.",".WWWWWrrWWWWW.",".WWWWWWWWWWWW.",
 ".wWWWWWWWWWWw.",".vvvvvvvvvvvv.",".wWWWWWWWWWWw.","..wWWWWWWWWw..","..wwWWWWWWww.."])
TORSO_B=P(["..WWWWWWWWWW..",".WWWWWWWWWWWW.",".WWWWWWWWWWWW.",".WWWWWWWWWWWW.",".WWWWWWWWWWWW.",
 ".wWWWWWWWWWWw.",".vvvvvvvvvvvv.",".wWWWWWWWWWWw.","..wWWWWWWWWw..","..wwWWWWWWww.."])
PACK_B=P([".BBBBBBBBBB.","BBBBBBBBBBBB","BbbBBBBBBbbB","BbbBBBBBBbbB","BBBBBBBBBBBB",
 "BBBBbbbbBBBB","BBBBBBBBBBBB","bBBBBBBBBBBb",".bbbbbbbbbb."])
TORSO_S=P([".WWWWWWWW.","WWWWWWWWWW","WWWWWWWWRW","WWWWWWWWrW","WWWWWWWWWW",
 "wWWWWWWWWw","vvvvvvvvvv","wWWWWWWWWw",".wWWWWWWw.",".wwWWWWww."])
PACK_S=P([".BBB.","BBBBB","BbBBB","BbBBB","BBBBB","BbBBB","BbBBB","BBBBB","bBBBb",".bbb."])
ARM_L=P([".WW.","WWWW","WWWw","WWWw","wWWw","wWWw","GGGG","GGGg",".gg."])
ARM_S=P([".vW.","vWWW","vWWw","vWWw","vWWw","GGGG","gGGg",".gg."])
LEG=P(["WWWWW","WWWWw","wWWWw","wWWWw","SSSSS","SSSSs","sssss"])
CARRY_L=P([".WW..","WWWW.","WWWWW",".wWWW","..GGG","..GGg","...gg"])
PLUG=P(["yYYy","YYYY",".yy."])

def mirror(rows): return [r[::-1] for r in rows]
def shade(rows):   # darker copy for the far leg/arm
    m={'W':'w','w':'v','S':'s','s':'s','G':'g'}
    return [''.join(m.get(c,c) for c in r) for r in rows]

CW,CH=32,40
def blank(): return [['.']*CW for _ in range(CH)]
def stamp(cv,rows,x,y):
    for j,r in enumerate(rows):
        for i,c in enumerate(r):
            if c!='.' and 0<=y+j<CH and 0<=x+i<CW: cv[y+j][x+i]=c
def render(cv, outline=OUT, recolor=None):
    img=np.zeros((CH,CW,4),np.uint8)
    filled=np.array([[c!='.' for c in r] for r in cv])
    for y in range(CH):
        for x in range(CW):
            c=cv[y][x]
            if c!='.':
                col=PAL[c] if recolor is None else recolor(c,PAL[c])
                img[y,x]=(*col,255)
    # auto outline: transparent pixels touching a filled pixel (4-neighbour)
    for y in range(CH):
        for x in range(CW):
            if filled[y,x]: continue
            if any(0<=y+dy<CH and 0<=x+dx<CW and filled[y+dy,x+dx] for dx,dy in ((1,0),(-1,0),(0,1),(0,-1))):
                img[y,x]=(*outline,255)
    return img

# ---- poses -------------------------------------------------------------
FEET=39
def front(phase=0, bob=0, carry=False):
    cv=blank()
    # phase: 0 neutral, 1 left leg lifted, 2 neutral, 3 right leg lifted
    ll = 2 if phase==1 else 0; rl = 2 if phase==3 else 0
    stamp(cv,LEG,10,FEET-6-ll); stamp(cv,LEG,17,FEET-6-rl)
    body=-bob
    stamp(cv,TORSO_F,9,24+body)
    if carry:
        stamp(cv,CARRY_L,8,25+body); stamp(cv,mirror(CARRY_L),19,25+body)
        stamp(cv,PLUG,14,31+body)
    else:
        sw = 1 if phase==1 else (-1 if phase==3 else 0)
        stamp(cv,ARM_L,6,25+body+sw); stamp(cv,mirror(ARM_L),22,25+body-sw)
    stamp(cv,HELMET_F,8,11+body)
    return cv
def back(phase=0, bob=0):
    cv=blank()
    ll = 2 if phase==1 else 0; rl = 2 if phase==3 else 0
    stamp(cv,LEG,10,FEET-6-ll); stamp(cv,LEG,17,FEET-6-rl)
    body=-bob
    stamp(cv,TORSO_B,9,24+body)
    sw = 1 if phase==1 else (-1 if phase==3 else 0)
    stamp(cv,ARM_L,6,25+body-sw); stamp(cv,mirror(ARM_L),22,25+body+sw)
    stamp(cv,PACK_B,10,24+body)
    stamp(cv,HELMET_B,8,11+body)
    return cv
def side(phase=0, bob=0):
    # facing right. phase 0/2 legs together, 1: front leg forward, 3: back leg forward
    cv=blank()
    fx={0:0,1:3,2:0,3:-3}[phase]; bx=-fx
    stamp(cv,shade(LEG),12+bx,FEET-6-(1 if phase==3 else 0))   # far leg
    body=-bob
    stamp(cv,PACK_S,7,23+body)
    stamp(cv,TORSO_S,10,24+body)
    stamp(cv,LEG,13+fx,FEET-6-(1 if phase==1 else 0))           # near leg
    stamp(cv,HELMET_S,8,11+body)
    ax={0:0,1:-2,2:0,3:2}[phase]
    stamp(cv,ARM_S,13+ax,25+body)
    return cv

frames=[]; anims={}
def add(name, imgs):
    anims[name]=list(range(len(frames),len(frames)+len(imgs))); frames.extend(imgs)
add('idle_down',[render(front(0,0)),render(front(0,1))])
add('idle_up',[render(back(0,0)),render(back(0,1))])
add('idle_right',[render(side(0,0)),render(side(0,1))])
add('idle_left',[render(side(0,0))[:, ::-1],render(side(0,1))[:, ::-1]])
add('walk_down',[render(front(p,1 if p in (1,3) else 0)) for p in range(4)])
add('walk_up',[render(back(p,1 if p in (1,3) else 0)) for p in range(4)])
add('walk_right',[render(side(p,1 if p in (1,3) else 0)) for p in range(4)])
add('walk_left',[render(side(p,1 if p in (1,3) else 0))[:, ::-1] for p in range(4)])
add('carry',[render(front(0,0,True)),render(front(0,1,True))])
# shocked: electric outline + tinted suit, two flashing frames
def zap_tint(c,col):
    return tuple(min(255,int(v*0.75+[120,220,255][i]*0.25)) for i,v in enumerate(col))
sA=render(front(0,0),outline=(120,240,255)); sB=render(front(0,1),outline=(255,230,90),recolor=zap_tint)
rng=np.random.default_rng(3)
for img,col in ((sA,(255,240,120)),(sB,(140,240,255))):
    for _ in range(14):
        x,y=int(rng.integers(3,29)),int(rng.integers(8,39))
        if img[y,x,3]==0: img[y,x]=(*col,255)
add('shock',[sA,sB])
def burn(c,col): return tuple(int(v*0.45) for v in col) if c in 'WwvSsGgBb' else col
bt=render(front(0,0),recolor=burn)
for (x,y) in [(13,27),(14,27),(19,30),(11,18),(20,16),(21,16)]: bt[y,x]=(20,18,20,255)
for (x,y) in [(12,8),(13,6),(20,7),(19,5),(21,4)]: bt[y,x]=(120,120,120,200)
add('burnt',[bt])

sheet=np.concatenate(frames,1)
Image.fromarray(sheet).save('Assets/images/astronaut/astronaut_v2.png')
json.dump(anims,open('tools/out/astronaut2_anims.json','w'))
prev=Image.new('RGBA',(sheet.shape[1],CH),(70,74,86,255)); prev.alpha_composite(Image.fromarray(sheet))
prev.resize((prev.width*4,CH*4),Image.NEAREST).save('tools/out/astro2_preview.png')
print(anims, sheet.shape)
