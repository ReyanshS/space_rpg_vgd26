# sfx_crate.py: the sound of a movable crate rolling one tile (push.wav).
# A soft thump as it starts, then the rumble of its little wheels: noise that
# goes through a simple low pass filter (each sample is mostly the one before),
# fading in and out. Same idea as sfx.py, but only needs plain Python (no numpy).
# Only writes Assets/audio/push.wav. Run from the project folder:
#     python tools/sfx_crate.py
import math, random, struct, wave

SR = 44100
random.seed(7)


def save(name, xs, vol=0.7):
    peak = max(abs(x) for x in xs) or 1.0
    with wave.open('Assets/audio/' + name, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(x / peak * vol * 32767)) for x in xs))


def push():
    n = int(SR * 0.24)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / SR
        # the thump: a low tone that dies away fast
        thump = math.sin(2 * math.pi * 70 * t) * math.exp(-t * 40) * 1.2
        # the wheels: low-passed noise with a slight wobble (each wheel bump)
        lp = lp * 0.93 + random.uniform(-1, 1) * 0.07
        wobble = 0.7 + 0.3 * math.sin(2 * math.pi * 26 * t)
        env = min(1.0, t / 0.03) * max(0.0, 1.0 - t / 0.24)
        out.append(thump + lp * 6.0 * wobble * env)
    save('push.wav', out, 0.55)


push()
print('wrote Assets/audio/push.wav')
