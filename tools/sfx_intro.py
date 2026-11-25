# sfx_intro.py: the sounds under the intro cutscene, one per picture, made the
# same way as sfx.py (sine waves, square waves, noise and volume envelopes).
# Each one loops cleanly (the picture stays until you press E), so every tone
# fits a whole number of times into the loop and the noise is made round too.
#   intro_alarm.wav   picture 1, the cryostasis warning: a two tone klaxon and beeps
#   intro_space.wav   picture 2, the station by Uranus: a deep drone and failing power
#   intro_wake.wav    picture 3, "wake up": a heartbeat and slow breathing
# Only writes these files. Run from the project folder:   python tools/sfx_intro.py
import numpy as np, wave
SR = 44100
rng = np.random.default_rng(57)


def t(d): return np.arange(int(SR * d)) / SR


def save(name, x, vol=0.8):
    x = np.clip(x / (np.abs(x).max() + 1e-9) * vol, -1, 1)
    with wave.open('Assets/audio/' + name, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def round_noise(n, low_hz, high_hz):
    """Noise that loops without a click: made in the frequency domain (FFT),
    keeping only low_hz..high_hz, so it repeats seamlessly every n samples."""
    spec = np.fft.rfft(rng.uniform(-1, 1, n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec[(f < low_hz) | (f > high_hz)] = 0
    return np.fft.irfft(spec, n)


def env(n, a, r):
    e = np.ones(n); A = int(SR * a); R = int(SR * r)
    if A: e[:A] = np.linspace(0, 1, A)
    if R: e[-R:] *= np.linspace(1, 0, R)
    return e


def add(mix, start_s, sig):
    i = int(start_s * SR)
    n = min(len(sig), len(mix) - i)
    mix[i:i + n] += sig[:n]


# picture 1: klaxon. 2 s loop: a low "wah" and a high "wah", then two beeps.
L = 2.0
mix = np.zeros(int(SR * L))
for k, f in enumerate((370.0, 494.0)):
    tt = t(0.45)
    tone = np.sign(np.sin(2 * np.pi * f * tt)) * 0.5 + np.sin(2 * np.pi * f * 2 * tt) * 0.3
    add(mix, k * 0.5, tone * env(len(tt), 0.03, 0.12) * 0.55)
for k in range(2):
    tt = t(0.07)
    add(mix, 1.3 + k * 0.18, np.sin(2 * np.pi * 1760 * tt) * env(len(tt), 0.003, 0.03) * 0.35)
tt = t(L)
mix += np.sin(2 * np.pi * 55 * tt) * 0.12          # the ship's hum underneath (110 whole cycles)
save('intro_alarm.wav', mix, 0.55)

# picture 2: deep space. 4 s loop: a slow drone and a power-failing warble.
L = 4.0
tt = t(L)
drone = np.sin(2 * np.pi * 41 * tt) * 0.5 + np.sin(2 * np.pi * 61.5 * tt) * 0.3 \
    + np.sin(2 * np.pi * 82.25 * tt) * 0.15
drone *= 0.75 + 0.25 * np.sin(2 * np.pi * 0.25 * tt)            # swells once per loop
rumble = round_noise(len(tt), 20, 140) * 2.5
mix = drone + rumble
wt = t(1.6)
f = np.linspace(330, 110, len(wt))                               # a sound running down
warble = np.sin(2 * np.pi * np.cumsum(f) / SR) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * wt))
add(mix, 1.4, warble * env(len(wt), 0.2, 0.8) * 0.25)
save('intro_space.wav', mix, 0.5)

# picture 3: waking up. 2 s loop: a heartbeat (lub dub) and one slow breath.
L = 2.0
mix = np.zeros(int(SR * L))
for start, f, amp in ((0.0, 52.0, 1.0), (0.22, 46.0, 0.7)):
    bt = t(0.18)
    add(mix, start, np.sin(2 * np.pi * f * bt) * np.exp(-bt * 22) * amp)
breath = round_noise(len(mix), 300, 2200)
tt = t(L)
mix += breath * (0.5 - 0.5 * np.cos(2 * np.pi * tt / L)) * 1.2   # in and out once per loop
save('intro_wake.wav', mix, 0.6)
print('written: intro_alarm, intro_space, intro_wake')
