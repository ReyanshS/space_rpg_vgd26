# sfx.py - makes every sound in Assets/audio from scratch (no recordings, no downloads).
# Building blocks: sine waves (tones), random noise (crackle/static) and envelopes
# (how loud a sound is over time). The random generator is seeded, so running this
# again recreates exactly the same files. Edit a sound's recipe, then run:
#     python tools/sfx.py        (from the project folder; overwrites Assets/audio/*.wav)
import numpy as np, wave
SR=44100
rng=np.random.default_rng(7)
def t(d): return np.arange(int(SR*d))/SR
def env(n,a=0.005,r=0.1,total=None):
    e=np.ones(n); A=int(SR*a); R=int(SR*r)
    if A: e[:A]=np.linspace(0,1,A)
    if R: e[-R:]*=np.linspace(1,0,R)
    return e
def lp(x,k=8):
    return np.convolve(x,np.ones(k)/k,mode='same')
def save(name,x,vol=0.8):
    x=np.clip(x/ (np.abs(x).max()+1e-9) *vol,-1,1)
    with wave.open('Assets/audio/'+name,'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x*32767).astype(np.int16).tobytes())
def buzz(tt,f): # square-ish buzz
    return np.sign(np.sin(2*np.pi*f*tt))*0.5+np.sin(2*np.pi*f*2*tt)*0.3
def crackle(n,density=0.02):
    x=np.zeros(n); idx=rng.random(n)<density
    x[idx]=rng.uniform(-1,1,idx.sum())
    return lp(x,3)
# grab: rising buzz + click
d=0.28; tt=t(d); f=np.linspace(90,240,len(tt))
x=np.sign(np.sin(2*np.pi*np.cumsum(f)/SR))*0.4 + crackle(len(tt),0.05)*0.8
x[:300]+=rng.uniform(-1,1,300)*np.linspace(1,0,300)
save('grab.wav',x*env(len(tt),0.002,0.12),0.6)
# hum loop (exact 1s => integer cycles)
tt=t(1.0)
x=np.sin(2*np.pi*60*tt)*0.5+np.sin(2*np.pi*120*tt)*0.35+np.sign(np.sin(2*np.pi*180*tt))*0.08
x+=crackle(len(tt),0.004)*0.6
save('hum.wav',x,0.35)
# node: zap + chime
d=0.45; tt=t(d)
zap=rng.uniform(-1,1,len(tt))*np.exp(-tt*30)
ch=(np.sin(2*np.pi*880*tt)+0.5*np.sin(2*np.pi*1320*tt))*np.exp(-tt*6)
f=np.linspace(300,1200,len(tt)); sw=np.sin(2*np.pi*np.cumsum(f)/SR)*np.exp(-tt*10)*0.5
save('node.wav',zap*0.6+ch*0.6+sw,0.7)
# bend: click + short buzz
d=0.16; tt=t(d)
x=np.zeros(len(tt)); x[:120]=rng.uniform(-1,1,120)*np.linspace(1,0,120)
x+=buzz(tt,140)*np.exp(-tt*25)*0.6
save('bend.wav',x,0.6)
# shock: harsh crackle + 50Hz
d=0.9; tt=t(d)
x=crackle(len(tt),0.25)*1.0+buzz(tt,55)*0.4+rng.uniform(-1,1,len(tt))*0.25
am=(rng.random(len(tt)//800+1)>0.3).repeat(800)[:len(tt)]*1.0
x=x*(0.4+0.6*am)*env(len(tt),0.001,0.3)
save('shock.wav',x,0.85)
# snap: wire snaps / fizzles
d=0.6; tt=t(d)
f=np.linspace(700,90,len(tt))
x=np.sin(2*np.pi*np.cumsum(f)/SR)*np.exp(-tt*5)*0.6+crackle(len(tt),0.08)*np.exp(-tt*4)
x[:200]+=rng.uniform(-1,1,200)
save('snap.wav',x,0.7)
# power-up sweep
d=1.3; tt=t(d)
f=110*2**(tt/d*3)
x=np.sin(2*np.pi*np.cumsum(f)/SR)*0.5+np.sin(2*np.pi*np.cumsum(f*1.5)/SR)*0.25
x+=crackle(len(tt),0.02)*0.5
x*=env(len(tt),0.05,0.35)
save('powerup.wav',x,0.7)
# door: servo whoosh
d=0.7; tt=t(d)
n=lp(rng.uniform(-1,1,len(tt)),30)*3
f=np.linspace(220,160,len(tt))
x=n*np.sin(np.pi*tt/d)+np.sign(np.sin(2*np.pi*np.cumsum(f)/SR))*0.12*np.sin(np.pi*tt/d)
save('door.wav',x,0.6)
# complete jingle
notes=[523.25,659.25,783.99,1046.5]
x=np.concatenate([ (np.sign(np.sin(2*np.pi*nf*t(0.14)))*0.3+np.sin(2*np.pi*nf*t(0.14))*0.6)*env(int(SR*0.14),0.005,0.05) for nf in notes[:3]]+
                 [ (np.sign(np.sin(2*np.pi*notes[3]*t(0.6)))*0.3+np.sin(2*np.pi*notes[3]*t(0.6))*0.6)*np.exp(-t(0.6)*4)])
save('complete.wav',x,0.6)
# warning tick
tt=t(0.07); x=np.sin(2*np.pi*1600*tt)*np.exp(-tt*60)
save('tick.wav',x,0.5)
print('ok')
