"""Placeholder brand sounds: Karplus-Strong plucked strings tuned like a dombra (D3-G3).
Replace with a real dombra recording later (brief: brand system > Sound and motion).
Run: python3 scripts/make_sounds.py  -> assets/sounds/*.wav (44.1 kHz, 16-bit mono)."""
import math, random, struct, wave, os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds')
random.seed(7)

def pluck(freq, dur, damp=0.996, bright=0.5, amp=1.0):
    n = int(SR / freq)
    buf = [random.uniform(-1, 1) for _ in range(n)]
    # soften the excitation (plucking with a finger, not a pick)
    for _ in range(int((1 - bright) * 4)):
        buf = [(buf[i] + buf[i - 1]) / 2 for i in range(n)]
    out = []
    for i in range(int(SR * dur)):
        v = buf[i % n]
        nxt = buf[(i + 1) % n]
        buf[i % n] = damp * 0.5 * (v + nxt)
        out.append(v * amp)
    return out

def knock(dur=0.08, freq=180):
    out = []
    for i in range(int(SR * dur)):
        t = i / SR
        out.append(math.sin(2 * math.pi * freq * t) * math.exp(-t * 60) * 0.9 + random.uniform(-1, 1) * math.exp(-t * 120) * 0.15)
    return out

def harmonic(freq, dur):
    out = []
    for i in range(int(SR * dur)):
        t = i / SR
        env = min(1, t / 0.004) * math.exp(-t * 14)
        out.append((math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(4 * math.pi * freq * t)) * env)
    return out

def mix(total, parts):
    out = [0.0] * int(SR * total)
    for start, sig in parts:
        s = int(SR * start)
        for i, v in enumerate(sig):
            if s + i < len(out):
                out[s + i] += v
    return out

def body(sig):
    # a little wooden body resonance: short comb + gentle low-pass
    y, prev = [], 0.0
    d = int(SR * 0.0023)
    for i, v in enumerate(sig):
        r = v + (0.35 * sig[i - d] if i >= d else 0)
        prev = prev + 0.45 * (r - prev)
        y.append(prev)
    return y

def fade_out(sig, ms=40):
    n = int(SR * ms / 1000)
    for i in range(n):
        sig[-n + i] *= 1 - i / n
    return sig

def write(name, sig, peak_db=-3.0):
    sig = fade_out(body(sig))
    peak = max(abs(v) for v in sig) or 1
    g = (10 ** (peak_db / 20)) / peak
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v * g)) * 32767)) for v in sig))

D3, G3, D4, G4 = 146.83, 196.00, 293.66, 392.00
os.makedirs(OUT, exist_ok=True)
# Match: two open strings a fourth apart, low then high, ringing together
write('match.wav', mix(0.85, [(0.0, pluck(D3, 0.85)), (0.09, pluck(G3, 0.76))]))
# Like: one soft muted pluck
write('like.wav', mix(0.16, [(0.0, pluck(G3, 0.16, damp=0.95, bright=0.2))]), peak_db=-8)
# Super like: quick strum (kagys) across both strings, down then up
write('super.wav', mix(0.36, [(0.0, pluck(D3, 0.36, 0.99)), (0.025, pluck(G3, 0.33, 0.99)),
                               (0.15, pluck(G3, 0.21, 0.985)), (0.17, pluck(D3, 0.19, 0.985))]), peak_db=-5)
# New message: single high harmonic
write('message.wav', harmonic(G4 * 2, 0.2), peak_db=-10)
# Event check-in: pluck + low wooden knock
write('checkin.wav', mix(0.42, [(0.0, knock()), (0.05, pluck(D4, 0.37, 0.993))]), peak_db=-5)
print('wrote', sorted(os.listdir(OUT)))
