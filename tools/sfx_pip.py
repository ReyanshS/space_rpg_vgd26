# sfx_pip.py - the sounds for Level 3's rogue PIP, made the same way as sfx.py
# (sine waves, square waves, noise and volume envelopes - no recordings).
# Only writes these files, so the other sounds stay exactly as they are:
#   glitch.wav      PIP's voice breaking up (malfunction, getting hit)
#   pulse.wav       his shutdown pulse that cuts your wire
#   warn.wav        one beep of his shutdown meter (it beeps faster near the end)
#   boot.wav        PIP rebooting: a rising start-up chime
# (The boss music used to be made here too; it's now the team's own track,
#  Assets/audio/music_core.ogg.)
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

print('written: glitch, pulse, warn, boot')
