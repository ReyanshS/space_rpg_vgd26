# sfx_pip.py - the sounds for Level 3's rogue PIP, made the same way as sfx.py
# (sine waves, square waves, noise and volume envelopes - no recordings).
# Only writes these files, so the other sounds stay exactly as they are:
#   glitch.wav      PIP's voice breaking up (malfunction, getting hit)
#   pulse.wav       his shutdown pulse that cuts your wire
#   warn.wav        one beep of his shutdown meter (it beeps faster near the end)
#   boot.wav        PIP rebooting: a rising start-up chime
#   music_core.wav  the boss loop for the core chamber (exactly 8 bars, loops cleanly)
# Run from the project folder:   python tools/sfx_pip.py
import numpy as np, wave
SR = 44100
rng = np.random.default_rng(31)


def t(d): return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=0.1):
    e = np.ones(n); A = int(SR * a); R = int(SR * r)
    if A: e[:A] = np.linspace(0, 1, A)
    if R: e[-R:] *= np.linspace(1, 0, R)
    return e


def save(name, x, vol=0.8):
    x = np.clip(x / (np.abs(x).max() + 1e-9) * vol, -1, 1)
    with wave.open('Assets/audio/' + name, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def square(tt, f): return np.sign(np.sin(2 * np.pi * f * tt))


# glitch: short random square-wave blips that jump between pitches, with dropouts
parts = []
for i in range(14):
    d = rng.uniform(0.02, 0.06); tt = t(d)
    f = rng.choice([180, 240, 320, 480, 640, 960, 1280])
    blip = square(tt, f) * (0.5 if rng.random() < 0.8 else 0.0)
    blip += rng.uniform(-1, 1, len(tt)) * 0.15
    parts.append(blip * env(len(tt), 0.001, 0.005))
x = np.concatenate(parts)
x = np.round(x * 4) / 4                       # "bit crush": only 9 loudness steps = crunchy
save('glitch.wav', x * env(len(x), 0.002, 0.05), 0.55)

# pulse: a deep falling boom + a buzzy sweep down + crackle
d = 0.9; tt = t(d)
f = np.linspace(420, 40, len(tt))
sweep = np.sin(2 * np.pi * np.cumsum(f) / SR)
buzz = square(tt, 55) * np.exp(-tt * 3) * 0.35
noise = rng.uniform(-1, 1, len(tt)) * np.exp(-tt * 6) * 0.5
save('pulse.wav', (sweep * 0.7 + buzz + noise) * env(len(tt), 0.002, 0.3), 0.85)

# warn: one short high beep
d = 0.09; tt = t(d)
save('warn.wav', (square(tt, 1760) * 0.4 + np.sin(2 * np.pi * 880 * tt) * 0.5) * env(len(tt), 0.002, 0.04), 0.4)

# boot: three rising notes, then a bright held chord
notes = [523.25, 659.25, 783.99]
parts = []
for f in notes:
    tt = t(0.12)
    parts.append((np.sin(2 * np.pi * f * tt) + 0.3 * square(tt, f)) * env(len(tt), 0.003, 0.04))
tt = t(0.9)
chord = sum(np.sin(2 * np.pi * f * 2 * tt) for f in notes) * np.exp(-tt * 3)
parts.append(chord)
save('boot.wav', np.concatenate(parts), 0.6)

# music_core: 4 s per pass x 2 = 8 s. A pulsing bass on the beat, a nervous
# arpeggio in A minor, and a ticking hi-hat. Every note starts and ends inside
# the loop, so it repeats without a click.
bpm = 120.0; beat = 60.0 / bpm; bars = 4
total = int(SR * beat * 4 * bars)
mix = np.zeros(total)


def add(start_s, sig):
    i = int(start_s * SR)
    n = min(len(sig), total - i)
    if n > 0: mix[i:i + n] += sig[:n]


bass_roots = [55.0, 55.0, 43.65, 49.0]                   # A, A, F, G
arp = [[220, 261.63, 329.63, 261.63], [220, 261.63, 329.63, 392.0],
       [174.61, 220, 261.63, 220], [196, 246.94, 293.66, 246.94]]
for b in range(bars):
    for k in range(4):                                     # bass: every beat, a short "doom"
        tt = t(beat * 0.9)
        f = bass_roots[b]
        add((b * 4 + k) * beat, (np.sin(2 * np.pi * f * tt) + 0.4 * square(tt, f)) * np.exp(-tt * 5) * 0.6)
    for k in range(8):                                     # arpeggio: eighth notes
        tt = t(beat * 0.45)
        f = arp[b][k % 4] * 2
        add((b * 4 + k * 0.5) * beat, square(tt, f) * env(len(tt), 0.002, 0.08) * 0.12)
    for k in range(16):                                    # hi-hat: sixteenth ticks
        tt = t(0.03)
        add((b * 4 + k * 0.25) * beat, rng.uniform(-1, 1, len(tt)) * np.exp(-tt * 120) * (0.18 if k % 4 == 2 else 0.08))
loop = np.concatenate([mix, mix])
save('music_core.wav', loop, 0.6)
print('written: glitch, pulse, warn, boot, music_core')
