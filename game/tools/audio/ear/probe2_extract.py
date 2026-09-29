import json, os

BASE = r"C:\Users\fixme\Desktop\flesh-pit-main\game\tools\audio\samples\src"
OUT_DIR = r"C:\Users\fixme\Desktop\flesh-pit-main\game\tools\audio\ear\raw_probe_out"
os.makedirs(OUT_DIR, exist_ok=True)

import wave
import numpy as np

def load_wav(path):
    with wave.open(path, "rb") as w:
        ch = w.getnchannels(); rate = w.getframerate(); n = w.getnframes()
        raw = w.readframes(n)
    data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    data = data.reshape(-1, ch)
    return data.mean(axis=1), rate

def write_wav(path, mono, rate):
    pcm = np.clip(mono, -1.0, 32767.0/32768.0)
    pcm = np.round(pcm * 32768.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())

# candidates: (name, relpath, offset_s, dur_s)
candidates = [
    ("chew_full_start", "chew/fs22416.wav", 0.0, 4.0),
    ("chew_full_mid", "chew/fs22416.wav", 4.0, 4.0),
    ("vomit_full_a", "vomit/fs338116.wav", 0.0, 4.0),
    ("vomit_full_b", "vomit/fs338116.wav", 20.0, 4.0),
    ("vomit_full_c", "vomit/fs338116.wav", 60.0, 4.0),
    ("tile_full", "tile/fs816017.wav", 0.0, 3.0),
    ("body_full", "body/fs214865.wav", 0.0, 4.0),
]

for name, rel, off, dur in candidates:
    path = os.path.join(BASE, rel)
    mono, rate = load_wav(path)
    off_n = int(off * rate)
    dur_n = int(dur * rate)
    seg = mono[off_n:off_n+dur_n]
    if seg.size == 0:
        print(name, "EMPTY - file too short, total sec =", mono.size/rate)
        continue
    out_path = os.path.join(OUT_DIR, name + ".wav")
    write_wav(out_path, seg, rate)
    print(name, "written", seg.size/rate, "sec, total file sec =", mono.size/rate)
